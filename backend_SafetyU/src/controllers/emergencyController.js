const Emergency = require("../models/Emergency");
const CheckIn = require("../models/CheckIn");
const TrustedContact = require("../models/TrustedContact");
const Notification = require("../models/Notification");
const User = require("../models/User");
const { sendPushToUsers } = require("../services/pushService");

// =========================================================
// START EMERGENCY
// =========================================================

const startEmergency = async (req, res) => {
  try {
    const {
      checkInId,
      message,
      latitude,
      longitude,
      directEmergency: requestedDirectEmergency = false,
    } = req.body;

    // Emergency Assistant is also recognized by its dedicated message.
    // This keeps the flow working even if the Flutter screen does not
    // send the optional directEmergency flag.
    const directEmergency =
      requestedDirectEmergency === true ||
      String(message || "")
        .trim()
        .startsWith("Emergency Assistant");

    // -------------------------------------------------------
    // Check that the check-in belongs to the signed-in user.
    // -------------------------------------------------------

    const checkIn = await CheckIn.findOne({
      _id: checkInId,
      user: req.user.id,
    });

    if (!checkIn) {
      return res.status(404).json({
        message: "Check-in not found",
      });
    }

    // -------------------------------------------------------
    // Normal safety sessions still use trusted contacts.
    //
    // Emergency Assistant does NOT require a trusted contact.
    // The Emergency PIN already confirmed the user's intention.
    // -------------------------------------------------------

    let selectedUsers = [];
    let primaryContact = null;

    if (!directEmergency) {
      const selectedIds = checkIn.trustedContactUsers?.length
        ? checkIn.trustedContactUsers
        : checkIn.trustedContactUser
          ? [checkIn.trustedContactUser]
          : [];

      selectedUsers = selectedIds.length
        ? await User.find({
            _id: { $in: selectedIds },
          }).select("name phone")
        : [];

      primaryContact = selectedUsers.length
        ? null
        : await TrustedContact.findOne({
            user: req.user.id,
            priority: "primary",
            isActive: true,
          });

      if (!selectedUsers.length && !primaryContact) {
        return res.status(404).json({
          message: "Primary trusted contact not found",
        });
      }
    }

    // -------------------------------------------------------
    // Create Emergency
    // -------------------------------------------------------

    const emergency = await Emergency.create({
      user: req.user.id,
      checkIn: checkInId,

      status: directEmergency
        ? "emergency"
        : "primary_alerted",

      currentContact: directEmergency
        ? "emergency"
        : "primary",

      message:
        message || "Emergency assistance required",

      location: {
        latitude,
        longitude,
      },
    });

    // -------------------------------------------------------
    // Normal trusted-contact safety alert
    // -------------------------------------------------------

    if (!directEmergency && selectedUsers.length) {
      const existingAlert = await Notification.exists({
        checkIn: checkIn._id,
        type: "safety_alert",
      });

      if (!existingAlert) {
        const sender = await User.findById(req.user.id).select("name");

        await Notification.insertMany(
          selectedUsers.map((selectedUser) => ({
            receiver: selectedUser._id,
            sender: req.user.id,
            checkIn: checkIn._id,
            type: "safety_alert",
            title: "SafetyU Alert",
            message: `${sender?.name || "A trusted contact"} may need your attention.`,
          })),
        );

        sendPushToUsers(
          selectedUsers.map((u) => u._id),
          {
            title: "SafetyU Alert",
            body: `${sender?.name || "A trusted contact"} may need your attention.`,
            data: { type: "safety_alert", checkInId: checkIn._id.toString() },
          },
        );
      }
    }

    // -------------------------------------------------------
    // Direct Emergency Assistant response
    // -------------------------------------------------------

    if (directEmergency) {
      return res.status(201).json({
        message: "Emergency started",
        emergency,
        directEmergency: true,
      });
    }

    // -------------------------------------------------------
    // Normal emergency response
    // -------------------------------------------------------

    return res.status(201).json({
      message: "Emergency started",
      emergency,
      alertedContact: {
        name:
          selectedUsers[0]?.name ||
          primaryContact.name,

        phone:
          selectedUsers[0]?.phone ||
          primaryContact.phone,

        priority:
          selectedUsers.length
            ? "selected"
            : primaryContact.priority,
      },
    });
  } catch (error) {
    console.error(
      "Start emergency error:",
      error
    );

    return res.status(500).json({
      message: "Server error",
      error: error.message,
    });
  }
};

