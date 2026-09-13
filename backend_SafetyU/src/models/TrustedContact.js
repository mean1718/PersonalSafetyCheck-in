const mongoose = require("mongoose");

const trustedContactSchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    contactUser: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      index: true,
    },
    name: { type: String, required: true, trim: true },
    phone: { type: String, required: true, trim: true },
    email: { type: String, required: true, trim: true, lowercase: true },
    relationship: { type: String, required: true, trim: true },
    priority: { type: String, enum: ["primary", "secondary"], required: true },
    availability: {
      type: String,
      enum: ["available", "unavailable"],
      default: "available",
    },
    isActive: { type: Boolean, default: true },
  },
  { timestamps: true },
);

trustedContactSchema.index({ user: 1, phone: 1 }, { unique: true });
trustedContactSchema.index({ user: 1, email: 1 }, { unique: true });

module.exports = mongoose.model("TrustedContact", trustedContactSchema);
