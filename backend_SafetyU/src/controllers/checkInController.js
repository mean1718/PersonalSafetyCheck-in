const CheckIn = require("../models/CheckIn");
const TrustRequest = require("../models/TrustRequest");
const Notification = require("../models/Notification");
const mongoose = require("mongoose");

const hasAcceptedTrust = (userId, contactId) =>
  TrustRequest.exists({
    status: "accepted",
    $or: [
      { sender: userId, receiver: contactId },
      { sender: contactId, receiver: userId },
    ],
  });

const getSessionTrustedContacts = async (req, res) => {
  try {
    const relationships = await TrustRequest.find({
      status: "accepted",
      $or: [{ sender: req.user.id }, { receiver: req.user.id }],
    })
      .populate("sender", "name phone email")
      .populate("receiver", "name phone email");
    const contacts = relationships.map((relationship) => {
      const other =
        relationship.sender._id.toString() === req.user.id
          ? relationship.receiver
          : relationship.sender;
      return {
        userId: other._id,
        name: other.name,
        phone: other.phone,
        email: other.email,
      };
    });
    return res.json({ contacts });
  } catch (_) {
    return res.status(500).json({ message: "Server error" });
  }
};

// Start a safety check-in
const startCheckIn = async (req, res) => {
  try {
    const { message, latitude, longitude, contactUserId, contactUserIds } =
      req.body;
    const requestedIds = Array.isArray(contactUserIds)
      ? [...new Set(contactUserIds.map((id) => id?.toString()).filter(Boolean))]
      : contactUserId
        ? [contactUserId.toString()]
        : [];
    if (requestedIds.some((id) => !mongoose.isValidObjectId(id))) {
      return res
        .status(400)
        .json({ message: "Selected trusted contact is invalid." });
    }
    if (requestedIds.includes(req.user.id.toString())) {
      return res
        .status(400)
        .json({ message: "You cannot select yourself as a trusted contact." });
    }
    if (
      (
        await Promise.all(
          requestedIds.map((id) => hasAcceptedTrust(req.user.id, id)),
        )
      ).some((accepted) => !accepted)
    ) {
      return res
        .status(403)
        .json({ message: "Selected user is not a confirmed trusted contact." });
    }

    const checkIn = await CheckIn.create({
      user: req.user.id,
      ...(requestedIds.length > 0
        ? {
            trustedContactUser: requestedIds[0],
            trustedContactUsers: requestedIds,
          }
        : {}),
      message: message || "",
      location: {
        latitude: latitude || null,
        longitude: longitude || null,
      },
      status: "active",
    });

    // No alert is sent yet. Trusted contacts are only notified if this
    // person fails to check in / confirm safe by the deadline they set —
    // that happens later, via needHelpNow() when the app's escalation
    // timer runs out. Starting a session on its own should be silent.

    res.status(201).json({
      message: "Safety check-in started",
      checkIn,
    });
  } catch (error) {
    res.status(500).json({
      message: "Server error",
      error: error.message,
    });
  }
};

// Complete a safety check-in
const completeCheckIn = async (req, res) => {
  try {
    const checkIn = await CheckIn.findOne({
      _id: req.params.id,
      user: req.user.id,
    });

    if (!checkIn) {
      return res.status(404).json({
        message: "Check-in not found",
      });
    }

    checkIn.status = "completed";
    checkIn.completedAt = new Date();

    await checkIn.save();

    res.status(200).json({
      message: "Safety check-in completed",
      checkIn,
    });
  } catch (error) {
    res.status(500).json({
      message: "Server error",
      error: error.message,
    });
  }
};

// Get user's check-ins
const getMyCheckIns = async (req, res) => {
  try {
    const checkIns = await CheckIn.find({
      user: req.user.id,
    }).sort({ createdAt: -1 });

    res.status(200).json({
      checkIns,
    });
  } catch (error) {
    res.status(500).json({
      message: "Server error",
      error: error.message,
    });
  }
};

const getAlertStatus = async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) {
    return res.status(404).json({ message: "Check-in not found" });
  }
  try {
    const checkIn = await CheckIn.findOne({
      _id: req.params.id,
      user: req.user.id,
    });
    if (!checkIn)
      return res.status(404).json({ message: "Check-in not found" });
    const notifications = await Notification.find({
      checkIn: checkIn._id,
      type: "safety_alert",
    })
      .populate("receiver", "name phone")
      .sort({ createdAt: 1 });
    // A contact can end up with more than one safety_alert row for the
    // same check-in (e.g. a re-alert fired when escalation moved to the
    // next tier). Collapse those down to ONE entry per contact so the
    // panel updates in place — "Waiting..." flips to "Can Help" — instead
    // of listing the same person twice.
    const byContact = new Map();
    for (const n of notifications) {
      if (!n.receiver) continue;
      const key = n.receiver._id.toString();
      const existing = byContact.get(key);
      if (!existing) {
        byContact.set(key, n);
        continue;
      }
      // Keep the earliest "notified at" (their first alert) but let a
      // response on ANY of their alerts win over a still-pending one.
      const existingResponded = (existing.responseStatus || "pending") !== "pending";
      const thisResponded = (n.responseStatus || "pending") !== "pending";
      if (thisResponded && !existingResponded) {
        byContact.set(key, { ...existing.toObject(), ...n.toObject(), createdAt: existing.createdAt });
      }
    }

    return res.json({
      checkInId: checkIn._id,
      ownerUserId: checkIn.user,
      notifiedContacts: [...byContact.values()].map((n) => ({
        notificationId: n._id,
        userId: n.receiver._id,
        name: n.receiver.name,
        phone: n.receiver.phone,
        notifiedAt: n.createdAt,
        responseStatus: n.responseStatus || "pending",
        respondedAt: n.respondedAt || null,
      })),
    });
  } catch (error) {
    return res
      .status(500)
      .json({ message: "Server error", error: error.message });
  }
};

