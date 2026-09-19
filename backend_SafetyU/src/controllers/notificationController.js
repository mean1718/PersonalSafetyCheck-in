const mongoose = require("mongoose");
const Notification = require("../models/Notification");
const CheckIn = require("../models/CheckIn");
const { sendPushToUser } = require("../services/pushService");

const getMyNotifications = async (req, res) => {
  try {
    const notifications = await Notification.find({ receiver: req.user.id })
      .populate("sender", "name phone")
      .populate("checkIn", "status")
      .sort({ createdAt: -1 });
    return res.json({ notifications });
  } catch (_) {
    return res.status(500).json({ message: "Server error" });
  }
};

// The Trust/Friends screen sees only alerts delivered to the authenticated
// user. Sender is the session owner; receiver is never supplied by Flutter.
const getMyActiveSafetyAlerts = async (req, res) => {
  try {
    const notifications = await Notification.find({
      receiver: req.user.id,
      type: "safety_alert",
    })
      .populate("sender", "name phone")
      .populate("checkIn", "status message startedAt")
      .sort({ createdAt: -1 });
    const alerts = notifications
      .filter((notification) =>
        notification.checkIn
          ? ["active", "emergency"].includes(notification.checkIn.status)
          : // No session behind this one (a "Need Help" sent from chat) —
            // it's active until the sender confirms Safe, not until a
            // CheckIn status changes.
            !notification.resolved,
      )
      .map((notification) => ({
        notificationId: notification._id,
        sessionId: notification.checkIn?._id || null,
        ownerUserId: notification.sender?._id,
        ownerName: notification.sender?.name || "A trusted contact",
        ownerPhone: notification.sender?.phone || "",
        sessionStatus: notification.checkIn?.status || null,
        message: notification.checkIn?.message || notification.message,
        notifiedAt: notification.createdAt,
        responseStatus: notification.responseStatus || "pending",
        respondedAt: notification.respondedAt || null,
        isRead: notification.isRead || false,
      }));
    return res.json({ alerts });
  } catch (_) {
    return res.status(500).json({ message: "Server error" });
  }
};

const markRead = async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id))
    return res.status(404).json({ message: "Notification not found." });
  try {
    const notification = await Notification.findOne({
      _id: req.params.id,
      receiver: req.user.id,
    });
    if (!notification)
      return res.status(404).json({ message: "Notification not found." });
    notification.isRead = true;
    await notification.save();
    return res.json({ message: "Notification marked as read." });
  } catch (_) {
    return res.status(500).json({ message: "Server error" });
  }
};

// A trusted contact may only respond to their own received safety alert.
const respondToSafetyAlert = async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id))
    return res.status(404).json({ message: "Notification not found." });
  const { responseStatus } = req.body;
  if (!["can_help", "cannot_help", "marked_safe"].includes(responseStatus)) {
    return res.status(400).json({
      message: "Response must be can_help, cannot_help, or marked_safe.",
    });
  }
  try {
    const notification = await Notification.findOne({
      _id: req.params.id,
      receiver: req.user.id,
      type: "safety_alert",
    });
    if (!notification)
      return res.status(404).json({ message: "Safety alert not found." });

    // Gate: only someone who already committed to helping can close out
    // the whole session on the person's behalf — stops a contact who
    // hasn't even responded (or said they can't help) from silently
    // canceling someone else's active emergency.
    if (
      responseStatus === "marked_safe" &&
      notification.responseStatus !== "can_help"
    ) {
      return res.status(400).json({
        message: "Confirm you can help before marking this person safe.",
      });
    }

    notification.responseStatus = responseStatus;
    notification.respondedAt = new Date();
    notification.isRead = true;
    if (responseStatus === "marked_safe") notification.resolved = true;
    await notification.save();

    if (responseStatus === "marked_safe") {
      const contactName = req.authenticatedUser?.name || "A trusted contact";
      if (notification.checkIn) {
        const checkIn = await CheckIn.findById(notification.checkIn);
        if (checkIn && checkIn.status !== "completed") {
          checkIn.status = "completed";
          checkIn.completedAt = new Date();
          await checkIn.save();
        }
        // Every contact alerted for this same session should see it as
        // resolved too, not just the one who marked it — otherwise the
        // others are left waiting on an alert that's already over.
        await Notification.updateMany(
          { checkIn: notification.checkIn, type: "safety_alert" },
          { $set: { resolved: true } },
        );
        if (checkIn) {
          const message = `${contactName} confirmed you're safe.`;
          await Notification.create({
            receiver: checkIn.user,
            sender: req.user.id,
            checkIn: checkIn._id,
            type: "checkin_completed",
            title: "SafetyU",
            message,
          });
          sendPushToUser(checkIn.user, {
            title: "SafetyU",
            body: message,
            data: {
              type: "checkin_completed",
              checkInId: checkIn._id.toString(),
            },
          });
        }
      } else {
        // A "Need Help" sent straight from chat — no CheckIn behind it.
        // Resolve every other still-open safety_alert from the same
        // sender toward this same receiver, and tell the sender directly.
        await Notification.updateMany(
          {
            receiver: req.user.id,
            sender: notification.sender,
            type: "safety_alert",
            checkIn: { $in: [null, undefined] },
            resolved: false,
          },
          { $set: { resolved: true } },
        );
        const message = `${contactName} confirmed you're safe.`;
        await Notification.create({
          receiver: notification.sender,
          sender: req.user.id,
          type: "checkin_completed",
          title: "SafetyU",
          message,
        });
        sendPushToUser(notification.sender, {
          title: "SafetyU",
          body: message,
          data: { type: "checkin_completed" },
        });
      }
    }

    return res.json({
      message: "Safety alert response recorded.",
      notification,
    });
  } catch (_) {
    return res.status(500).json({ message: "Server error" });
  }
};

// DELETE /api/notifications
// Clears every dismissible notification for this account. Payment
// confirmations are deliberately excluded — they're the person's receipt
// of what they paid and when, not a transient alert, so they stay even
// after Clear All (mirrors GET /api/payments/history, which is the
// permanent record this is meant to always be findable alongside).
const clearAllNotifications = async (req, res) => {
  try {
    await Notification.deleteMany({
      receiver: req.user.id,
      type: { $ne: "payment_confirmed" },
    });
    return res.json({ message: "Notifications cleared." });
  } catch (_) {
    return res.status(500).json({ message: "Server error" });
  }
};

module.exports = {
  getMyNotifications,
  getMyActiveSafetyAlerts,
  markRead,
  respondToSafetyAlert,
  clearAllNotifications,
};
