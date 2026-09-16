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

// =========================================================
// START EMERGENCY
// =========================================================

router.post(
  "/",
  protect,
  startEmergency
);

// =========================================================
// GET MY EMERGENCIES
// =========================================================

router.get(
  "/",
  protect,
  getMyEmergencies
);

// =========================================================
// PRIMARY → SECONDARY
// =========================================================

router.post(
  "/:emergencyId/secondary",
  protect,
  escalateToSecondary
);

// =========================================================
// SECONDARY → EMERGENCY RESPONDER
// =========================================================

router.post(
  "/:emergencyId/emergency",
  protect,
  escalateToEmergency
);

// =========================================================
// RESOLVE EMERGENCY
// =========================================================

router.put(
  "/:emergencyId/resolve",
  protect,
  resolveEmergency
);

module.exports = router;