const mongoose = require("mongoose");

// A 1:1 message between two real accounts. Not tied to a specific
// CheckIn — a Trust relationship's conversation is ongoing, the same way
// texting a friend is, so messages sent during a safety session (Need
// Help / I'm Safe) live in the same thread as any other message between
// these two people.
const chatMessageSchema = new mongoose.Schema({
  sender: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true, index: true },
  receiver: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true, index: true },
  text: { type: String, required: true, trim: true },
  // Lets the client show "Need Help" / "I'm Safe" messages with distinct
  // styling instead of a plain bubble, without needing a second query.
  kind: {
    type: String,
    enum: ["text", "helpRequest", "safeCheckIn"],
    default: "text",
  },
  isRead: { type: Boolean, default: false },
}, { timestamps: true });

module.exports = mongoose.model("ChatMessage", chatMessageSchema);