// ---------------------------------------------------------------
// NEW: Safety User's phone calls this repeatedly while a session
// is active, to push their live GPS position into the database.
// ---------------------------------------------------------------
const updateLocation = async (req, res) => {
  const { latitude, longitude } = req.body;

  if (typeof latitude !== "number" || typeof longitude !== "number") {
    return res
      .status(400)
      .json({ message: "latitude and longitude must be numbers." });
  }
  if (!mongoose.isValidObjectId(req.params.id)) {
    return res.status(404).json({ message: "Check-in not found" });
  }

  try {
    // "user: req.user.id" is the security lock here: this only finds a
    // check-in that BOTH matches this ID AND belongs to whoever is
    // making the request (proven by their JWT, not by anything they
    // typed). So no one can push a fake location into someone else's
    // session, even if they somehow guessed the session's ID.
    const checkIn = await CheckIn.findOne({
      _id: req.params.id,
      user: req.user.id,
    });

    if (!checkIn) {
      return res.status(404).json({ message: "Check-in not found" });
    }

    // Only an ACTIVE session should keep updating location. Once the
    // user taps Safe (status becomes "completed"), we stop accepting
    // new GPS points for it -- there's no reason to keep tracking
    // someone after their session has ended.
    if (checkIn.status !== "active") {
      return res
        .status(400)
        .json({ message: "This session is no longer active." });
    }

    checkIn.location = { latitude, longitude };
    await checkIn.save();

    return res
      .status(200)
      .json({ message: "Location updated", location: checkIn.location });
  } catch (error) {
    return res
      .status(500)
      .json({ message: "Server error", error: error.message });
  }
};

// ---------------------------------------------------------------
// NEW: A Trusted Contact's phone calls this to fetch the Safety
// User's current location for one specific session.
// ---------------------------------------------------------------
const viewSessionLocation = async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) {
    return res.status(404).json({ message: "Check-in not found" });
  }

  try {
    const checkIn = await CheckIn.findById(req.params.id);

    if (!checkIn) {
      return res.status(404).json({ message: "Check-in not found" });
    }

    // Two kinds of people are allowed to see this location:
    //   1) The Safety User themself (checking their own session), or
    //   2) A Trusted Contact who was actually selected for THIS session.
    // Anyone else -- even a fully logged-in, valid SafetyU user -- gets
    // rejected. This is the exact check that stops a random user of the
    // app from viewing a stranger's location.
    const isOwner = checkIn.user.toString() === req.user.id;
    const isAlertedContact = (checkIn.trustedContactUsers || [])
      .map((id) => id.toString())
      .includes(req.user.id);

    if (!isOwner && !isAlertedContact) {
      return res
        .status(403)
        .json({ message: "You are not authorized to view this location." });
    }

    // A Trusted Contact should only ever see a LIVE location while the
    // session is still active. Once it's completed, we hide the
    // location from contacts (the owner can still see their own).
    if (!isOwner && checkIn.status !== "active") {
      return res
        .status(400)
        .json({
          message: "This session has ended. Location is no longer shared.",
        });
    }

    return res.status(200).json({
      checkInId: checkIn._id,
      status: checkIn.status,
      location: checkIn.location,
    });
  } catch (error) {
    return res
      .status(500)
      .json({ message: "Server error", error: error.message });
  }
};

// POST /api/checkins/:id/need-help — called when "Need Help" fires, either
// the manual button or a timed-out escalation stage. The original
// session-start notification only reflects the state from when the
// session began; if a contact already answered it (or it's otherwise not
// currently "pending"), nothing would ever resurface on their Home screen
// for this more urgent moment. This creates a brand-new safety_alert
// notification for the given contacts, tied to the same check-in, so it
// naturally reappears as a fresh, unread, pending alert — instead of
// silently resetting the original one's history.
const needHelpNow = async (req, res) => {
    if (!mongoose.isValidObjectId(req.params.id)) {
        return res.status(404).json({ message: "Check-in not found" });
    }
    try {
        const checkIn = await CheckIn.findOne({ _id: req.params.id, user: req.user.id });
        if (!checkIn) return res.status(404).json({ message: "Check-in not found" });
        if (checkIn.status === "completed") {
            return res.status(400).json({ message: "This session has already ended." });
        }

        const { contactUserIds } = req.body;
        const requestedIds = Array.isArray(contactUserIds)
            ? [...new Set(contactUserIds.map((id) => id?.toString()).filter(Boolean))]
            : (checkIn.trustedContactUsers || []).map((id) => id.toString());
        if (requestedIds.some((id) => !mongoose.isValidObjectId(id))) {
            return res.status(400).json({ message: "One of the selected contacts is invalid." });
        }
        if (requestedIds.length === 0) {
            return res.status(400).json({ message: "No contacts to notify." });
        }

        const created = await Notification.insertMany(requestedIds.map((receiver) => ({
            receiver,
            sender: req.user.id,
            checkIn: checkIn._id,
            type: "safety_alert",
            title: "SafetyU Alert",
            message: `${req.authenticatedUser?.name || "A trusted contact"} needs help right now.`,
        })));

        return res.status(201).json({ message: "Contacts re-alerted.", notifications: created });
    } catch (error) {
        return res.status(500).json({ message: "Server error", error: error.message });
    }
};

module.exports = {
  getSessionTrustedContacts,
  startCheckIn,
  completeCheckIn,
  getMyCheckIns,
  getAlertStatus,
  updateLocation,
  viewSessionLocation,
  needHelpNow,
};