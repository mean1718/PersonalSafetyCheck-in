const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");

const User = require("../models/User");
const ResponderOfficer = require("../models/ResponderOfficer");

// This deliberately accepts normal local/international phone formatting while
// rejecting letters, implausibly short/long values, repeated digits, and easy
// placeholder sequences such as 1111111111 or 1234567890.
const normalizePhone = (value) => value.trim().replace(/[\s().-]/g, "");
const isValidPhone = (value) => {
  if (!/^\+?[0-9]{7,15}$/.test(value)) return false;

  const digits = value.replace(/^\+/, "");
  if (/^(\d)\1+$/.test(digits)) return false;

  let ascending = true;
  let descending = true;
  for (let index = 1; index < digits.length; index += 1) {
    const previous = Number(digits[index - 1]);
    const current = Number(digits[index]);
    ascending &&= current === (previous + 1) % 10;
    descending &&= current === (previous + 9) % 10;
  }
  return !ascending && !descending;
};

const isValidEmail = (value) => {
  if (!/^[^\s@]+@[^\s@]+(?:\.[^\s@.]+)+$/.test(value)) return false;

  const [localPart, domain] = value.split("@");
  if (localPart.includes("..") || domain.includes("..")) return false;

  // Two-letter country domains (for example .kh) are valid. For generic
  // domains we allow common public suffixes, which rejects obvious made-up
  // addresses such as p@mmmk.kjjd without rejecting normal addresses.
  const tld = domain.split(".").at(-1);
  const commonGenericTlds = new Set([
    "com", "org", "net", "edu", "gov", "mil", "info", "biz", "io", "co",
    "app", "dev", "me", "pro", "tech", "online", "site", "store", "cloud",
    "ai", "xyz", "name", "mobi", "museum", "travel",
  ]);
  return tld.length === 2 || commonGenericTlds.has(tld);
};

// New records are always lowercased, but this keeps login and duplicate
// checks compatible with accounts created before that rule was introduced.
const escapeRegex = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const findUserByEmail = (email) =>
  User.findOne({ email: new RegExp(`^${escapeRegex(email)}$`, "i") });

// =========================================================
// PUBLIC USER DATA
// =========================================================
//
// Never return password or emergencyPin to Flutter.
// =========================================================

const publicUser = (user) => ({
  id: user._id,
  name: user.name,
  email: user.email,
  phone: user.phone,
  role: user.role,
  officerId: user.officerId || null,
  responderStatus: user.responderStatus || null,
  createdAt: user.createdAt,

  // Do NOT return the actual PIN.
  // Only tell Flutter whether a PIN exists.
  hasEmergencyPin: Boolean(user.emergencyPin),

  isPro: user.isPro,
  proExpiresAt: user.proExpiresAt,
  purchasedExtraMainSlots: user.purchasedExtraMainSlots,
  purchasedExtraOtherSlots: user.purchasedExtraOtherSlots,
});

// =========================================================
// REGISTER USER / RESPONDER
// =========================================================

