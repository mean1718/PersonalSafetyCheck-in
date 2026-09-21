const crypto = require("crypto");
const User = require("../models/User");
const Payment = require("../models/Payment");
const Notification = require("../models/Notification");
const { buildIndividualKHQR } = require("../utils/khqr");
const { checkTransactionByMd5 } = require("../services/bakongClient");
const { sendPushToUser } = require("../services/pushService");
const { activeExtraSlots } = require("../utils/extraSlots");

const EXTRA_SLOTS_DURATION_MS = 24 * 60 * 60 * 1000;

const PRO_DURATION_MS = 30 * 24 * 60 * 60 * 1000; // one billing month
// How long after the QR's own expiry we still accept a confirmation. A bank
// can settle a transfer a few seconds after the QR window closes; without
// this grace a person who paid at the last moment was told "expired".
const LATE_PAYMENT_GRACE_MS = 60 * 1000;
const MAX_EXTRA_PER_TYPE = 50;

const PRO_MONTHLY_PRICE_USD = 2.99;
const PRICE_PER_CONTACT_USD = 0.2;

const ACCOUNT_CURRENCY = (
  process.env.BAKONG_ACCOUNT_CURRENCY || "KHR"
).toUpperCase();

// Which currencies a customer is allowed to request the KHQR in. Cambodian
// bank/Bakong accounts (ABA etc.) commonly hold both a USD and a KHR
// balance under the SAME account ID/username — Bakong routes an incoming
// transfer into whichever sub-balance matches the currency printed on the
// QR. So the same BAKONG_ACCOUNT_USERNAME can issue either currency; we
// don't need a second account to support both.
const ALLOWED_QR_CURRENCIES = ["USD", "KHR"];

const accountInfo = () => {
  const bakongAccountId = process.env.BAKONG_ACCOUNT_USERNAME;
  const merchantName = process.env.BAKONG_ACCOUNT_NAME;
  const merchantCity = process.env.BAKONG_MERCHANT_CITY || "Phnom Penh";

  if (!bakongAccountId || !merchantName) {
    throw new Error(
      "BAKONG_ACCOUNT_USERNAME and BAKONG_ACCOUNT_NAME must be set in " +
        "backend_SafetyU/src/config/.env — find both on the ABA Mobile / " +
        "Bakong app's own 'My QR' screen (Account details -> Bakong " +
        "Account ID / Account Name). No need to export or decode a QR image.",
    );
  }
  return { bakongAccountId, merchantName, merchantCity };
};

const usdToKhr = (usd) => {
  const rate = Number(process.env.BAKONG_USD_TO_KHR_RATE) || 4100;
  return Math.round(usd * rate);
};

// Picks the currency to actually print on the KHQR for this request.
// Falls back to the account's configured default (ACCOUNT_CURRENCY) if the
// client didn't send a recognized one, rather than rejecting the request —
// keeps older app builds that don't send `currency` at all working exactly
// as before.
const resolveQrCurrency = (requested) => {
  const normalized = String(requested || "").toUpperCase();
  return ALLOWED_QR_CURRENCIES.includes(normalized)
    ? normalized
    : ACCOUNT_CURRENCY;
};

const hasKhqrAmount = (qrString) => {
  let index = 0;
  while (index + 4 <= qrString.length) {
    const tag = qrString.slice(index, index + 2);
    const length = Number(qrString.slice(index + 2, index + 4));
    if (!Number.isInteger(length) || length < 0) return false;
    if (tag === "54") return length > 0;
    index += 4 + length;
  }
  return false;
};

// True only while a Pro plan is genuinely active. Older accounts that were
// marked Pro before proExpiresAt existed keep working (no expiry recorded).
const proIsActive = (user) =>
  !!user?.isPro &&
  (!user.proExpiresAt || new Date(user.proExpiresAt) > new Date());

// The plan state the app should show after a purchase. Always derived from
// the database, so the phone never has to guess or "credit locally".
const planSnapshot = (user) => {
  const active = activeExtraSlots(user);
  return {
    isPro: proIsActive(user),
    proExpiresAt: user?.proExpiresAt ?? null,
    purchasedExtraMainSlots: active.main,
    purchasedExtraOtherSlots: active.other,
    extraSlotsExpireAt: active.expiresAt,
  };
};

