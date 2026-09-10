const express = require("express");

const router = express.Router();

const {
    getSessionTrustedContacts,
    startCheckIn,
    completeCheckIn,
    getMyCheckIns,
    getAlertStatus
} = require("../controllers/checkInController");

const protect = require("../middleware/authMiddleware");

router.get("/trusted-contacts", protect, getSessionTrustedContacts);

// Start check-in
router.post("/", protect, startCheckIn);

// Complete check-in
router.put("/:id/complete", protect, completeCheckIn);

router.get("/:id/alert-status", protect, getAlertStatus);

// Get my check-ins
router.get("/", protect, getMyCheckIns);

module.exports = router;
