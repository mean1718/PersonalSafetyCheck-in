const express = require("express");

const router = express.Router();

const {
  getSessionTrustedContacts,
  startCheckIn,
  completeCheckIn,
  completeAllMyActiveCheckIns,
  getMyCheckIns,
  getAlertStatus,
  updateLocation,
  viewSessionLocation,
  needHelpNow,
  confirmContactSafe,
  extendCheckIn,
} = require("../controllers/checkInController");
const protect = require("../middleware/authMiddleware");

router.get("/trusted-contacts", protect, getSessionTrustedContacts);

// Start check-in
router.post("/", protect, startCheckIn);

// One-time cleanup: complete every one of MY OWN stuck-active check-ins.
router.post("/complete-all-active", protect, completeAllMyActiveCheckIns);

// Complete check-in
router.put("/:id/complete", protect, completeCheckIn);

router.get("/:id/alert-status", protect, getAlertStatus);

// NEW: Safety User's phone sends live GPS updates here while session is active
router.put("/:id/location", protect, updateLocation);

// NEW: Safety User (their own session) or an alerted Trusted Contact reads the live location here
router.get("/:id/location", protect, viewSessionLocation);

// Re-alert contacts right now (real Need Help escalation)
router.post("/:id/need-help", protect, needHelpNow);

// A trusted contact confirms the owner is safe -- see confirmContactSafe.
router.post("/:id/confirm-safe", protect, confirmContactSafe);

// The owner asked for more time -- moves the server-side deadline too.
router.put("/:id/extend", protect, extendCheckIn);

// Get my check-ins
router.get("/", protect, getMyCheckIns);

module.exports = router;
