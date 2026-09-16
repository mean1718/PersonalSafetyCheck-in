const mongoose = require("mongoose");

const responderOfficerSchema = new mongoose.Schema(
  {
    officerId: {
      type: String,
      required: true,
      unique: true,
      trim: true,
      uppercase: true,
    },

    station: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "PoliceStation",
      required: true,
    },

    officerName: {
      type: String,
      trim: true,
      default: "",
    },

    isActive: {
      type: Boolean,
      default: true,
    },

    isAssigned: {
      type: Boolean,
      default: false,
    },

    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null,
    },
  },
  {
    timestamps: true,
  }
);

module.exports = mongoose.model(
  "ResponderOfficer",
  responderOfficerSchema
);