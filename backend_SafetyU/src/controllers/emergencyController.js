const Emergency = require("../models/Emergency");
const CheckIn = require("../models/CheckIn");
const TrustedContact = require("../models/TrustedContact");
const Notification = require("../models/Notification");
const User = require("../models/User");
const ResponderOfficer = require("../models/ResponderOfficer");
const PoliceStation = require("../models/PoliceStation");

const { sendPushToUsers, sendPushToUser } = require("../services/pushService");

// =========================================================
// HELPERS
// =========================================================

/**
 * Find the ResponderOfficer record belonging to the
 * currently logged-in responder.
 */
const getResponderOfficer = async (req) => {
  if (!req.user?.officerId) {
    return null;
  }

  return ResponderOfficer.findOne({
    officerId: req.user.officerId,
    isActive: true,
  }).populate("station");
};

/**
 * Create a notification for the emergency owner.
 *
 * Deduplicated by:
 *   receiver + emergency + type + title
 */
const notifyEmergencyOwner = async ({
  emergency,
  responderId,
  title,
  message,
  status,
}) => {
  const existing = await Notification.findOne({
    receiver: emergency.user,
    emergency: emergency._id,
    type: "emergency_alert",
    title,
  });

  if (existing) {
    return existing;
  }

  const notification = await Notification.create({
    receiver: emergency.user,
    sender: responderId,
    checkIn: emergency.checkIn,
    emergency: emergency._id,
    type: "emergency_alert",
    title,
    message,
    location: {
      latitude: emergency.location?.latitude,
      longitude: emergency.location?.longitude,
    },
    responseStatus: "pending",
    isRead: false,
    resolved: status === "resolved",
  });

  sendPushToUser(emergency.user, {
    title,
    body: message,
    data: {
      type: "emergency_status",
      emergencyId: emergency._id.toString(),
      status,
    },
  });

  return notification;
};

// =========================================================
// DISTANCE HELPER
// =========================================================

/**
 * Calculate distance between two GPS coordinates.
 *
 * Returns kilometres.
 */
const calculateDistanceKm = (latitude1, longitude1, latitude2, longitude2) => {
  const earthRadiusKm = 6371;

  const toRadians = (degrees) => degrees * (Math.PI / 180);

  const dLatitude = toRadians(latitude2 - latitude1);

  const dLongitude = toRadians(longitude2 - longitude1);

  const lat1 = toRadians(latitude1);
  const lat2 = toRadians(latitude2);

  const a =
    Math.sin(dLatitude / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLongitude / 2) ** 2;

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return earthRadiusKm * c;
};

// =========================================================
// FIND AND ASSIGN NEAREST AVAILABLE RESPONDER
// =========================================================
//
// Availability is determined by:
//
// 1. Station is active
// 2. Station is not explicitly unavailable
// 3. ResponderOfficer is active
// 4. Responder account exists
// 5. Responder role is "responder"
// 6. Responder is approved
// 7. Responder is currently online
//
// Assignment is saved immediately on the Emergency.
//
// Therefore, polling from multiple Flutter windows cannot
// independently choose different responders.
//
// Tie-break:
// If eligible responders are within 10 metres of the same
// distance, the smallest Officer ID wins.
//
// =========================================================

