const mongoose = require("mongoose");

const emergencySchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
    },

    checkIn: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "CheckIn",
      required: true,
    },

    status: {
      type: String,
      enum: [
        "waiting",
        "primary_alerted",
        "secondary_alerted",
        "emergency",
        "resolved",
      ],
      default: "waiting",
    },

    currentContact: {
      type: String,
      enum: ["primary", "secondary", "emergency"],
      default: "primary",
    },

    message: {
      type: String,
      default: "Emergency assistance required",
    },

    location: {
      latitude: Number,
      longitude: Number,
    },
  },
  {
    timestamps: true,
  }
);

module.exports = mongoose.model("Emergency", emergencySchema);