const registerUser = async (req, res) => {
  try {
    const { role, officerId, emergencyPin } = req.body;

    const name =
      typeof req.body.name === "string" ? req.body.name.trim() : "";
    const email =
      typeof req.body.email === "string"
        ? req.body.email.trim().toLowerCase()
        : "";
    const password =
      typeof req.body.password === "string" ? req.body.password : "";
    const phone =
      typeof req.body.phone === "string" ? normalizePhone(req.body.phone) : "";

    const requestedRole = role === "responder" ? "responder" : "user";

    // -----------------------------------------------------
    // Basic validation
    // -----------------------------------------------------

    if (name.length < 2) {
      return res
        .status(400)
        .json({ message: "Name must be at least 2 characters." });
    }
    if (!isValidEmail(email)) {
      return res
        .status(400)
        .json({ message: "Please enter a valid email address." });
    }
    if (password.length < 8) {
      return res
        .status(400)
        .json({ message: "Password must be at least 8 characters." });
    }
    if (!isValidPhone(phone)) {
      return res
        .status(400)
        .json({ message: "Please enter a valid phone number." });
    }

    // -----------------------------------------------------
    // Check existing email (case-insensitive)
    // -----------------------------------------------------

    const existingUser = await findUserByEmail(email);
    if (existingUser) {
      return res
        .status(409)
        .json({ message: "An account with this email already exists." });
    }

    // -----------------------------------------------------
    // Check existing phone
    // -----------------------------------------------------

    const existingPhone = await User.findOne({ phone });
    if (existingPhone) {
      return res
        .status(409)
        .json({ message: "An account with this phone number already exists." });
    }

    // =====================================================
    // NORMAL USER EMERGENCY PIN
    // =====================================================

    let normalizedEmergencyPin = null;

    if (requestedRole === "user") {
      normalizedEmergencyPin =
        typeof emergencyPin === "string" ? emergencyPin.trim() : "";

      if (!/^\d{4}$/.test(normalizedEmergencyPin)) {
        return res
          .status(400)
          .json({ message: "Emergency PIN must be exactly 4 digits." });
      }
    }

    // =====================================================
    // RESPONDER OFFICER ID
    // =====================================================

    let normalizedOfficerId = null;
    let responderOfficer = null;

    if (requestedRole === "responder") {
      normalizedOfficerId =
        typeof officerId === "string" ? officerId.trim().toUpperCase() : "";

      if (!normalizedOfficerId) {
        return res.status(400).json({
          message: "Officer ID is required for responder accounts.",
        });
      }

      responderOfficer = await ResponderOfficer.findOne({
        officerId: normalizedOfficerId,
      });

      if (!responderOfficer) {
        return res.status(404).json({
          message: "Officer ID was not found. Please use an assigned Officer ID.",
        });
      }

      if (!responderOfficer.isActive) {
        return res.status(400).json({ message: "This Officer ID is inactive." });
      }

      if (responderOfficer.isAssigned) {
        return res.status(409).json({
          message: "This Officer ID is already assigned to another account.",
        });
      }
    }

    // =====================================================
    // HASH PASSWORD / PIN
    // =====================================================

    const hashedPassword = await bcrypt.hash(password, 10);

    const hashedEmergencyPin =
      requestedRole === "user"
        ? await bcrypt.hash(normalizedEmergencyPin, 10)
        : null;

    // =====================================================
    // CREATE USER
    // =====================================================

    const user = await User.create({
      name,
      email,
      password: hashedPassword,
      phone,
      role: requestedRole,
      officerId: requestedRole === "responder" ? normalizedOfficerId : null,
      responderStatus: requestedRole === "responder" ? "pending" : null,
      emergencyPin: requestedRole === "user" ? hashedEmergencyPin : null,
    });

    // =====================================================
    // LINK RESPONDER OFFICER
    // =====================================================

    if (requestedRole === "responder" && responderOfficer) {
      responderOfficer.user = user._id;
      responderOfficer.isAssigned = true;
      await responderOfficer.save();
    }

    return res.status(201).json({
      message: "Account created successfully.",
      user: publicUser(user),
    });
  } catch (error) {
    console.error("Register user error:", error);

    if (error?.code === 11000) {
      const field = Object.keys(error.keyPattern || {})[0];
      return res.status(409).json({
        message:
          field === "phone"
            ? "This phone number is already registered."
            : "An account with these details already exists.",
      });
    }

    return res.status(500).json({ message: "Server error" });
  }
};

// =========================================================
// LOGIN
// =========================================================

const loginUser = async (req, res) => {
  try {
    const email =
      typeof req.body.email === "string"
        ? req.body.email.trim().toLowerCase()
        : "";
    const password =
      typeof req.body.password === "string" ? req.body.password : "";

    if (!email || !password) {
      return res
        .status(400)
        .json({ message: "Email and password are required." });
    }

    // Use the same generic message for invalid credentials to avoid
    // revealing whether an email address has an account.
    const user = await findUserByEmail(email);

    if (!user) {
      return res.status(401).json({ message: "Invalid email or password." });
    }

    const passwordMatches = await bcrypt.compare(password, user.password);

    if (!passwordMatches) {
      return res.status(401).json({ message: "Invalid email or password." });
    }

    if (!process.env.JWT_SECRET) {
      console.error("JWT_SECRET is not configured.");
      return res
        .status(500)
        .json({ message: "Server authentication is not configured." });
    }

    const token = jwt.sign(
      { id: user._id.toString(), role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: "7d" },
    );

    return res.status(200).json({
      message: "Login successful.",
      token,
      user: publicUser(user),
    });
  } catch (error) {
    console.error("Login user error:", error);
    return res.status(500).json({ message: "Server error" });
  }
};