const findAndAssignNearestAvailableResponder = async (emergency) => {
  // -------------------------------------------------------
  // Never overwrite an existing assignment.
  // -------------------------------------------------------

  if (emergency.assignedStation && emergency.assignedResponder) {
    const station = await PoliceStation.findById(emergency.assignedStation);

    const responder = await User.findById(emergency.assignedResponder);

    return {
      station,
      responder,
      alreadyAssigned: true,
    };
  }

  // -------------------------------------------------------
  // Validate emergency GPS.
  // -------------------------------------------------------

  const latitude = Number(emergency.location?.latitude);

  const longitude = Number(emergency.location?.longitude);

  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    return null;
  }

  // -------------------------------------------------------
  // Find active police stations.
  // -------------------------------------------------------

  const stations = await PoliceStation.find({
    isActive: true,
    "location.type": "Point",
  });

  if (!stations.length) {
    return null;
  }

  const stationIds = stations.map((station) => station._id);

  // -------------------------------------------------------
  // Find active officers belonging to these stations.
  // -------------------------------------------------------

  const officers = await ResponderOfficer.find({
    station: {
      $in: stationIds,
    },
    isActive: true,
  })
    .populate("user", "name phone role responderStatus isOnline")
    .populate(
      "station",
      "name stationCode phone address location isActive isAvailable",
    );

  // -------------------------------------------------------
  // Filter to currently eligible responders.
  // -------------------------------------------------------

  const eligible = officers.filter((officer) => {
    const responder = officer.user;

    const station = officer.station;

    if (!responder || !station) {
      return false;
    }

    // Must be a responder account.
    if (responder.role !== "responder") {
      return false;
    }

    // Must be approved.
    if (responder.responderStatus !== "approved") {
      return false;
    }

    // Must currently be logged in/online.
    if (responder.isOnline !== true) {
      return false;
    }

    // Station itself must be active.
    if (station.isActive !== true) {
      return false;
    }

    // If station has been explicitly disabled,
    // it is not eligible.
    if (station.isAvailable === false) {
      return false;
    }

    const coordinates = station.location?.coordinates;

    if (!Array.isArray(coordinates) || coordinates.length < 2) {
      return false;
    }

    const stationLongitude = Number(coordinates[0]);

    const stationLatitude = Number(coordinates[1]);

    if (
      !Number.isFinite(stationLatitude) ||
      !Number.isFinite(stationLongitude)
    ) {
      return false;
    }

    return true;
  });

  if (!eligible.length) {
    return null;
  }

  // -------------------------------------------------------
  // Calculate distance for every eligible officer.
  // -------------------------------------------------------

  const candidates = eligible.map((officer) => {
    const station = officer.station;

    const coordinates = station.location.coordinates;

    const stationLongitude = Number(coordinates[0]);

    const stationLatitude = Number(coordinates[1]);

    const distanceKm = calculateDistanceKm(
      latitude,
      longitude,
      stationLatitude,
      stationLongitude,
    );

    return {
      officer,
      station,
      responder: officer.user,
      distanceKm,
    };
  });

  // -------------------------------------------------------
  // Sort nearest first.
  // -------------------------------------------------------

  candidates.sort((a, b) => a.distanceKm - b.distanceKm);

  const nearestDistance = candidates[0].distanceKm;

  // -------------------------------------------------------
  // Tie tolerance: 10 metres.
  // -------------------------------------------------------

  const tiedCandidates = candidates.filter(
    (candidate) => Math.abs(candidate.distanceKm - nearestDistance) <= 0.01,
  );

  // -------------------------------------------------------
  // Tie-break using Officer ID.
  //
  // Example:
  // PP-004 beats PP-005.
  // -------------------------------------------------------

  tiedCandidates.sort((a, b) =>
    String(a.officer.officerId).localeCompare(
      String(b.officer.officerId),
      undefined,
      {
        numeric: true,
        sensitivity: "base",
      },
    ),
  );

  const selected = tiedCandidates[0];

  // -------------------------------------------------------
  // Save assignment immediately.
  // -------------------------------------------------------

  emergency.assignedStation = selected.station._id;

  emergency.assignedResponder = selected.responder._id;

  emergency.assignedAt = new Date();

  await emergency.save();

  return {
    station: selected.station,

    responder: selected.responder,

    distanceKm: selected.distanceKm,

    alreadyAssigned: false,
  };
};

// =========================================================
// NOTIFY ASSIGNED RESPONDER
// =========================================================
//
// Only ONE responder receives the emergency notification.
//
// Deduplicated by emergency + receiver + notification type.
// =========================================================