// =========================================================
// ESCALATE TO SECONDARY
// =========================================================

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

    const secondaryContact =
      await TrustedContact.findOne({
        user: req.user.id,
        priority: "secondary",
        isActive: true,
      });

    if (!secondaryContact) {
      return res.status(404).json({
        message:
          "Secondary trusted contact not found",
      });
    }

    emergency.status = "secondary_alerted";
    emergency.currentContact = "secondary";

    await emergency.save();

    return res.status(200).json({
      message:
        "Emergency escalated to secondary contact",

      emergency,

      alertedContact: {
        name: secondaryContact.name,
        phone: secondaryContact.phone,
        priority: secondaryContact.priority,
      },
    });
  } catch (error) {
    console.error(
      "Escalate to secondary error:",
      error
    );

    return res.status(500).json({
      message: "Server error",
    });
  }
};

// =========================================================
// ESCALATE TO EMERGENCY RESPONDER
// =========================================================

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

    // -------------------------------------------------------
    // Change emergency status
    // -------------------------------------------------------

    emergency.status = "emergency";
    emergency.currentContact = "emergency";

    await emergency.save();

    // -------------------------------------------------------
    // Find responder accounts
    //
    // We support both:
    //   role = "responder"
    //   role = "emergency"
    //
    // This keeps compatibility with older accounts.
    // -------------------------------------------------------

    const responders = await User.find({
      role: {
        $in: ["responder", "emergency"],
      },
    }).select(
      "_id name phone role"
    );

    // -------------------------------------------------------
    // Check whether this emergency already notified
    // a responder.
    // -------------------------------------------------------

    const existingNotifications =
      await Notification.find({
        emergency: emergency._id,
        type: "emergency_alert",
      }).select("receiver");

    const alreadyNotified = new Set(
      existingNotifications.map(
        (notification) =>
          notification.receiver.toString()
      )
    );

    // -------------------------------------------------------
    // Get emergency sender information
    // -------------------------------------------------------

    const sender = await User.findById(
      req.user.id
    ).select("name phone");

    // -------------------------------------------------------
    // Create responder notifications
    // -------------------------------------------------------

    const notificationsToCreate =
      responders
        .filter(
          (responder) =>
            !alreadyNotified.has(
              responder._id.toString()
            )
        )
        .map((responder) => ({
          receiver: responder._id,

          sender: req.user.id,

          checkIn: emergency.checkIn,

          emergency: emergency._id,

          type: "emergency_alert",

          title: "New Emergency",

          message:
            `${sender?.name || "A SafetyU user"} needs immediate emergency assistance.`,

          location: {
            latitude:
              emergency.location?.latitude,

            longitude:
              emergency.location?.longitude,
          },

          responseStatus: "pending",

          isRead: false,
        }));

    // -------------------------------------------------------
    // Save notifications
    // -------------------------------------------------------

    if (notificationsToCreate.length) {
      await Notification.insertMany(
        notificationsToCreate
      );
    }

    // -------------------------------------------------------
    // Return success
    // -------------------------------------------------------

    return res.status(200).json({
      message:
        "Emergency escalation activated",

      emergency,

      responderCount:
        responders.length,

      notificationsCreated:
        notificationsToCreate.length,

      action:
        "Emergency responder notification created",
    });
  } catch (error) {
    console.error(
      "Escalate to emergency error:",
      error
    );

    return res.status(500).json({
      message: "Server error",
      error: error.message,
    });
  }
};

// =========================================================
// GET MY EMERGENCIES
// =========================================================

const getMyEmergencies = async (req, res) => {
  try {
    const emergencies =
      await Emergency.find({
        user: req.user.id,
      })
        .populate("checkIn")
        .sort({
          createdAt: -1,
        });

    return res.status(200).json({
      emergencies,
    });
  } catch (error) {
    console.error(
      "Get my emergencies error:",
      error
    );

    return res.status(500).json({
      message: "Server error",
    });
  }
};

// =========================================================
// RESOLVE EMERGENCY
// =========================================================

const resolveEmergency = async (req, res) => {
  try {
    const { emergencyId } = req.params;

    const emergency =
      await Emergency.findOne({
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

    return res.status(200).json({
      message: "Emergency resolved",
      emergency,
    });
  } catch (error) {
    console.error(
      "Resolve emergency error:",
      error
    );

    return res.status(500).json({
      message: "Server error",
    });
  }
};

// =========================================================
// EXPORTS
// =========================================================

module.exports = {
  startEmergency,
  escalateToSecondary,
  escalateToEmergency,
  getMyEmergencies,
  resolveEmergency,
};