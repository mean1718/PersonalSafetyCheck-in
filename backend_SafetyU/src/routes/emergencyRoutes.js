const express = require("express");

const router = express.Router();

const {
  startEmergency,
  escalateToSecondary,
  escalateToEmergency,
  getMyEmergencies,
  getResponderEmergencies,
  acceptEmergency,
  resolveEmergency,
} = require("../controllers/emergencyController");

const protect =
  require("../middleware/authMiddleware");

const requireResponder =
  require("../middleware/responderMiddleware");

// =========================================================
// START EMERGENCY
// =========================================================

router.post(
  "/",
  protect,
  startEmergency
);

// =========================================================
// RESPONDER CASES
// =========================================================

router.get(
  "/responder/cases",
  protect,
  requireResponder,
  getResponderEmergencies
);

// =========================================================
// RESPONDER ACCEPTS CASE
// =========================================================

router.put(
  "/:emergencyId/accept",
  protect,
  requireResponder,
  acceptEmergency
);

// =========================================================
// GET USER'S EMERGENCIES
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
// RESPONDER RESOLVES EMERGENCY
// =========================================================

router.put(
  "/:emergencyId/resolve",
  protect,
  requireResponder,
  resolveEmergency
);

module.exports = router;