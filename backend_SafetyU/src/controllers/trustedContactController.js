const mongoose = require("mongoose");
const TrustedContact = require("../models/TrustedContact");

const MAX_SECONDARY_CONTACTS = 5;
const genericTlds = new Set(["com", "org", "net", "edu", "gov", "info", "biz", "io", "co", "app", "dev", "me", "tech", "ai", "xyz"]);
const phone = (value) => value.trim().replace(/[\s().-]/g, "");
const validPhone = (value) => /^\+?[0-9]{7,15}$/.test(value) && !/^(\d)\1+$/.test(value.replace(/^\+/, ""));
const validEmail = (value) => {
  if (!/^[^\s@]+@[^\s@]+(?:\.[^\s@.]+)+$/.test(value)) return false;
  const [local, domain] = value.split("@");
  const tld = domain.split(".").at(-1);
  return !local.includes("..") && !domain.includes("..") && (tld.length === 2 || genericTlds.has(tld));
};

function values(body) {
  const name = typeof body.name === "string" ? body.name.trim() : "";
  const contactPhone = typeof body.phone === "string" ? phone(body.phone) : "";
  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const relationship = typeof body.relationship === "string" ? body.relationship.trim() : "";
  const priority = body.priority === "main" ? "primary" : body.priority;
  const availability = body.availability ?? "available";
  if (name.length < 2) return { error: "Contact name must be at least 2 characters." };
  if (!validPhone(contactPhone)) return { error: "Please enter a valid phone number." };
  if (!validEmail(email)) return { error: "Please enter a valid email address." };
  if (relationship.length < 2) return { error: "Relationship is required." };
  if (!["primary", "secondary"].includes(priority)) return { error: "Contact type must be main or secondary." };
  if (!["available", "unavailable"].includes(availability)) return { error: "Availability must be available or unavailable." };
  return { value: { name, phone: contactPhone, email, relationship, priority, availability } };
}

async function overSecondaryLimit(user, priority, ignoredId) {
  if (priority !== "secondary") return false;
  const filter = { user, priority: "secondary", isActive: true };
  if (ignoredId) filter._id = { $ne: ignoredId };
  return (await TrustedContact.countDocuments(filter)) >= MAX_SECONDARY_CONTACTS;
}

const addTrustedContact = async (req, res) => {
  try {
    const result = values(req.body);
    if (result.error) return res.status(400).json({ message: result.error });
    if (await overSecondaryLimit(req.user.id, result.value.priority)) return res.status(400).json({ message: `You can have up to ${MAX_SECONDARY_CONTACTS} secondary trusted contacts.` });
    const contact = await TrustedContact.create({ user: req.user.id, ...result.value });
    return res.status(201).json({ message: "Trusted contact added successfully.", contact });
  } catch (error) {
    if (error?.code === 11000) return res.status(400).json({ message: "A trusted contact with this phone number or email already exists." });
    return res.status(500).json({ message: "Server error" });
  }
};

const getTrustedContacts = async (req, res) => {
  try {
    const contacts = await TrustedContact.find({ user: req.user.id, isActive: true }).sort({ priority: 1, createdAt: -1 });
    return res.json({ contacts, secondaryLimit: MAX_SECONDARY_CONTACTS });
  } catch (_) { return res.status(500).json({ message: "Server error" }); }
};

const contactForUser = (id, user) => TrustedContact.findOne({ _id: id, user, isActive: true });
const validId = (id) => mongoose.isValidObjectId(id);

const getTrustedContact = async (req, res) => {
  if (!validId(req.params.id)) return res.status(404).json({ message: "Trusted contact not found." });
  try {
    const contact = await contactForUser(req.params.id, req.user.id);
    if (!contact) return res.status(404).json({ message: "Trusted contact not found." });
    return res.json({ contact });
  } catch (_) { return res.status(500).json({ message: "Server error" }); }
};

const updateTrustedContact = async (req, res) => {
  if (!validId(req.params.id)) return res.status(404).json({ message: "Trusted contact not found." });
  try {
    const result = values(req.body);
    if (result.error) return res.status(400).json({ message: result.error });
    const contact = await contactForUser(req.params.id, req.user.id);
    if (!contact) return res.status(404).json({ message: "Trusted contact not found." });
    if (await overSecondaryLimit(req.user.id, result.value.priority, contact._id)) return res.status(400).json({ message: `You can have up to ${MAX_SECONDARY_CONTACTS} secondary trusted contacts.` });
    Object.assign(contact, result.value);
    await contact.save();
    return res.json({ message: "Trusted contact updated successfully.", contact });
  } catch (error) {
    if (error?.code === 11000) return res.status(400).json({ message: "A trusted contact with this phone number or email already exists." });
    return res.status(500).json({ message: "Server error" });
  }
};

const deleteTrustedContact = async (req, res) => {
  if (!validId(req.params.id)) return res.status(404).json({ message: "Trusted contact not found." });
  try {
    const contact = await contactForUser(req.params.id, req.user.id);
    if (!contact) return res.status(404).json({ message: "Trusted contact not found." });
    contact.isActive = false;
    await contact.save();
    return res.json({ message: "Trusted contact deleted successfully." });
  } catch (_) { return res.status(500).json({ message: "Server error" }); }
};

module.exports = { addTrustedContact, getTrustedContacts, getTrustedContact, updateTrustedContact, deleteTrustedContact, MAX_SECONDARY_CONTACTS };