// Bakong's check_transaction_by_md5 answers "yes" for ANY transaction that
// ever matched that md5 — including an older one. Without checking the
// transaction itself, a new purchase whose QR hashes to the same md5 as an
// earlier paid one is instantly (and wrongly) confirmed with no payment.
// This makes sure the transaction Bakong returned really is THIS payment.
const verifyBakongTransaction = (payment, raw) => {
  const tx = raw?.data;
  if (!tx || typeof tx !== "object") return { ok: true }; // nothing to compare

  const createdMs = Number(tx.createdDateMs ?? tx.acknowledgedDateMs);
  if (Number.isFinite(createdMs) && createdMs > 0) {
    const earliestOk = new Date(payment.createdAt).getTime() - 2 * 60 * 1000;
    if (createdMs < earliestOk) {
      return { ok: false, reason: "transaction is older than this payment" };
    }
  }

  const qrCurrency = payment.qrCurrency || "USD";
  if (tx.currency && String(tx.currency).toUpperCase() !== qrCurrency) {
    return { ok: false, reason: "currency does not match" };
  }

  const paidAmount = Number(tx.amount);
  const expectedAmount =
    payment.qrAmount ??
    (qrCurrency === "USD" ? payment.amount : usdToKhr(payment.amount));
  if (Number.isFinite(paidAmount) && tx.amount !== null) {
    const tolerance = qrCurrency === "USD" ? 0.005 : 1;
    if (Math.abs(paidAmount - expectedAmount) > tolerance) {
      return { ok: false, reason: "amount does not match" };
    }
  }
  return { ok: true };
};

// Applies a confirmed payment to the account EXACTLY ONCE, even if the app
// polls several times at the same moment (the old code could credit twice,
// or mark a payment paid and then fail before crediting it).
// Returns the updated user, or null if someone else already credited it.
const creditPayment = async (payment) => {
  const claim = await Payment.findOneAndUpdate(
    { _id: payment._id, credited: false },
    { $set: { credited: true } },
    { new: true },
  );
  if (!claim) return null;

  try {
    let user;
    if (payment.purpose === "pro_subscription") {
      const existing = await User.findById(payment.user).select(
        "isPro proExpiresAt",
      );
      // Renewing while still active adds a month on top instead of losing
      // the time that was already paid for.
      const base =
        proIsActive(existing) && existing.proExpiresAt
          ? new Date(existing.proExpiresAt).getTime()
          : Date.now();
      user = await User.findByIdAndUpdate(
        payment.user,
        {
          $set: { isPro: true, proExpiresAt: new Date(base + PRO_DURATION_MS) },
        },
        { new: true },
      );
    } else {
      const existingUser = await User.findById(payment.user).select(
        "purchasedExtraMainSlots purchasedExtraOtherSlots extraSlotsExpireAt",
      );
      const active = activeExtraSlots(existingUser);
      user = await User.findByIdAndUpdate(
        payment.user,
        {
          $set: {
            purchasedExtraMainSlots: active.main + payment.extraMainSlots,
            purchasedExtraOtherSlots: active.other + payment.extraOtherSlots,
            extraSlotsExpireAt: new Date(Date.now() + EXTRA_SLOTS_DURATION_MS),
          },
        },
        { new: true },
      );
    }
    if (!user) throw new Error("User not found while crediting payment.");
    return user;
  } catch (error) {
    // Crediting failed — release the flag so the next status poll retries
    // instead of leaving the person "paid but never upgraded".
    await Payment.updateOne(
      { _id: payment._id },
      { $set: { credited: false } },
    );
    throw error;
  }
};

const notifyPaymentConfirmed = async (payment) => {
  try {
    const paymentLabel =
      payment.purpose === "pro_subscription"
        ? "Pro subscription (1 month)"
        : `${payment.extraContacts} extra contact slot${payment.extraContacts === 1 ? "" : "s"} (24 hours)`;
    const paymentMessage = `Your payment of $${payment.amount.toFixed(2)} for ${paymentLabel} was confirmed.`;
    await Notification.create({
      receiver: payment.user,
      sender: payment.user,
      type: "payment_confirmed",
      title: "Payment confirmed",
      message: paymentMessage,
    });
    sendPushToUser(payment.user, {
      title: "Payment confirmed",
      body: paymentMessage,
      data: {
        type: "payment_confirmed",
        paymentId: payment._id.toString(),
      },
    });
  } catch (error) {
    // A missing receipt must never undo a payment that really went through.
    console.warn("[payment] could not send confirmation:", error.message);
  }
};

