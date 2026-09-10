const mongoose = require("mongoose");
const Notification = require("../models/Notification");

const getMyNotifications = async (req, res) => {
  try {
    const notifications = await Notification.find({ receiver: req.user.id }).populate("sender", "name phone").sort({ createdAt: -1 });
    return res.json({ notifications });
  } catch (_) { return res.status(500).json({ message: "Server error" }); }
};

// The Trust/Friends screen sees only alerts delivered to the authenticated
// user. Sender is the session owner; receiver is never supplied by Flutter.
const getMyActiveSafetyAlerts = async (req, res) => {
  try {
    const notifications = await Notification.find({ receiver: req.user.id, type: "safety_alert" })
      .populate("sender", "name phone")
      .populate("checkIn", "status message startedAt")
      .sort({ createdAt: -1 });
    const alerts = notifications
      .filter((notification) => notification.checkIn && ["active", "emergency"].includes(notification.checkIn.status))
      .map((notification) => ({
        notificationId: notification._id,
        sessionId: notification.checkIn._id,
        ownerUserId: notification.sender?._id,
        ownerName: notification.sender?.name || "A trusted contact",
        ownerPhone: notification.sender?.phone || "",
        sessionStatus: notification.checkIn.status,
        message: notification.checkIn.message || notification.message,
        notifiedAt: notification.createdAt,
        responseStatus: notification.responseStatus || "pending",
        respondedAt: notification.respondedAt || null,
      }));
    return res.json({ alerts });
  } catch (_) { return res.status(500).json({ message: "Server error" }); }
};

const markRead = async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) return res.status(404).json({ message: "Notification not found." });
  try {
    const notification = await Notification.findOne({ _id: req.params.id, receiver: req.user.id });
    if (!notification) return res.status(404).json({ message: "Notification not found." });
    notification.isRead = true;
    await notification.save();
    return res.json({ message: "Notification marked as read." });
  } catch (_) { return res.status(500).json({ message: "Server error" }); }
};

// A trusted contact may only respond to their own received safety alert.
const respondToSafetyAlert = async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) return res.status(404).json({ message: "Notification not found." });
  const { responseStatus } = req.body;
  if (!["can_help", "cannot_help"].includes(responseStatus)) {
    return res.status(400).json({ message: "Response must be can_help or cannot_help." });
  }
  try {
    const notification = await Notification.findOne({ _id: req.params.id, receiver: req.user.id, type: "safety_alert" });
    if (!notification) return res.status(404).json({ message: "Safety alert not found." });
    notification.responseStatus = responseStatus;
    notification.respondedAt = new Date();
    notification.isRead = true;
    await notification.save();
    return res.json({ message: "Safety alert response recorded.", notification });
  } catch (_) { return res.status(500).json({ message: "Server error" }); }
};

module.exports = { getMyNotifications, getMyActiveSafetyAlerts, markRead, respondToSafetyAlert };
