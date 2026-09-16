const mongoose = require("mongoose");

const policeStationSchema = new mongoose.Schema(
  {
    name: {
      type: String,
      required: true,
      trim: true,
    },

    stationCode: {
      type: String,
      required: true,
      unique: true,
      trim: true,
      uppercase: true,
    },

    phone: {
      type: String,
      trim: true,
      default: "",
    },

    address: {
      type: String,
      trim: true,
      default: "",
    },

    location: {
      type: {
        type: String,
        enum: ["Point"],
        required: true,
      },

      coordinates: {
        type: [Number],
        required: true,
      },
    },

    isActive: {
      type: Boolean,
      default: true,
    },

    isAvailable: {
      type: Boolean,
      default: true,
    },
  },
  {
    timestamps: true,
  }
);

// Allows MongoDB to find stations near an emergency location.
policeStationSchema.index({
  location: "2dsphere",
});

module.exports = mongoose.model(
  "PoliceStation",
  policeStationSchema
);