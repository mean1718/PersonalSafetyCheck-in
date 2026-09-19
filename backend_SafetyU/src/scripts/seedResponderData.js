require("dotenv").config({
  path: require("path").join(
    __dirname,
    "../config/.env"
  ),
});

const mongoose = require("mongoose");

const PoliceStation = require("../models/PoliceStation");
const ResponderOfficer = require("../models/ResponderOfficer");
const User = require("../models/User");

//
// ============================================================
// DEMO RESPONDER DATA
// ============================================================
//
// 1 Officer ID = 1 Officer = 1 Station
//
// These are DEMO authorization IDs.
// They should NOT be used as passwords.
//
// Production should issue secure, one-time activation codes
// tied to a specific station/officer.
//

const stations = [
  {
    name: "SafetyU Demo Police Station 01",
    stationCode: "PP-DEMO-001",
    phone: "",
    address: "SafetyU Demo Area 01, Phnom Penh, Cambodia",

    // GeoJSON = [longitude, latitude]
    location: {
      type: "Point",
      coordinates: [104.9000, 11.5500],
    },

    isActive: true,

    // This is an administrative station setting.
    // Responder online status comes from User.isOnline.
    isAvailable: true,
  },

  {
    name: "SafetyU Demo Police Station 02",
    stationCode: "PP-DEMO-002",
    phone: "",
    address: "SafetyU Demo Area 02, Phnom Penh, Cambodia",

    location: {
      type: "Point",
      coordinates: [104.9100, 11.5500],
    },

    isActive: true,
    isAvailable: true,
  },

  {
    name: "SafetyU Demo Police Station 03",
    stationCode: "PP-DEMO-003",
    phone: "",
    address: "SafetyU Demo Area 03, Phnom Penh, Cambodia",

    location: {
      type: "Point",
      coordinates: [104.9200, 11.5500],
    },

    isActive: true,
    isAvailable: true,
  },

  {
    name: "SafetyU Demo Police Station 04",
    stationCode: "PP-DEMO-004",
    phone: "",
    address: "SafetyU Demo Area 04, Phnom Penh, Cambodia",

    location: {
      type: "Point",
      coordinates: [104.9300, 11.5500],
    },

    isActive: true,
    isAvailable: true,
  },

  {
    name: "SafetyU Demo Police Station 05",
    stationCode: "PP-DEMO-005",
    phone: "",
    address: "SafetyU Demo Area 05, Phnom Penh, Cambodia",

    location: {
      type: "Point",
      coordinates: [104.9400, 11.5500],
    },

    isActive: true,
    isAvailable: true,
  },

  {
    name: "SafetyU Demo Police Station 06",
    stationCode: "PP-DEMO-006",
    phone: "",
    address: "SafetyU Demo Area 06, Phnom Penh, Cambodia",

    location: {
      type: "Point",
      coordinates: [104.9000, 11.5600],
    },

    isActive: true,
    isAvailable: true,
  },

  {
    name: "SafetyU Demo Police Station 07",
    stationCode: "PP-DEMO-007",
    phone: "",
    address: "SafetyU Demo Area 07, Phnom Penh, Cambodia",

    location: {
      type: "Point",
      coordinates: [104.9100, 11.5600],
    },

    isActive: true,
    isAvailable: true,
  },

  {
    name: "SafetyU Demo Police Station 08",
    stationCode: "PP-DEMO-008",
    phone: "",
    address: "SafetyU Demo Area 08, Phnom Penh, Cambodia",

    location: {
      type: "Point",
      coordinates: [104.9200, 11.5600],
    },

    isActive: true,
    isAvailable: true,
  },

  {
    name: "SafetyU Demo Police Station 09",
    stationCode: "PP-DEMO-009",
    phone: "",
    address: "SafetyU Demo Area 09, Phnom Penh, Cambodia",

    location: {
      type: "Point",
      coordinates: [104.9300, 11.5600],
    },

    isActive: true,
    isAvailable: true,
  },

  {
    name: "SafetyU Demo Police Station 10",
    stationCode: "PP-DEMO-010",
    phone: "",
    address: "SafetyU Demo Area 10, Phnom Penh, Cambodia",

    location: {
      type: "Point",
      coordinates: [104.9400, 11.5600],
    },

    isActive: true,
    isAvailable: true,
  },
];

