const CheckIn = require("../models/CheckIn");
const TrustRequest = require("../models/TrustRequest");
const Notification = require("../models/Notification");
const mongoose = require("mongoose");

const hasAcceptedTrust = (userId, contactId) => TrustRequest.exists({
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
        }).populate("sender", "name phone email").populate("receiver", "name phone email");
        const contacts = relationships.map((relationship) => {
            const other = relationship.sender._id.toString() === req.user.id
                ? relationship.receiver
                : relationship.sender;
            return { userId: other._id, name: other.name, phone: other.phone, email: other.email };
        });
        return res.json({ contacts });
    } catch (_) { return res.status(500).json({ message: "Server error" }); }
};

// Start a safety check-in
const startCheckIn = async (req, res) => {
    try {
        const { message, latitude, longitude, contactUserId, contactUserIds } = req.body;
        const requestedIds = Array.isArray(contactUserIds)
            ? [...new Set(contactUserIds.map((id) => id?.toString()).filter(Boolean))]
            : contactUserId ? [contactUserId.toString()] : [];
        if (requestedIds.some((id) => !mongoose.isValidObjectId(id))) {
            return res.status(400).json({ message: "Selected trusted contact is invalid." });
        }
        if (requestedIds.includes(req.user.id.toString())) {
            return res.status(400).json({ message: "You cannot select yourself as a trusted contact." });
        }
        if ((await Promise.all(requestedIds.map((id) => hasAcceptedTrust(req.user.id, id)))).some((accepted) => !accepted)) {
            return res.status(403).json({ message: "Selected user is not a confirmed trusted contact." });
        }

        const checkIn = await CheckIn.create({
            user: req.user.id,
            ...(requestedIds.length > 0 ? {
                trustedContactUser: requestedIds[0],
                trustedContactUsers: requestedIds,
            } : {}),
            message: message || "",
            location: {
                latitude: latitude || null,
                longitude: longitude || null
            },
            status: "active"
        });

        // The selected accounts receive the active-session alert now. Each
        // row is keyed to its receiver, so each trusted contact can answer
        // independently even before an emergency escalation occurs.
        if (requestedIds.length > 0) {
            await Notification.insertMany(requestedIds.map((receiver) => ({
                receiver,
                sender: req.user.id,
                checkIn: checkIn._id,
                type: "safety_alert",
                title: "SafetyU Alert",
                message: `${req.authenticatedUser?.name || "A trusted contact"} started a safety session.`,
            })));
        }

        res.status(201).json({
            message: "Safety check-in started",
            checkIn
        });

    } catch (error) {
        res.status(500).json({
            message: "Server error",
            error: error.message
        });
    }
};


// Complete a safety check-in
const completeCheckIn = async (req, res) => {
    try {
        const checkIn = await CheckIn.findOne({
            _id: req.params.id,
            user: req.user.id
        });

        if (!checkIn) {
            return res.status(404).json({
                message: "Check-in not found"
            });
        }

        checkIn.status = "completed";
        checkIn.completedAt = new Date();

        await checkIn.save();

        res.status(200).json({
            message: "Safety check-in completed",
            checkIn
        });

    } catch (error) {
        res.status(500).json({
            message: "Server error",
            error: error.message
        });
    }
};


// Get user's check-ins
const getMyCheckIns = async (req, res) => {
    try {
        const checkIns = await CheckIn.find({
            user: req.user.id
        }).sort({ createdAt: -1 });

        res.status(200).json({
            checkIns
        });

    } catch (error) {
        res.status(500).json({
            message: "Server error",
            error: error.message
        });
    }
};


const getAlertStatus = async (req, res) => {
    if (!mongoose.isValidObjectId(req.params.id)) {
        return res.status(404).json({ message: "Check-in not found" });
    }
    try {
        const checkIn = await CheckIn.findOne({ _id: req.params.id, user: req.user.id });
        if (!checkIn) return res.status(404).json({ message: "Check-in not found" });
        const notifications = await Notification.find({ checkIn: checkIn._id, type: "safety_alert" })
            .populate("receiver", "name phone").sort({ createdAt: 1 });
        return res.json({
            checkInId: checkIn._id,
            ownerUserId: checkIn.user,
            notifiedContacts: notifications.filter((n) => n.receiver).map((n) => ({
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
        return res.status(500).json({ message: "Server error", error: error.message });
    }
};

module.exports = {
    getSessionTrustedContacts,
    startCheckIn,
    completeCheckIn,
    getMyCheckIns,
    getAlertStatus
};
