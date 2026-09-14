const express = require("express");

const router = express.Router();

const {
  getSessionTrustedContacts,
  startCheckIn,
  completeCheckIn,
  getMyCheckIns,
  getAlertStatus,
  updateLocation,
  viewSessionLocation,
  needHelpNow,
} = require("../controllers/checkInController");
const protect = require("../middleware/authMiddleware");

router.get("/trusted-contacts", protect, getSessionTrustedContacts);

// Start check-in
router.post("/", protect, startCheckIn);

// Complete check-in
router.put("/:id/complete", protect, completeCheckIn);

router.get("/:id/alert-status", protect, getAlertStatus);

// NEW: Safety User's phone sends live GPS updates here while session is active
router.put("/:id/location", protect, updateLocation);

// NEW: Safety User (their own session) or an alerted Trusted Contact reads the live location here
router.get("/:id/location", protect, viewSessionLocation);

// Re-alert contacts right now (real Need Help escalation)
router.post("/:id/need-help", protect, needHelpNow);
// Get my check-ins
router.get("/", protect, getMyCheckIns);

module.exports = router;