const officers = [
  {
    officerId: "PP-001",
    stationCode: "PP-DEMO-001",
    officerName: "Demo Officer 01",
    isActive: true,
    isAssigned: false,
  },

  {
    officerId: "PP-002",
    stationCode: "PP-DEMO-002",
    officerName: "Demo Officer 02",
    isActive: true,
    isAssigned: false,
  },

  {
    officerId: "PP-003",
    stationCode: "PP-DEMO-003",
    officerName: "Demo Officer 03",
    isActive: true,
    isAssigned: false,
  },

  {
    officerId: "PP-004",
    stationCode: "PP-DEMO-004",
    officerName: "Demo Officer 04",
    isActive: true,
    isAssigned: false,
  },

  {
    officerId: "PP-005",
    stationCode: "PP-DEMO-005",
    officerName: "Demo Officer 05",
    isActive: true,
    isAssigned: false,
  },

  {
    officerId: "PP-006",
    stationCode: "PP-DEMO-006",
    officerName: "Demo Officer 06",
    isActive: true,
    isAssigned: false,
  },

  {
    officerId: "PP-007",
    stationCode: "PP-DEMO-007",
    officerName: "Demo Officer 07",
    isActive: true,
    isAssigned: false,
  },

  {
    officerId: "PP-008",
    stationCode: "PP-DEMO-008",
    officerName: "Demo Officer 08",
    isActive: true,
    isAssigned: false,
  },

  {
    officerId: "PP-009",
    stationCode: "PP-DEMO-009",
    officerName: "Demo Officer 09",
    isActive: true,
    isAssigned: false,
  },

  {
    officerId: "PP-010",
    stationCode: "PP-DEMO-010",
    officerName: "Demo Officer 10",
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

    // ========================================================
    // 1. RESET OLD DEMO RESPONDER DATA
    // ========================================================

    console.log("");
    console.log("Resetting old demo responder data...");

    const oldOfficerIds = [
      "PP-4471",
      "PP-4472",
      ...officers.map((officer) => officer.officerId),
    ];

    const oldStationCodes = [
      "PP-CENTRAL",
      ...stations.map((station) => station.stationCode),
    ];

    //
    // IMPORTANT:
    // Do NOT delete User documents here.
    //
    // Registered responder accounts may already reference
    // ResponderOfficer documents.
    //
    // Instead, clean the responder authorization records
    // and unlink their associated User records first.
    //

    const oldOfficers = await ResponderOfficer.find({
      officerId: { $in: oldOfficerIds },
    }).select("user");

    const responderUserIds = oldOfficers
      .map((officer) => officer.user)
      .filter(Boolean);

    if (responderUserIds.length > 0) {
      await User.updateMany(
        {
          _id: { $in: responderUserIds },
          role: "responder",
        },
        {
          $set: {
            isOnline: false,
            lastSeenAt: new Date(),
          },
          $unset: {
            officerId: "",
          },
        }
      );

      console.log(
        `Reset ${responderUserIds.length} existing responder account(s).`
      );
    }

    await ResponderOfficer.deleteMany({
      officerId: { $in: oldOfficerIds },
    });

    await PoliceStation.deleteMany({
      stationCode: { $in: oldStationCodes },
    });

    console.log("Old demo responder data removed.");

    // ========================================================
    // 2. CREATE POLICE STATIONS
    // ========================================================

    console.log("");
    console.log("Creating demo police stations...");

    const stationMap = {};

    for (const stationData of stations) {
      const station = await PoliceStation.create(stationData);

      stationMap[station.stationCode] = station;

      console.log(
        `Station ready: ${station.name} (${station.stationCode})`
      );
    }

    // ========================================================
    // 3. CREATE AUTHORIZED OFFICER IDs
    // ========================================================

    console.log("");
    console.log("Creating authorized Officer IDs...");

    for (const officerData of officers) {
      const station = stationMap[officerData.stationCode];

      if (!station) {
        throw new Error(
          `Station ${officerData.stationCode} was not found.`
        );
      }

      const officer = await ResponderOfficer.create({
        officerId: officerData.officerId,
        station: station._id,
        officerName: officerData.officerName,
        isActive: officerData.isActive,
        isAssigned: false,
        user: null,
      });

      console.log(
        `Officer ready: ${officer.officerId} → ${station.stationCode}`
      );
    }

    // ========================================================
    // 4. SUMMARY
    // ========================================================

    console.log("");
    console.log("======================================");
    console.log("Responder data seeded successfully.");
    console.log("======================================");
    console.log("");

    console.log("Authorized Officer IDs:");

    for (const officer of officers) {
      console.log(
        `  ${officer.officerId} → ${officer.stationCode}`
      );
    }

    console.log("");
    console.log(
      "Responder availability is determined by User.isOnline."
    );
    console.log(
      "A responder becomes online after approved login."
    );
    console.log(
      "A responder becomes offline after logout."
    );
    console.log("");
  } catch (error) {
    console.error(
      "Failed to seed responder data:",
      error
    );

    process.exitCode = 1;
  } finally {
    await mongoose.disconnect();
  }
}

seed();