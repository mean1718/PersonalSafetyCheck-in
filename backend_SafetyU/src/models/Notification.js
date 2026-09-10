const mongoose = require("mongoose");

const notificationSchema = new mongoose.Schema({
  receiver: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true, index: true },
  sender: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
  checkIn: { type: mongoose.Schema.Types.ObjectId, ref: "CheckIn", required: true },
  type: { type: String, enum: ["safety_alert", "checkin_completed"], required: true },
  title: { type: String, required: true },
  message: { type: String, required: true },
  // A safety-alert notification is the authoritative per-recipient record
  // for an alert. It belongs to the notified user, never the session owner.
  responseStatus: {
    type: String,
    enum: ["pending", "can_help", "cannot_help"],
    default: "pending",
  },
  respondedAt: { type: Date },
  isRead: { type: Boolean, default: false },
}, { timestamps: true });

module.exports = mongoose.model("Notification", notificationSchema);
