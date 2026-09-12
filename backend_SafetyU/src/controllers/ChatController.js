const mongoose = require("mongoose");
const ChatMessage = require("../models/ChatMessage");

// POST /api/chat  { receiverId, text, kind? }
const sendMessage = async (req, res) => {
  const { receiverId, text, kind } = req.body;
  if (!receiverId || !mongoose.isValidObjectId(receiverId)) {
    return res.status(400).json({ message: "A valid receiverId is required." });
  }
  if (!text || !text.trim()) {
    return res.status(400).json({ message: "Message text is required." });
  }
  if (receiverId === req.user.id) {
    return res.status(400).json({ message: "Cannot message yourself." });
  }
  try {
    const message = await ChatMessage.create({
      sender: req.user.id,
      receiver: receiverId,
      text: text.trim(),
      kind: ["text", "helpRequest", "safeCheckIn"].includes(kind) ? kind : "text",
    });
    return res.status(201).json({ message });
  } catch (_) {
    return res.status(500).json({ message: "Server error" });
  }
};

// GET /api/chat/:userId — every message between the signed-in user and
// :userId, oldest first, regardless of who sent which. Opening a
// conversation is what "reading" it means here, so this also marks every
// message the other person sent as read.
const getConversation = async (req, res) => {
  const { userId } = req.params;
  if (!mongoose.isValidObjectId(userId)) {
    return res.status(400).json({ message: "Invalid user id." });
  }
  try {
    const messages = await ChatMessage.find({
      $or: [
        { sender: req.user.id, receiver: userId },
        { sender: userId, receiver: req.user.id },
      ],
    }).sort({ createdAt: 1 });
    await ChatMessage.updateMany(
      { sender: userId, receiver: req.user.id, isRead: false },
      { $set: { isRead: true } }
    );
    return res.json({ messages });
  } catch (_) {
    return res.status(500).json({ message: "Server error" });
  }
};

// GET /api/chat/unread/counts — how many unread messages this account has
// from each sender, e.g. { counts: { "<userId>": 3 } }. Powers the badge
// on each friend's message icon without needing a full inbox screen.
const getUnreadCounts = async (req, res) => {
  try {
    const rows = await ChatMessage.aggregate([
      { $match: { receiver: new mongoose.Types.ObjectId(req.user.id), isRead: false } },
      { $group: { _id: "$sender", count: { $sum: 1 } } },
    ]);
    const counts = {};
    rows.forEach((row) => { counts[row._id.toString()] = row.count; });
    return res.json({ counts });
  } catch (_) {
    return res.status(500).json({ message: "Server error" });
  }
};

module.exports = { sendMessage, getConversation, getUnreadCounts };