const mongoose = require("mongoose");

// One doc per user, upserted on every ping — this is a "where are they
// right now" pointer, not a location history log.
const locationSchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      unique: true,
      index: true,
    },
    latitude: { type: Number, required: true, min: -90, max: 90 },
    longitude: { type: Number, required: true, min: -180, max: 180 },
    accuracy: { type: Number }, // meters, from the device GPS
    heading: { type: Number }, // degrees, optional

    // Off by default. A user only becomes visible to their trusted
    // contacts once they explicitly turn sharing on from the app, and can
    // turn it off at any time — turning it off stops them showing up in
    // anyone's "contacts' locations" list immediately.
    sharingEnabled: { type: Boolean, default: false },
  },
  { timestamps: true },
);

module.exports = mongoose.model("Location", locationSchema);