// GET /api/payments/pricing
// Public (no auth) — lets the frontend always show the real, current price
// instead of keeping its own hardcoded copy that can drift out of sync.
const getPricing = async (req, res) => {
  res.json({
    proMonthlyPriceUsd: PRO_MONTHLY_PRICE_USD,
    pricePerContactUsd: PRICE_PER_CONTACT_USD,
  });
};

// POST /api/payments/khqr
// Body: { purpose: 'pro_subscription', currency?: 'USD' | 'KHR' }
//    or { purpose: 'pay_per_contact', extraMain?, extraOther?, currency?: 'USD' | 'KHR' }
const createKhqrPayment = async (req, res) => {
  const purpose = req.body.purpose;
  const extraMain = Math.min(
    MAX_EXTRA_PER_TYPE,
    Math.max(0, Math.floor(Number(req.body.extraMain) || 0)),
  );
  const extraOther = Math.min(
    MAX_EXTRA_PER_TYPE,
    Math.max(0, Math.floor(Number(req.body.extraOther) || 0)),
  );
  const extraContacts = extraMain + extraOther;
  const qrCurrency = resolveQrCurrency(req.body.currency);

  if (!["pro_subscription", "pay_per_contact"].includes(purpose)) {
    return res.status(400).json({ message: "Invalid purpose." });
  }
  if (purpose === "pay_per_contact" && extraContacts < 1) {
    return res
      .status(400)
      .json({ message: "Select at least one extra contact to pay for." });
  }

  const amountUsd =
    purpose === "pro_subscription"
      ? PRO_MONTHLY_PRICE_USD
      : Math.round(extraContacts * PRICE_PER_CONTACT_USD * 100) / 100;
  const qrAmount = qrCurrency === "USD" ? amountUsd : usdToKhr(amountUsd);

  try {
    // Hand back the still-valid QR from a moment ago (double tap, reopened
    // dialog) instead of creating a second one — but only if it has a
    // useful amount of time left and is for exactly the same thing.
    const existing = await Payment.findOne({
      user: req.user.id,
      purpose,
      status: "pending",
      credited: false,
      expiresAt: { $gt: new Date(Date.now() + 60 * 1000) },
      qrCurrency,
      ...(purpose === "pay_per_contact"
        ? { extraMainSlots: extraMain, extraOtherSlots: extraOther }
        : {}),
    });
    if (existing) {
      if (!hasKhqrAmount(existing.qrString)) {
        existing.status = "expired";
        await existing.save();
      } else {
        return res.status(200).json({
          paymentId: existing._id,
          purpose: existing.purpose,
          qrString: existing.qrString,
          md5: existing.md5,
          amount: existing.amount,
          currency: existing.currency,
          qrAmount: existing.qrAmount ?? qrAmount,
          qrCurrency: existing.qrCurrency,
          expiresAt: existing.expiresAt,
        });
      }
    }

    // Every QR must hash to an md5 that has never been used before —
    // otherwise Bakong reports the OLD transaction for the new QR (wrongly
    // "paid" instantly, or never matching the new transfer). If a
    // collision happens, regenerate with a different bill number / store
    // label until it is unique.
    let generated = null;
    for (let attempt = 0; attempt < 5 && !generated; attempt += 1) {
      const candidate = buildIndividualKHQR({
        ...accountInfo(),
        currency: qrCurrency,
        amount: qrAmount,
        billNumber: crypto.randomBytes(6).toString("hex"),
        ...(attempt > 0
          ? { storeLabel: `SU${crypto.randomBytes(4).toString("hex")}` }
          : {}),
      });
      const taken = await Payment.exists({ md5: candidate.md5 });
      if (!taken) generated = candidate;
    }
    if (!generated) {
      console.error("[createKhqrPayment] could not produce a unique md5");
      return res.status(503).json({
        message: "Could not generate a unique payment QR. Please try again.",
      });
    }

    const payment = await Payment.create({
      user: req.user.id,
      purpose,
      extraContacts: purpose === "pay_per_contact" ? extraContacts : 0,
      extraMainSlots: purpose === "pay_per_contact" ? extraMain : 0,
      extraOtherSlots: purpose === "pay_per_contact" ? extraOther : 0,
      amount: amountUsd,
      currency: "USD",
      qrCurrency,
      qrAmount,
      qrString: generated.qrString,
      md5: generated.md5,
      expiresAt: generated.expiresAt,
    });

    return res.status(201).json({
      paymentId: payment._id,
      purpose: payment.purpose,
      qrString: payment.qrString,
      md5: payment.md5,
      amount: amountUsd,
      currency: "USD",
      qrAmount,
      qrCurrency,
      expiresAt: payment.expiresAt,
    });
  } catch (error) {
    console.error("[createKhqrPayment] failed:", error);
    const isDbError =
      typeof error.code !== "undefined" || error.name === "MongoServerError";
    return res.status(500).json({
      message: isDbError
        ? "Could not generate a payment QR right now. Please try again."
        : error.message || "Could not generate a payment QR.",
    });
  }
};