// =========================================================
// DEVICE TOKEN REGISTRATION (push notifications)
// =========================================================
//
// POST /api/users/device-token  { token }
// Called by Flutter right after login and again whenever Firebase hands
// the app a fresh token (they rotate). $addToSet so registering the same
// token twice (app restart, token unchanged) is a no-op instead of piling
// up duplicates.
// =========================================================

const registerDeviceToken = async (req, res) => {
  const token = typeof req.body.token === "string" ? req.body.token.trim() : "";
  if (!token) {
    return res.status(400).json({ message: "A device token is required." });
  }
  try {
    await User.updateOne(
      { _id: req.user.id },
      { $addToSet: { fcmTokens: token } },
    );
    return res.json({ message: "Device registered for push notifications." });
  } catch (_) {
    return res.status(500).json({ message: "Server error" });
  }
};

// POST /api/users/device-token/remove  { token }
// Called on logout so a shared/borrowed device stops getting this
// account's pushes once they've signed out of it.
const removeDeviceToken = async (req, res) => {
  const token = typeof req.body.token === "string" ? req.body.token.trim() : "";
  if (!token) {
    return res.status(400).json({ message: "A device token is required." });
  }
  try {
    await User.updateOne({ _id: req.user.id }, { $pull: { fcmTokens: token } });
    return res.json({ message: "Device unregistered." });
  } catch (_) {
    return res.status(500).json({ message: "Server error" });
  }
};

// =========================================================
// VERIFY EMERGENCY PIN
// =========================================================
//
// Used by Emergency Assistant.
//
// Flutter sends:
// {
//   "pin": "1234"
// }
//
// Backend compares the entered PIN with the bcrypt hash.
// The actual PIN is never returned.
// =========================================================

const verifyEmergencyPin = async (req, res) => {
  try {
    const userId = req.user.id;

    const pin =
      typeof req.body.pin === "string" ? req.body.pin.trim() : "";

    if (!/^\d{4}$/.test(pin)) {
      return res
        .status(400)
        .json({ message: "Emergency PIN must be exactly 4 digits." });
    }

    const user = await User.findById(userId);

    if (!user) {
      return res.status(404).json({ message: "User account not found." });
    }

    if (user.role !== "user") {
      return res.status(403).json({
        message: "Emergency PIN is only available for user accounts.",
      });
    }

    if (!user.emergencyPin) {
      return res
        .status(400)
        .json({ message: "Emergency PIN has not been created." });
    }

    const isMatch = await bcrypt.compare(pin, user.emergencyPin);

    if (!isMatch) {
      return res.status(400).json({ message: "Incorrect Emergency PIN" });
    }

    return res.status(200).json({
      message: "Emergency PIN verified.",
      verified: true,
    });
  } catch (error) {
    console.error("Verify Emergency PIN error:", error);
    return res.status(500).json({ message: "Server error" });
  }
};

// =========================================================
// CHANGE EMERGENCY PIN
// =========================================================
//
// Flutter sends:
//
// {
//   "currentPin": "1234",
//   "newPin": "5678",
//   "confirmPin": "5678"
// }
//
// The new PIN is stored as a bcrypt hash.
// =========================================================

