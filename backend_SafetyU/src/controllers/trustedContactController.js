const mongoose = require("mongoose");
const TrustedContact = require("../models/TrustedContact");
const { activeExtraSlots } = require("../utils/extraSlots");

// Free-plan caps — mirrors Frontend_SafetyU's AppSession.freeMainContactLimit
// / freeOtherContactLimit. Lifted by a confirmed Bakong payment: either
// isPro (unlimited) or purchasedExtraMainSlots/purchasedExtraOtherSlots,
// which only count while still within their 24h window (see extraSlots.js).
const FREE_MAIN_CONTACT_LIMIT = 2;
const FREE_OTHER_CONTACT_LIMIT = 1;
const UNLIMITED = 1 << 30;

function limitsFor(user) {
  const isPro =
    !!user?.isPro &&
    (!user.proExpiresAt || new Date(user.proExpiresAt) > new Date());
  if (isPro) return { main: UNLIMITED, other: UNLIMITED };
  const active = activeExtraSlots(user);
  return {
    main: FREE_MAIN_CONTACT_LIMIT + active.main,
    other: FREE_OTHER_CONTACT_LIMIT + active.other,
  };
}
const genericTlds = new Set([
  "com",
  "org",
  "net",
  "edu",
  "gov",
  "info",
  "biz",
  "io",
  "co",
  "app",
  "dev",
  "me",
  "tech",
  "ai",
  "xyz",
]);
const phone = (value) => value.trim().replace(/[\s().-]/g, "");
const validPhone = (value) =>
  /^\+?[0-9]{7,15}$/.test(value) && !/^(\d)\1+$/.test(value.replace(/^\+/, ""));
const validEmail = (value) => {
  if (!/^[^\s@]+@[^\s@]+(?:\.[^\s@.]+)+$/.test(value)) return false;
  const [local, domain] = value.split("@");
  const tld = domain.split(".").at(-1);
  return (
    !local.includes("..") &&
    !domain.includes("..") &&
    (tld.length === 2 || genericTlds.has(tld))
  );
};

function values(body) {
  const name = typeof body.name === "string" ? body.name.trim() : "";
  const contactPhone = typeof body.phone === "string" ? phone(body.phone) : "";
  const email =
    typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const relationship =
    typeof body.relationship === "string" ? body.relationship.trim() : "";
  const priority = body.priority === "main" ? "primary" : body.priority;
  const availability = body.availability ?? "available";
  if (name.length < 2)
    return { error: "Contact name must be at least 2 characters." };
  if (!validPhone(contactPhone))
    return { error: "Please enter a valid phone number." };
  if (!validEmail(email))
    return { error: "Please enter a valid email address." };
  if (relationship.length < 2) return { error: "Relationship is required." };
  if (!["primary", "secondary"].includes(priority))
    return { error: "Contact type must be main or secondary." };
  if (!["available", "unavailable"].includes(availability))
    return { error: "Availability must be available or unavailable." };
  return {
    value: {
      name,
      phone: contactPhone,
      email,
      relationship,
      priority,
      availability,
    },
  };
}

async function overLimit(user, priority, limits, ignoredId) {
  const limit = priority === "primary" ? limits.main : limits.other;
  const filter = { user, priority, isActive: true };
  if (ignoredId) filter._id = { $ne: ignoredId };
  return (await TrustedContact.countDocuments(filter)) >= limit;
}

const addTrustedContact = async (req, res) => {
  try {
    const result = values(req.body);
    if (result.error) return res.status(400).json({ message: result.error });
    const limits = limitsFor(req.authenticatedUser);
    if (await overLimit(req.user.id, result.value.priority, limits)) {
      const kind = result.value.priority === "primary" ? "main" : "other";
      const limit =
        result.value.priority === "primary" ? limits.main : limits.other;
      return res.status(400).json({
        message: `You can have up to ${limit} ${kind} trusted contacts on your current plan.`,
      });
    }
    const contact = await TrustedContact.create({
      user: req.user.id,
      ...result.value,
    });
    return res
      .status(201)
      .json({ message: "Trusted contact added successfully.", contact });
  } catch (error) {
    if (error?.code === 11000)
      return res.status(400).json({
        message:
          "A trusted contact with this phone number or email already exists.",
      });
    return res.status(500).json({ message: "Server error" });
  }
};

const getTrustedContacts = async (req, res) => {
  try {
    const contacts = await TrustedContact.find({
      user: req.user.id,
      isActive: true,
    }).sort({ priority: 1, createdAt: -1 });
    const limits = limitsFor(req.authenticatedUser);
    return res.json({
      contacts,
      mainLimit: limits.main,
      secondaryLimit: limits.other,
    });
  } catch (_) {
    return res.status(500).json({ message: "Server error" });
  }
};

const contactForUser = (id, user) =>
  TrustedContact.findOne({ _id: id, user, isActive: true });
const validId = (id) => mongoose.isValidObjectId(id);

const getTrustedContact = async (req, res) => {
  if (!validId(req.params.id))
    return res.status(404).json({ message: "Trusted contact not found." });
  try {
    const contact = await contactForUser(req.params.id, req.user.id);
    if (!contact)
      return res.status(404).json({ message: "Trusted contact not found." });
    return res.json({ contact });
  } catch (_) {
    return res.status(500).json({ message: "Server error" });
  }
};

const updateTrustedContact = async (req, res) => {
  if (!validId(req.params.id))
    return res.status(404).json({ message: "Trusted contact not found." });
  try {
    const result = values(req.body);
    if (result.error) return res.status(400).json({ message: result.error });
    const contact = await contactForUser(req.params.id, req.user.id);
    if (!contact)
      return res.status(404).json({ message: "Trusted contact not found." });
    const limits = limitsFor(req.authenticatedUser);
    if (
      contact.priority !== result.value.priority &&
      (await overLimit(req.user.id, result.value.priority, limits, contact._id))
    ) {
      const kind = result.value.priority === "primary" ? "main" : "other";
      const limit =
        result.value.priority === "primary" ? limits.main : limits.other;
      return res.status(400).json({
        message: `You can have up to ${limit} ${kind} trusted contacts on your current plan.`,
      });
    }
    Object.assign(contact, result.value);
    await contact.save();
    return res.json({
      message: "Trusted contact updated successfully.",
      contact,
    });
  } catch (error) {
    if (error?.code === 11000)
      return res.status(400).json({
        message:
          "A trusted contact with this phone number or email already exists.",
      });
    return res.status(500).json({ message: "Server error" });
  }
};

const deleteTrustedContact = async (req, res) => {
  if (!validId(req.params.id))
    return res.status(404).json({ message: "Trusted contact not found." });
  try {
    const contact = await contactForUser(req.params.id, req.user.id);
    if (!contact)
      return res.status(404).json({ message: "Trusted contact not found." });
    contact.isActive = false;
    await contact.save();
    return res.json({ message: "Trusted contact deleted successfully." });
  } catch (_) {
    return res.status(500).json({ message: "Server error" });
  }
};

module.exports = {
  addTrustedContact,
  getTrustedContacts,
  getTrustedContact,
  updateTrustedContact,
  deleteTrustedContact,
  FREE_MAIN_CONTACT_LIMIT,
  FREE_OTHER_CONTACT_LIMIT,
  limitsFor,
};