const notifyAssignedResponder = async (emergency, senderId) => {
  if (!emergency.assignedResponder) {
    return 0;
  }

  const existing = await Notification.findOne({
    emergency: emergency._id,
    receiver: emergency.assignedResponder,
    type: "emergency_alert",
    title: "New Emergency",
  });

  if (existing) {
    return 0;
  }

  const sender = await User.findById(senderId).select("name phone");

  await Notification.create({
    receiver: emergency.assignedResponder,

    sender: senderId,

    checkIn: emergency.checkIn,

    emergency: emergency._id,

    type: "emergency_alert",

    title: "New Emergency",

    message: `${sender?.name || "A SafetyU user"} needs immediate emergency assistance.`,

    location: {
      latitude: emergency.location?.latitude,

      longitude: emergency.location?.longitude,
    },

    responseStatus: "pending",

    isRead: false,

    resolved: false,
  });

  sendPushToUser(emergency.assignedResponder, {
    title: "New Emergency",

    body: `${sender?.name || "A SafetyU user"} needs immediate emergency assistance.`,

    data: {
      type: "emergency_alert",

      emergencyId: emergency._id.toString(),
    },
  });

  return 1;
};

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

    // Emergency Assistant is also recognized by its message.
    const directEmergency =
      requestedDirectEmergency === true ||
      String(message || "")
        .trim()
        .startsWith("Emergency Assistant");

    // -------------------------------------------------------
    // Check-in must belong to signed-in user.
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
    // Emergency Assistant does not.
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
            _id: {
              $in: selectedIds,
            },
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
    // CREATE EMERGENCY
    // -------------------------------------------------------

    const emergency = await Emergency.create({
      user: req.user.id,

      checkIn: checkInId,

      status: directEmergency ? "emergency" : "primary_alerted",

      currentContact: directEmergency ? "emergency" : "primary",

      message: message || "Emergency assistance required",

      location: {
        latitude,
        longitude,
      },
    });

    // -------------------------------------------------------
    // NORMAL TRUSTED-CONTACT ALERT
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

            data: {
              type: "safety_alert",

              checkInId: checkIn._id.toString(),

              ownerName: sender?.name || "A trusted contact",
            },
          },
        );
      }
    }

    // -------------------------------------------------------
    // FALLBACK: no contacts were picked for this session, so the primary
    // trusted contact was found instead -- but nobody was actually
    // notified, so the emergency started silently. If that contact has a
    // SafetyU account, alert them now.
    // -------------------------------------------------------

    if (
      !directEmergency &&
      !selectedUsers.length &&
      primaryContact?.contactUser
    ) {
      const existingAlert = await Notification.exists({
        checkIn: checkIn._id,
        type: "safety_alert",
        receiver: primaryContact.contactUser,
      });
      if (!existingAlert) {
        const sender = await User.findById(req.user.id).select("name");
        const alertText = `${sender?.name || "A trusted contact"} may need your attention.`;
        await Notification.create({
          receiver: primaryContact.contactUser,
          sender: req.user.id,
          checkIn: checkIn._id,
          type: "safety_alert",
          title: "SafetyU Alert",
          message: alertText,
          ...(latitude != null && longitude != null
            ? { location: { latitude, longitude } }
            : {}),
        });
        sendPushToUser(primaryContact.contactUser, {
          title: "SafetyU Alert",
          body: alertText,
          data: {
            type: "safety_alert",
            checkInId: checkIn._id.toString(),
            ownerName: sender?.name || "A trusted contact",
          },
        });
      }
    }

    // -------------------------------------------------------
    // DIRECT EMERGENCY ASSISTANT
    //
    // Assign immediately to the nearest available responder.
    // -------------------------------------------------------

    if (directEmergency) {
      const assignment =
        await findAndAssignNearestAvailableResponder(emergency);

      let notificationsCreated = 0;

      if (assignment) {
        notificationsCreated = await notifyAssignedResponder(
          emergency,
          req.user.id,
        );
      }

      return res.status(201).json({
        message: assignment
          ? "Emergency started and assigned to the nearest available responder."
          : "Emergency started. No available responder was found.",

        emergency,

        directEmergency: true,

        assigned: Boolean(assignment),

        notificationsCreated,
      });
    }

    // -------------------------------------------------------
    // NORMAL EMERGENCY RESPONSE
    // -------------------------------------------------------

    return res.status(201).json({
      message: "Emergency started",

      emergency,

      alertedContact: {
        name: selectedUsers[0]?.name || primaryContact?.name,

        phone: selectedUsers[0]?.phone || primaryContact?.phone,

        priority: selectedUsers.length ? "selected" : primaryContact?.priority,
      },
    });
  } catch (error) {
    console.error("Start emergency error:", error);

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

    return res.status(200).json({
      message: "Emergency escalated to secondary contact",

      emergency,

      alertedContact: {
        name: secondaryContact.name,

        phone: secondaryContact.phone,

        priority: secondaryContact.priority,
      },
    });
  } catch (error) {
    console.error("Escalate to secondary error:", error);

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

    emergency.status = "emergency";

    emergency.currentContact = "emergency";

    await emergency.save();

    // -------------------------------------------------------
    // Assign only if not already assigned.
    // -------------------------------------------------------

    const assignment = await findAndAssignNearestAvailableResponder(emergency);

    let notificationsCreated = 0;

    if (assignment) {
      notificationsCreated = await notifyAssignedResponder(
        emergency,
        req.user.id,
      );
    }

    return res.status(200).json({
      message: assignment
        ? "Emergency escalation activated and assigned."
        : "Emergency escalation activated, but no available responder was found.",

      emergency,

      notificationsCreated,

      assigned: Boolean(assignment),

      action: assignment
        ? "Nearest available responder notified."
        : "No available responder was found.",
    });
  } catch (error) {
    console.error("Escalate to emergency error:", error);

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
    const emergencies = await Emergency.find({
      user: req.user.id,
    })
      .populate("checkIn")
      .populate("assignedStation", "name stationCode phone address location")
      .populate("assignedResponder", "name phone officerId")
      .sort({
        createdAt: -1,
      });

    return res.status(200).json({
      emergencies,
    });
  } catch (error) {
    console.error("Get my emergencies error:", error);

    return res.status(500).json({
      message: "Server error",
    });
  }
};

