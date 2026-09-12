const express = require("express");
const router = express.Router();
const { sendMessage, getConversation, getUnreadCounts } = require("../controllers/ChatController");
const protect = require("../middleware/authMiddleware");

router.post("/", protect, sendMessage);
router.get("/unread/counts", protect, getUnreadCounts);
router.get("/:userId", protect, getConversation);

module.exports = router;