const paidResponse = (payment, user) => ({
  status: "paid",
  purpose: payment.purpose,
  extraMainSlots: payment.extraMainSlots,
  extraOtherSlots: payment.extraOtherSlots,
  ...planSnapshot(user),
});

// GET /api/payments/khqr/:md5/status
const checkKhqrStatus = async (req, res) => {
  try {
    // md5 is not unique across purchases, so scope by user and take the
    // newest record.
    let payment = await Payment.findOne({
      md5: req.params.md5,
      user: req.user.id,
    }).sort({ createdAt: -1 });
    if (!payment)
      return res.status(404).json({ message: "Payment not found." });

    // Already confirmed. If a previous poll marked it paid but crashed
    // before crediting, finish the job now.
    if (payment.status === "paid") {
      if (!payment.credited) {
        await creditPayment(payment);
      }
      const user = await User.findById(payment.user);
      return res.json(paidResponse(payment, user));
    }

    const now = Date.now();
    const pastExpiry = payment.expiresAt.getTime() < now;
    if (payment.expiresAt.getTime() + LATE_PAYMENT_GRACE_MS < now) {
      await Payment.updateOne(
        { _id: payment._id, status: "pending" },
        { $set: { status: "expired" } },
      );
      return res.json({ status: "expired" });
    }

    let result;
    try {
      result = await checkTransactionByMd5(payment.md5);
    } catch (error) {
      // Bakong being slow/unreachable is not a failed payment. Keep the
      // app waiting (and polling) instead of showing a scary error.
      console.error("[checkKhqrStatus] Bakong check failed:", error.message);
      return res.json({
        status: pastExpiry ? "expired" : "pending",
        checkError: error.message,
      });
    }

    if (!result.paid) {
      return res.json({ status: pastExpiry ? "expired" : "pending" });
    }

    const verification = verifyBakongTransaction(payment, result.raw);
    if (!verification.ok) {
      console.warn(
        `[checkKhqrStatus] Bakong reported a transaction for md5 ${payment.md5} ` +
          `but it is not this payment (${verification.reason}). Not crediting.`,
      );
      return res.json({ status: pastExpiry ? "expired" : "pending" });
    }

    // Atomically move pending -> paid. If two polls race, only ONE of them
    // wins this update; the other simply re-reads the finished result.
    const won = await Payment.findOneAndUpdate(
      { _id: payment._id, status: { $in: ["pending", "expired"] } },
      {
        $set: {
          status: "paid",
          paidAt: new Date(),
          bakongHash: result.raw?.data?.hash || undefined,
        },
      },
      { new: true },
    );
    payment = won || (await Payment.findById(payment._id));

    const credited = await creditPayment(payment);
    if (credited) await notifyPaymentConfirmed(payment);

    // If a parallel poll is the one crediting, give it a moment to finish
    // so this response carries the finished plan, not the old one.
    if (!credited) await new Promise((r) => setTimeout(r, 500));
    const user = credited || (await User.findById(payment.user));
    return res.json(paidResponse(payment, user));
  } catch (error) {
    console.error("[checkKhqrStatus] failed:", error);
    return res
      .status(500)
      .json({ message: error.message || "Could not check payment status." });
  }
};

// GET /api/payments/history
// Every payment this account has ever made, newest first — the "when did
// I pay, and for what" record the person can look back on.
const getMyPayments = async (req, res) => {
  try {
    const payments = await Payment.find({ user: req.user.id })
      .sort({ createdAt: -1 })
      .select(
        "purpose amount currency extraMainSlots extraOtherSlots status paidAt createdAt",
      );
    return res.json({ payments });
  } catch (error) {
    return res.status(500).json({ message: error.message || "Server error" });
  }
};

module.exports = {
  createKhqrPayment,
  checkKhqrStatus,
  getPricing,
  getMyPayments,
};
