const mongoose = require("mongoose");
const User = require("../models/User");
const TrustRequest = require("../models/TrustRequest");
const TrustedContact = require("../models/TrustedContact");

const normalizePhone = (phone) => phone.trim().replace(/[\s().-]/g, "");

const sendRequest = async (req, res) => {
  const phone =
    typeof req.body.phone === "string" ? normalizePhone(req.body.phone) : "";
  const relationship =
    typeof req.body.relationship === "string"
      ? req.body.relationship.trim()
      : "";
  if (!phone || relationship.length < 2)
    return res
      .status(400)
      .json({ message: "Phone number and relationship are required." });
  try {
    const receiver = await User.findOne({ phone });
    if (!receiver)
      return res
        .status(400)
        .json({
          message:
            "This phone number is not registered on SafetyU. The person must create a SafetyU account before you can send a Trust request.",
        });
    if (receiver._id.toString() === req.user.id)
      return res
        .status(400)
        .json({ message: "You cannot send a Trust request to yourself." });
    const existing = await TrustRequest.findOne({
      sender: req.user.id,
      receiver: receiver._id,
    });
    if (existing?.status === "pending")
      return res
        .status(400)
        .json({ message: "A Trust request is already pending." });
    if (existing?.status === "accepted")
      return res
        .status(400)
        .json({ message: "This user is already your trusted contact." });
    const request = existing
      ? await TrustRequest.findByIdAndUpdate(
          existing._id,
          { status: "pending", relationship },
          { new: true },
        )
      : await TrustRequest.create({
          sender: req.user.id,
          receiver: receiver._id,
          relationship,
        });
    return res.status(201).json({ message: "Trust request sent.", request });
  } catch (error) {
    if (error?.code === 11000)
      return res
        .status(400)
        .json({ message: "A Trust request is already pending." });
    return res.status(500).json({ message: "Server error" });
  }
};

const receivedRequests = async (req, res) => {
  try {
    const requests = await TrustRequest.find({
      receiver: req.user.id,
      status: "pending",
    })
      .populate("sender", "name phone email")
      .sort({ createdAt: -1 });
    return res.json({ requests });
  } catch (_) {
    return res.status(500).json({ message: "Server error" });
  }
};

const respond = (status) => async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id))
    return res.status(404).json({ message: "Trust request not found." });
  try {
    const request = await TrustRequest.findOne({
      _id: req.params.id,
      receiver: req.user.id,
      status: "pending",
    });
    if (!request)
      return res.status(404).json({ message: "Trust request not found." });
    request.status = status;
    await request.save();
    if (status === "accepted") {
      const [sender, receiver] = await Promise.all([
        User.findById(request.sender),
        User.findById(request.receiver),
      ]);
      if (!sender || !receiver)
        return res
          .status(400)
          .json({ message: "Trust request users no longer exist." });
      // Both accounts receive a confirmed, private contact record only after
      // the receiver accepts. Phone is never the relationship identifier.
      await TrustedContact.updateOne(
        { user: sender._id, phone: receiver.phone },
        {
          $set: {
            contactUser: receiver._id,
            name: receiver.name,
            phone: receiver.phone,
            email: receiver.email,
            relationship: "Trusted Contact",
            priority: "secondary",
            availability: "available",
            isActive: true,
          },
        },
        { upsert: true },
      );
      await TrustedContact.updateOne(
        { user: receiver._id, phone: sender.phone },
        {
          $set: {
            contactUser: sender._id,
            name: sender.name,
            phone: sender.phone,
            email: sender.email,
            relationship: request.relationship,
            priority: "secondary",
            availability: "available",
            isActive: true,
          },
        },
        { upsert: true },
      );
    }
    return res.json({
      message:
        status === "accepted"
          ? "Trust request accepted."
          : "Trust request rejected.",
      request,
    });
  } catch (_) {
    return res.status(500).json({ message: "Server error" });
  }
};

module.exports = {
  sendRequest,
  receivedRequests,
  acceptRequest: respond("accepted"),
  rejectRequest: respond("rejected"),
};