// =========================================================
// GET RESPONDER CASES
// =========================================================
//
// IMPORTANT:
// A responder only sees emergencies assigned to that
// responder. There is no broadcast/polling race here.
//
// =========================================================

const getResponderEmergencies = async (req, res) => {
  try {
    const emergencies = await Emergency.find({
      assignedResponder: req.user.id,

      status: {
        $in: ["emergency", "in_progress", "resolved"],
      },
    })
      .populate("user", "name phone")
      .populate("assignedStation", "name stationCode phone address location")
      .populate("assignedResponder", "name phone officerId")
      .sort({
        createdAt: -1,
      });

    return res.status(200).json({
      emergencies,
    });
  } catch (error) {
    console.error("Get responder emergencies error:", error);

    return res.status(500).json({
      message: "Server error",
      error: error.message,
    });
  }
};

// =========================================================
// ACCEPT EMERGENCY
// =========================================================

const acceptEmergency = async (req, res) => {
  try {
    const { emergencyId } = req.params;

    const emergency = await Emergency.findById(emergencyId);

    if (!emergency) {
      return res.status(404).json({
        message: "Emergency not found",
      });
    }

    if (emergency.status === "resolved") {
      return res.status(409).json({
        message: "This emergency is already resolved.",
      });
    }

    // -------------------------------------------------------
    // Emergency must already have been assigned.
    // -------------------------------------------------------

    if (!emergency.assignedResponder) {
      return res.status(409).json({
        message: "This emergency has not been assigned to a responder yet.",
      });
    }

    // -------------------------------------------------------
    // Only the assigned responder can accept it.
    // -------------------------------------------------------

    if (emergency.assignedResponder.toString() !== req.user.id) {
      return res.status(409).json({
        message: "This emergency is assigned to another responder.",
      });
    }

    // -------------------------------------------------------
    // Idempotent accept.
    // -------------------------------------------------------

    if (emergency.status === "in_progress") {
      return res.status(200).json({
        message: "Emergency already accepted.",

        emergency,
      });
    }

    // -------------------------------------------------------
    // Save status.
    // -------------------------------------------------------

    emergency.status = "in_progress";

    emergency.currentContact = "emergency";

    emergency.assignedAt = emergency.assignedAt || new Date();

    await emergency.save();

    // -------------------------------------------------------
    // Mark responder notification read.
    // -------------------------------------------------------

    await Notification.updateMany(
      {
        emergency: emergency._id,

        receiver: req.user.id,

        type: "emergency_alert",
      },
      {
        $set: {
          isRead: true,

          responseStatus: "can_help",

          respondedAt: new Date(),
        },
      },
    );

    // -------------------------------------------------------
    // Get assigned station.
    // -------------------------------------------------------

    const station = await PoliceStation.findById(emergency.assignedStation);

    const stationName = station?.name || "The assigned police station";

    // -------------------------------------------------------
    // Notify user.
    // -------------------------------------------------------

    await notifyEmergencyOwner({
      emergency,

      responderId: req.user.id,

      title: "Emergency Accepted",

      message: `${stationName} has accepted your emergency.`,

      status: "accepted",
    });

    // -------------------------------------------------------
    // Return populated emergency.
    // -------------------------------------------------------

    const populatedEmergency = await Emergency.findById(emergency._id)
      .populate("user", "name phone")
      .populate("assignedStation", "name stationCode phone address location")
      .populate("assignedResponder", "name phone officerId");

    return res.status(200).json({
      message: "Emergency accepted",

      emergency: populatedEmergency,
    });
  } catch (error) {
    console.error("Accept emergency error:", error);

    return res.status(500).json({
      message: "Server error",
      error: error.message,
    });
  }
};

