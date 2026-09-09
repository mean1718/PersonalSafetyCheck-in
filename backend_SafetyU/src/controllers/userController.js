const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const User = require("../models/User");

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
        "com", "org", "net", "edu", "gov", "mil", "info", "biz", "io",
        "co", "app", "dev", "me", "pro", "tech", "online", "site", "store",
        "cloud", "ai", "xyz", "name", "mobi", "museum", "travel",
    ]);
    return tld.length === 2 || commonGenericTlds.has(tld);
};

const publicUser = (user) => ({
    id: user._id,
    name: user.name,
    email: user.email,
    phone: user.phone,
    role: user.role,
    createdAt: user.createdAt,
});

const validationError = (message) => ({ message });

// New records are always lowercased, but this keeps login and duplicate
// checks compatible with accounts created before that rule was introduced.
const escapeRegex = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const findUserByEmail = (email) =>
    User.findOne({ email: new RegExp(`^${escapeRegex(email)}$`, "i") });

const registerUser = async (req, res) => {
    try {
        const name = typeof req.body.name === "string" ? req.body.name.trim() : "";
        const email = typeof req.body.email === "string"
            ? req.body.email.trim().toLowerCase()
            : "";
        const password = typeof req.body.password === "string" ? req.body.password : "";
        const phone = typeof req.body.phone === "string" ? normalizePhone(req.body.phone) : "";

        if (name.length < 2) {
            return res.status(400).json(validationError("Name must be at least 2 characters."));
        }
        if (!isValidEmail(email)) {
            return res.status(400).json(validationError("Please enter a valid email address."));
        }
        if (password.length < 8) {
            return res.status(400).json(validationError("Password must be at least 8 characters."));
        }
        if (!isValidPhone(phone)) {
            return res.status(400).json(validationError("Please enter a valid phone number."));
        }

        const existingUser = await findUserByEmail(email);

        if (existingUser) {
            return res.status(400).json({
                message: "This email is already registered."
            });
        }

        const existingPhone = await User.findOne({ phone });
        if (existingPhone) {
            return res.status(400).json({
                message: "This phone number is already registered."
            });
        }

        const hashedPassword = await bcrypt.hash(password, 10);

        const user = await User.create({
            name,
            email,
            password: hashedPassword,
            phone
        });

        res.status(201).json({
            message: "User registered successfully",
            user: publicUser(user)
        });

    } catch (error) {
        if (error?.code === 11000) {
            const field = Object.keys(error.keyPattern || {})[0];
            return res.status(400).json({
                message: field === "phone"
                    ? "This phone number is already registered."
                    : "This email is already registered."
            });
        }
        res.status(500).json({
            message: "Server error"
        });
    }
};
// Login user
const loginUser = async (req, res) => {
    try {
        const email = typeof req.body.email === "string"
            ? req.body.email.trim().toLowerCase()
            : "";
        const password = typeof req.body.password === "string" ? req.body.password : "";

        // Use the same generic message for invalid credentials to avoid
        // revealing whether an email address has an account.
        if (!isValidEmail(email) || password.length === 0) {
            return res.status(400).json({ message: "Invalid email or password." });
        }

        // Find user by email
        const user = await findUserByEmail(email);

        if (!user) {
            return res.status(400).json({
                message: "Invalid email or password."
            });
        }

        // Compare password
        const isMatch = await bcrypt.compare(password, user.password);

        if (!isMatch) {
            return res.status(400).json({
                message: "Invalid email or password."
            });
        }

        const token = jwt.sign(
    { id: user._id, role: user.role },
    process.env.JWT_SECRET,
    { expiresIn: "1d" }
);

res.status(200).json({
    message: "Login successful",
    token,
    user: publicUser(user)
});

    } catch (error) {
        res.status(500).json({
            message: "Server error"
        });
    }
};
module.exports = {
    registerUser,
    loginUser
};
