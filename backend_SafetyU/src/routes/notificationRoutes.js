const express = require("express");
const { getMyNotifications, getMyActiveSafetyAlerts, markRead, respondToSafetyAlert } = require("../controllers/notificationController");
const protect = require("../middleware/authMiddleware");
const router = express.Router();
router.get("/", protect, getMyNotifications);
router.get("/alerts", protect, getMyActiveSafetyAlerts);
router.put("/:id/read", protect, markRead);
router.put("/:id/response", protect, respondToSafetyAlert);
module.exports = router;
