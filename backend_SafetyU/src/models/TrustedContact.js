const mongoose = require("mongoose");

const trustedContactSchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
    },

    name: {
      type: String,
      required: true,
    },

    phone: {
      type: String,
      required: true,
    },

    relationship: {
      type: String,
      required: true,
    },

    priority: {
      type: String,
      enum: ["primary", "secondary"],
      required: true,
    },

    isActive: {
      type: Boolean,
      default: true,
    },
  },
  {
    timestamps: true,
  }
);

module.exports = mongoose.model(
  "TrustedContact",
  trustedContactSchema
);