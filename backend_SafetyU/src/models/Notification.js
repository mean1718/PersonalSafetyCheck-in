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

    // Optional on purpose: a "Need Help" sent straight from chat isn't part
    // of a timed CheckIn session, so there's no session to point at.
    checkIn: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "CheckIn",
      required: false,
    },

    // Emergency record connected to responder notifications.
    // Optional so existing safety-alert notifications
    // continue to work normally.
    emergency: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Emergency",
      default: null,
      index: true,
    },

    type: {
      type: String,
      enum: [
        "safety_alert",
        "checkin_completed",
        "emergency_alert",
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

    // Emergency location.
    // Used by the responder dashboard to create
    // the real emergency case on its map.
    location: {
      latitude: Number,
      longitude: Number,
    },

    // A safety-alert notification is the authoritative per-recipient record
    // for an alert. It belongs to the notified user, never the session owner.
    responseStatus: {
      type: String,
      enum: [
        "pending",
        "can_help",
        "cannot_help",
      ],
      default: "pending",
    },

    respondedAt: {
      type: Date,
    },

    isRead: {
      type: Boolean,
      default: false,
    },

    // For checkIn-less alerts (chat's "Need Help"), this is what "I'm Safe"
    // flips to true — there's no session status to check instead.
    resolved: {
      type: Boolean,
      default: false,
    },
  },
  {
    timestamps: true,
  }
);

module.exports = mongoose.model("Notification", notificationSchema);