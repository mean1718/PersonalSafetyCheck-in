const express = require("express");

const router = express.Router();

const {
  startEmergency,
  escalateToSecondary,
  escalateToEmergency,
  getMyEmergencies,
  resolveEmergency,
} = require("../controllers/emergencyController");

const protect = require("../middleware/authMiddleware");

// Start emergency
router.post("/", protect, startEmergency);

// Get my emergencies
router.get("/", protect, getMyEmergencies);

// Primary → Secondary
router.post(
  "/:emergencyId/secondary",
  protect,
  escalateToSecondary
);

// Secondary → Emergency / Police
router.post(
  "/:emergencyId/emergency",
  protect,
  escalateToEmergency
);

// Resolve emergency
router.put(
  "/:emergencyId/resolve",
  protect,
  resolveEmergency
);

module.exports = router;