const changeEmergencyPin = async (req, res) => {
  try {
    const userId = req.user.id;

    const currentPin =
      typeof req.body.currentPin === "string"
        ? req.body.currentPin.trim()
        : "";

    const newPin =
      typeof req.body.newPin === "string" ? req.body.newPin.trim() : "";

    const confirmPin =
      typeof req.body.confirmPin === "string"
        ? req.body.confirmPin.trim()
        : "";

    if (!/^\d{4}$/.test(currentPin)) {
      return res.status(400).json({
        message: "Current Emergency PIN must be exactly 4 digits.",
      });
    }

    if (!/^\d{4}$/.test(newPin)) {
      return res
        .status(400)
        .json({ message: "Emergency PIN must be exactly 4 digits." });
    }

    if (!/^\d{4}$/.test(confirmPin)) {
      return res.status(400).json({
        message: "Confirm Emergency PIN must be exactly 4 digits.",
      });
    }

    if (newPin !== confirmPin) {
      return res
        .status(400)
        .json({ message: "New Emergency PINs do not match." });
    }

    if (currentPin === newPin) {
      return res.status(400).json({
        message: "New Emergency PIN must be different from the current PIN.",
      });
    }

    const user = await User.findById(userId);

    if (!user) {
      return res.status(404).json({ message: "User account not found." });
    }

    if (user.role !== "user") {
      return res.status(403).json({
        message: "Emergency PIN is only available for user accounts.",
      });
    }

    if (!user.emergencyPin) {
      return res
        .status(400)
        .json({ message: "Emergency PIN has not been created." });
    }

    const currentPinMatches = await bcrypt.compare(
      currentPin,
      user.emergencyPin,
    );

    if (!currentPinMatches) {
      return res
        .status(400)
        .json({ message: "Incorrect current Emergency PIN." });
    }

    const hashedNewPin = await bcrypt.hash(newPin, 10);

    user.emergencyPin = hashedNewPin;
    await user.save();

    return res.status(200).json({
      message: "Emergency PIN updated successfully.",
    });
  } catch (error) {
    console.error("Change Emergency PIN error:", error);
    return res.status(500).json({ message: "Server error" });
  }
};
// =========================================================
// CREATE EMERGENCY PIN FOR EXISTING USERS
// =========================================================
//
// This is ONLY for existing/old user accounts that were created
// before Emergency PIN was added.
//
// The user does NOT need to enter a current PIN because they
// currently do not have one.
//
// Flutter sends:
//
// {
//   "newPin": "1234",
//   "confirmPin": "1234"
// }
//
// The PIN is stored as a bcrypt hash.
// =========================================================

const createEmergencyPin = async (req, res) => {
  try {
    const userId = req.user.id;

    const newPin =
      typeof req.body.newPin === "string"
        ? req.body.newPin.trim()
        : "";

    const confirmPin =
      typeof req.body.confirmPin === "string"
        ? req.body.confirmPin.trim()
        : "";

    // ---------------------------------------------------------
    // Validate PIN
    // ---------------------------------------------------------

    if (!/^\d{4}$/.test(newPin)) {
      return res.status(400).json({
        message: "Emergency PIN must be exactly 4 digits.",
      });
    }

    if (!/^\d{4}$/.test(confirmPin)) {
      return res.status(400).json({
        message: "Confirm Emergency PIN must be exactly 4 digits.",
      });
    }

    if (newPin !== confirmPin) {
      return res.status(400).json({
        message: "Emergency PINs do not match.",
      });
    }

    // ---------------------------------------------------------
    // Find signed-in user
    // ---------------------------------------------------------

    const user = await User.findById(userId);

    if (!user) {
      return res.status(404).json({
        message: "User account not found.",
      });
    }

    if (user.role !== "user") {
      return res.status(403).json({
        message: "Emergency PIN is only available for user accounts.",
      });
    }

    // ---------------------------------------------------------
    // IMPORTANT:
    // This endpoint is only for users who DON'T have a PIN.
    // ---------------------------------------------------------

    if (user.emergencyPin) {
      return res.status(400).json({
        message: "Emergency PIN already exists. Use Settings to change it.",
      });
    }

    // ---------------------------------------------------------
    // Hash and save PIN
    // ---------------------------------------------------------

    const hashedPin = await bcrypt.hash(newPin, 10);

    user.emergencyPin = hashedPin;

    await user.save();

    return res.status(200).json({
      message: "Emergency PIN created successfully.",
      hasEmergencyPin: true,
    });
  } catch (error) {
    console.error("Create Emergency PIN error:", error);

    return res.status(500).json({
      message: "Server error",
    });
  }
};

// =========================================================
// EXPORTS
// =========================================================

module.exports = {
  registerUser,
  loginUser,
  registerDeviceToken,
  removeDeviceToken,
  verifyEmergencyPin,
  changeEmergencyPin,
  createEmergencyPin,
};