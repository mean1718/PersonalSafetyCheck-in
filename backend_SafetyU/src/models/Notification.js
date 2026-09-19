const mongoose = require("mongoose");

const notificationSchema = new mongoose.Schema(
  {
    receiver: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },

    sender: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
    },

    checkIn: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "CheckIn",
      required: false,
    },

    // Emergency request connected to this notification.
    // Used by responder notifications.
    emergency: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Emergency",
      required: false,
    },

    type: {
      type: String,
      enum: [
        "safety_alert",
        "checkin_completed",
        "emergency_alert",
        "payment_confirmed",
      ],
      required: true,
    },

    title: {
      type: String,
      required: true,
    },

    message: {
      type: String,
      required: true,
    },

    // Current location of the person who needs help.
    location: {
      latitude: {
        type: Number,
      },
      longitude: {
        type: Number,
      },
    },

    responseStatus: {
      type: String,
      enum: ["pending", "can_help", "cannot_help", "marked_safe"],
      default: "pending",
    },

    respondedAt: {
      type: Date,
    },

    isRead: {
      type: Boolean,
      default: false,
    },

    resolved: {
      type: Boolean,
      default: false,
    },
  },
  {
    timestamps: true,
  },
);

module.exports = mongoose.model("Notification", notificationSchema);
