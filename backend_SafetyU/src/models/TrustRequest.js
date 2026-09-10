const mongoose = require("mongoose");

const trustRequestSchema = new mongoose.Schema({
  sender: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
  receiver: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
  relationship: { type: String, required: true, trim: true },
  status: { type: String, enum: ["pending", "accepted", "rejected"], default: "pending" },
}, { timestamps: true });

trustRequestSchema.index({ sender: 1, receiver: 1 }, { unique: true });
module.exports = mongoose.model("TrustRequest", trustRequestSchema);