// =========================================================
// RESOLVE EMERGENCY
// =========================================================

const resolveEmergency = async (req, res) => {
  try {
    const { emergencyId } = req.params;

    const emergency = await Emergency.findById(emergencyId);

    if (!emergency) {
      return res.status(404).json({
        message: "Emergency not found",
      });
    }

    const isOwner = emergency.user.toString() === req.user.id;

    const isAssignedResponder =
      req.user.role === "responder" &&
      emergency.assignedResponder?.toString() === req.user.id;

    if (!isOwner && !isAssignedResponder) {
      return res.status(403).json({
        message: "You are not assigned to this emergency.",
      });
    }

    if (emergency.status === "resolved") {
      return res.status(200).json({
        message: "Emergency already resolved",

        emergency,
      });
    }

    emergency.status = "resolved";

    await emergency.save();

    // -------------------------------------------------------
    // Responder resolved the emergency.
    // -------------------------------------------------------

    if (isAssignedResponder && emergency.assignedStation) {
      const station = await PoliceStation.findById(emergency.assignedStation);

      const stationName = station?.name || "The assigned police station";

      const resolvedMessage = `${stationName} has resolved your emergency.`;

      await notifyEmergencyOwner({
        emergency,

        responderId: req.user.id,

        title: "Emergency Resolved",

        message: resolvedMessage,

        status: "resolved",
      });

      // -----------------------------------------------------
      // Mark responder-side notifications resolved.
      // -----------------------------------------------------

      await Notification.updateMany(
        {
          emergency: emergency._id,

          receiver: req.user.id,

          type: "emergency_alert",
        },
        {
          $set: {
            isRead: true,
            resolved: true,
          },
        },
      );
    } else if (isOwner) {
      // -----------------------------------------------------
      // User resolved it directly.
      // -----------------------------------------------------

      await notifyEmergencyOwner({
        emergency,

        responderId: req.user.id,

        title: "Emergency Resolved",

        message: "Your emergency has been resolved.",

        status: "resolved",
      });
    }

    // -------------------------------------------------------
    // Return populated emergency.
    // -------------------------------------------------------

    const populatedEmergency = await Emergency.findById(emergency._id)
      .populate("user", "name phone")
      .populate("assignedStation", "name stationCode phone address location")
      .populate("assignedResponder", "name phone officerId");

    return res.status(200).json({
      message: "Emergency resolved",

      emergency: populatedEmergency,
    });
  } catch (error) {
    console.error("Resolve emergency error:", error);

    return res.status(500).json({
      message: "Server error",

      error: error.message,
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
  getResponderEmergencies,
  acceptEmergency,
  resolveEmergency,
};
