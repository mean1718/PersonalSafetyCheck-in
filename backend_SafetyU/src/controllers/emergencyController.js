const Emergency = require("../models/Emergency");
const CheckIn = require("../models/CheckIn");
const TrustedContact = require("../models/TrustedContact");
const Notification = require("../models/Notification");
const User = require("../models/User");

// Start Emergency
const startEmergency = async (req, res) => {
  try {
    const { checkInId, message, latitude, longitude } = req.body;

    // Check check-in
    const checkIn = await CheckIn.findOne({
      _id: checkInId,
      user: req.user.id,
    });

    if (!checkIn) {
      return res.status(404).json({
        message: "Check-in not found",
      });
    }

    // A session-selected account takes priority. The legacy primary contact
    // is only a fallback for older sessions without trustedContactUser.
    const selectedIds = checkIn.trustedContactUsers?.length
      ? checkIn.trustedContactUsers
      : checkIn.trustedContactUser ? [checkIn.trustedContactUser] : [];
    const selectedUsers = selectedIds.length
      ? await User.find({ _id: { $in: selectedIds } }).select("name phone")
      : [];
    const primaryContact = selectedUsers.length ? null : await TrustedContact.findOne({
      user: req.user.id, priority: "primary", isActive: true,
    });
    if (!selectedUsers.length && !primaryContact) {
      return res.status(404).json({
        message: "Primary trusted contact not found",
      });
    }

    // Create emergency
    const emergency = await Emergency.create({
      user: req.user.id,
      checkIn: checkInId,
      status: "primary_alerted",
      currentContact: "primary",
      message: message || "Emergency assistance required",
      location: {
        latitude,
        longitude,
      },
    });

    if (selectedUsers.length) {
      const existingAlert = await Notification.exists({ checkIn: checkIn._id, type: "safety_alert" });
      if (!existingAlert) {
        const sender = await User.findById(req.user.id).select("name");
        await Notification.insertMany(selectedUsers.map((selectedUser) => ({
          receiver: selectedUser._id,
          sender: req.user.id,
          checkIn: checkIn._id,
          type: "safety_alert",
          title: "SafetyU Alert",
          message: `${sender?.name || "A trusted contact"} may need your attention.`,
        })));
      }
    }

    res.status(201).json({
      message: "Emergency started",
      emergency,
      alertedContact: {
        name: selectedUsers[0]?.name || primaryContact.name,
        phone: selectedUsers[0]?.phone || primaryContact.phone,
        priority: selectedUsers.length ? "selected" : primaryContact.priority,
      },
    });
  } catch (error) {
    res.status(500).json({
      message: "Server error",
      error: error.message,
    });
  }
};

// Move to Secondary Contact
const escalateToSecondary = async (req, res) => {
  try {
    const { emergencyId } = req.params;

    const emergency = await Emergency.findOne({
      _id: emergencyId,
      user: req.user.id,
    });

    if (!emergency) {
      return res.status(404).json({
        message: "Emergency not found",
      });
    }

    const secondaryContact = await TrustedContact.findOne({
      user: req.user.id,
      priority: "secondary",
      isActive: true,
    });

    if (!secondaryContact) {
      return res.status(404).json({
        message: "Secondary trusted contact not found",
      });
    }

    emergency.status = "secondary_alerted";
    emergency.currentContact = "secondary";

    await emergency.save();

    res.status(200).json({
      message: "Emergency escalated to secondary contact",
      emergency,
      alertedContact: {
        name: secondaryContact.name,
        phone: secondaryContact.phone,
        priority: secondaryContact.priority,
      },
    });
  } catch (error) {
    res.status(500).json({
      message: "Server error",
      error: error.message,
    });
  }
};

// Escalate to Emergency / Police
const escalateToEmergency = async (req, res) => {
  try {
    const { emergencyId } = req.params;

    const emergency = await Emergency.findOne({
      _id: emergencyId,
      user: req.user.id,
    });

    if (!emergency) {
      return res.status(404).json({
        message: "Emergency not found",
      });
    }

    emergency.status = "emergency";
    emergency.currentContact = "emergency";

    await emergency.save();

    res.status(200).json({
      message: "Emergency escalation activated",
      emergency,
      action: "Contact emergency services",
    });
  } catch (error) {
    res.status(500).json({
      message: "Server error",
      error: error.message,
    });
  }
};

// Get My Emergencies
const getMyEmergencies = async (req, res) => {
  try {
    const emergencies = await Emergency.find({
      user: req.user.id,
    })
      .populate("checkIn")
      .sort({ createdAt: -1 });

    res.status(200).json({
      emergencies,
    });
  } catch (error) {
    res.status(500).json({
      message: "Server error",
      error: error.message,
    });
  }
};

// Resolve Emergency
const resolveEmergency = async (req, res) => {
  try {
    const { emergencyId } = req.params;

    const emergency = await Emergency.findOne({
      _id: emergencyId,
      user: req.user.id,
    });

    if (!emergency) {
      return res.status(404).json({
        message: "Emergency not found",
      });
    }

    emergency.status = "resolved";

    await emergency.save();

    res.status(200).json({
      message: "Emergency resolved",
      emergency,
    });
  } catch (error) {
    res.status(500).json({
      message: "Server error",
      error: error.message,
    });
  }
};

module.exports = {
  startEmergency,
  escalateToSecondary,
  escalateToEmergency,
  getMyEmergencies,
  resolveEmergency,
};
