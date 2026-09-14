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
      enum: ["user", "emergency"],
      default: "user",
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
