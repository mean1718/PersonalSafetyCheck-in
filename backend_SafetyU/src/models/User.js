const mongoose = require("mongoose");

const userSchema = new mongoose.Schema(
  {
    name: {
      type: String,
      required: true,
      trim: true,
      minlength: 2,
    },

    email: {
      type: String,
      required: true,
      unique: true,
      trim: true,
      lowercase: true,
    },

    password: {
      type: String,
      required: true,
    },

    phone: {
      type: String,
      required: true,
      unique: true,
      // Allows pre-existing accounts created before phone became required;
      // every newly registered account still has a unique phone number.
      sparse: true,
      trim: true,
    },

    role: {
      type: String,
      enum: ["user", "responder"],
      default: "user",
    },

    // ---- Push notifications ----
    // Firebase Cloud Messaging tokens for every device this account is
    // currently signed into. An array (not a single field) because the
    // same person can be logged in on more than one device at once —
    // every registered token gets the push. Registered by Flutter via
    // POST /api/users/device-token after login and on app start; pruned
    // automatically by pushService when Firebase reports a token is dead.
    fcmTokens: { type: [String], default: [] },

    // ---- Responder accounts ----
    officerId: {
      type: String,
      trim: true,
      uppercase: true,
      sparse: true,
      unique: true,
    },

    responderStatus: {
      type: String,
      enum: ["pending", "approved", "rejected"],
      default: "pending",
    },

    // ---- Emergency Assistant PIN (user accounts only) ----
    emergencyPin: {
      type: String,
      default: null,
    },

    // ---- Plan / paywall (credited by paymentController on confirmed Bakong payments) ----
    isPro: { type: Boolean, default: false },
    proExpiresAt: { type: Date },
    purchasedExtraMainSlots: { type: Number, default: 0 },
    purchasedExtraOtherSlots: { type: Number, default: 0 },
  },
  { timestamps: true },
);

module.exports = mongoose.model("User", userSchema);