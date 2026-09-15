const crypto = require("crypto");
const User = require("../models/User");
const Payment = require("../models/Payment");
const { buildIndividualKHQR } = require("../utils/khqr");
const { checkTransactionByMd5 } = require("../services/bakongClient");

const PRO_MONTHLY_PRICE_USD = 2.99;
const PRICE_PER_CONTACT_USD = 0.2;

const ACCOUNT_CURRENCY = (
  process.env.BAKONG_ACCOUNT_CURRENCY || "KHR"
).toUpperCase();

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
// Body: { purpose: 'pro_subscription' }
//    or { purpose: 'pay_per_contact', extraMain?, extraOther? }
const createKhqrPayment = async (req, res) => {
  const purpose = req.body.purpose;
  const extraMain = Math.max(0, Number(req.body.extraMain) || 0);
  const extraOther = Math.max(0, Number(req.body.extraOther) || 0);
  const extraContacts = extraMain + extraOther;

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

  try {
    const existing = await Payment.findOne({
      user: req.user.id,
      purpose,
      status: "pending",
      expiresAt: { $gt: new Date() },
      ...(purpose === "pay_per_contact"
        ? { extraMainSlots: extraMain, extraOtherSlots: extraOther }
        : {}),
    });
    if (existing) {
      if (!hasKhqrAmount(existing.qrString)) {
        existing.status = "expired";
        await existing.save();
      } else {
        const qrAmount =
          ACCOUNT_CURRENCY === "USD"
            ? existing.amount
            : usdToKhr(existing.amount);
        return res.status(200).json({
          paymentId: existing._id,
          qrString: existing.qrString,
          md5: existing.md5,
          amount: existing.amount,
          currency: existing.currency,
          qrAmount,
          qrCurrency: ACCOUNT_CURRENCY,
          expiresAt: existing.expiresAt,
        });
      }
    }

    // USD account -> exact charge, no conversion at all.
    // KHR account -> converted at BAKONG_USD_TO_KHR_RATE (not live; update
    // that env var periodically to track the real exchange rate).
    const qrAmount =
      ACCOUNT_CURRENCY === "USD" ? amountUsd : usdToKhr(amountUsd);

    const billNumber = crypto.randomBytes(6).toString("hex");
    const { qrString, md5, expiresAt } = buildIndividualKHQR({
      ...accountInfo(),
      currency: ACCOUNT_CURRENCY,
      amount: qrAmount,
      billNumber,
    });

    // md5 is no longer a unique index (see Payment.js) — a same-amount
    // repeat purchase can legitimately share an md5 with an older record,
    // and that's fine; status checks always scope by { md5, user }.
    const payment = await Payment.create({
      user: req.user.id,
      purpose,
      extraContacts: purpose === "pay_per_contact" ? extraContacts : 0,
      extraMainSlots: purpose === "pay_per_contact" ? extraMain : 0,
      extraOtherSlots: purpose === "pay_per_contact" ? extraOther : 0,
      amount: amountUsd,
      currency: "USD",
      qrString,
      md5,
      expiresAt,
    });

    return res.status(201).json({
      paymentId: payment._id,
      qrString: payment.qrString,
      md5: payment.md5,
      amount: amountUsd,
      currency: "USD",
      // The amount/currency actually printed on the QR — lets the frontend
      // show "≈ 12,259 ៛" next to the USD price when a conversion happened,
      // so the person isn't surprised by what their banking app shows them.
      qrAmount,
      qrCurrency: ACCOUNT_CURRENCY,
      expiresAt: payment.expiresAt,
    });
  } catch (error) {
    console.error("[createKhqrPayment] failed:", error);
    // Don't leak raw Mongo/driver error text (e.g. "E11000 duplicate key
    // error...") to the app — log the real error above for debugging, but
    // show the person something actionable instead.
    const isDbError =
      typeof error.code !== "undefined" || error.name === "MongoServerError";
    return res.status(500).json({
      message: isDbError
        ? "Could not generate a payment QR right now. Please try again."
        : error.message || "Could not generate a payment QR.",
    });
  }
};

// GET /api/payments/khqr/:md5/status
const checkKhqrStatus = async (req, res) => {
  try {
    // md5 is no longer unique (see Payment.js) — a user can have more than
    // one payment record sharing the same md5, so always take the most
    // recently created one rather than an arbitrary/possibly-stale match.
    const payment = await Payment.findOne({
      md5: req.params.md5,
      user: req.user.id,
    }).sort({ createdAt: -1 });
    if (!payment)
      return res.status(404).json({ message: "Payment not found." });

    if (payment.status === "paid") {
      const user = await User.findById(payment.user).select(
        "isPro purchasedExtraMainSlots purchasedExtraOtherSlots",
      );
      return res.json({
        status: "paid",
        purpose: payment.purpose,
        extraMainSlots: payment.extraMainSlots,
        extraOtherSlots: payment.extraOtherSlots,
        isPro: user?.isPro ?? false,
        purchasedExtraMainSlots: user?.purchasedExtraMainSlots ?? 0,
        purchasedExtraOtherSlots: user?.purchasedExtraOtherSlots ?? 0,
      });
    }

    if (payment.expiresAt < new Date()) {
      if (payment.status !== "expired") {
        payment.status = "expired";
        await payment.save();
      }
      return res.json({ status: "expired" });
    }

    const result = await checkTransactionByMd5(payment.md5);
    if (result.paid) {
      payment.status = "paid";
      payment.paidAt = new Date();
      await payment.save();

      // Credit the account only now that Bakong has actually confirmed
      // the transfer — never before this point.
      let user;
      if (payment.purpose === "pro_subscription") {
        user = await User.findByIdAndUpdate(
          payment.user,
          { isPro: true },
          { new: true },
        );
      } else {
        user = await User.findByIdAndUpdate(
          payment.user,
          {
            $inc: {
              purchasedExtraMainSlots: payment.extraMainSlots,
              purchasedExtraOtherSlots: payment.extraOtherSlots,
            },
          },
          { new: true },
        );
      }

      return res.json({
        status: "paid",
        purpose: payment.purpose,
        extraMainSlots: payment.extraMainSlots,
        extraOtherSlots: payment.extraOtherSlots,
        isPro: user?.isPro ?? false,
        purchasedExtraMainSlots: user?.purchasedExtraMainSlots ?? 0,
        purchasedExtraOtherSlots: user?.purchasedExtraOtherSlots ?? 0,
      });
    }

    return res.json({ status: "pending" });
  } catch (error) {
    console.error("[checkKhqrStatus] failed:", error);
    return res
      .status(500)
      .json({ message: error.message || "Could not check payment status." });
  }
};

module.exports = { createKhqrPayment, checkKhqrStatus, getPricing };
