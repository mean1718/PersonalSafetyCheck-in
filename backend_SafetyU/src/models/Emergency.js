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
        "in_progress",
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

    // Police station assigned to handle this emergency.
    assignedStation: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "PoliceStation",
      default: null,
    },

    // User account of the responder who accepted this emergency.
    assignedResponder: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null,
    },

    // Time when the emergency was assigned to a station.
    assignedAt: {
      type: Date,
      default: null,
    },
  },
  {
    timestamps: true,
  }
);

module.exports = mongoose.model("Emergency", emergencySchema);