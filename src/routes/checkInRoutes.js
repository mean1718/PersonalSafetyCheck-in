const express = require("express");

const router = express.Router();

const {
    startCheckIn,
    completeCheckIn,
    getMyCheckIns
} = require("../controllers/checkInController");

const protect = require("../middleware/authMiddleware");

// Start check-in
router.post("/", protect, startCheckIn);

// Complete check-in
router.put("/:id/complete", protect, completeCheckIn);

// Get my check-ins
router.get("/", protect, getMyCheckIns);

module.exports = router;