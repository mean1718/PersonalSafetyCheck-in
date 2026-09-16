require("dotenv").config({
  path: require("path").join(
    __dirname,
    "../config/.env"
  ),
});

const mongoose = require("mongoose");

const PoliceStation = require("../models/PoliceStation");
const ResponderOfficer = require("../models/ResponderOfficer");

const stations = [
  {
    name: "Phnom Penh Central Police Station",
    stationCode: "PP-CENTRAL",
    phone: "",
    address: "Phnom Penh, Cambodia",

    // IMPORTANT:
    // GeoJSON coordinates are [longitude, latitude].
    location: {
      type: "Point",
      coordinates: [104.9282, 11.5564],
    },

    isActive: true,
    isAvailable: true,
  },
];

const officers = [
  {
    officerId: "PP-4471",
    stationCode: "PP-CENTRAL",
    officerName: "",
    isActive: true,
    isAssigned: false,
  },

  {
    officerId: "PP-4472",
    stationCode: "PP-CENTRAL",
    officerName: "",
    isActive: true,
    isAssigned: false,
  },
];

async function seed() {
  try {
    if (!process.env.MONGODB_URI) {
      throw new Error("MONGODB_URI is not configured.");
    }

    await mongoose.connect(process.env.MONGODB_URI);

    console.log("MongoDB connected.");

    // ----------------------------------------
    // 1. Create / update police stations
    // ----------------------------------------

    const stationMap = {};

    for (const stationData of stations) {
      const station = await PoliceStation.findOneAndUpdate(
        {
          stationCode: stationData.stationCode,
        },
        stationData,
        {
          new: true,
          upsert: true,
          setDefaultsOnInsert: true,
        }
      );

      stationMap[station.stationCode] = station;

      console.log(
        `Station ready: ${station.name} (${station.stationCode})`
      );
    }

    // ----------------------------------------
    // 2. Create / update authorized officers
    // ----------------------------------------

    for (const officerData of officers) {
      const station =
        stationMap[officerData.stationCode];

      if (!station) {
        throw new Error(
          `Station ${officerData.stationCode} was not found.`
        );
      }

      const officer =
        await ResponderOfficer.findOneAndUpdate(
          {
            officerId: officerData.officerId,
          },
          {
            officerId: officerData.officerId,
            station: station._id,
            officerName: officerData.officerName,
            isActive: officerData.isActive,
            isAssigned: officerData.isAssigned,
          },
          {
            new: true,
            upsert: true,
            setDefaultsOnInsert: true,
          }
        );

      console.log(
        `Officer ready: ${officer.officerId} → ${station.stationCode}`
      );
    }

    console.log("");
    console.log("======================================");
    console.log("Responder data seeded successfully.");
    console.log("======================================");
    console.log("");
  } catch (error) {
    console.error(
      "Failed to seed responder data:",
      error.message
    );

    process.exitCode = 1;
  } finally {
    await mongoose.disconnect();
  }
}

seed();