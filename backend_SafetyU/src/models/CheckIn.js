const mongoose = require("mongoose");

const checkInSchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
    },

    trustedContactUser: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: false,
    },

    // The accounts selected for this particular session.  Keep the
    // singular field above for existing records, but use this list for
    // all newly-created sessions so every selected contact can be
    // notified and tracked independently.
    trustedContactUsers: [
      {
        type: mongoose.Schema.Types.ObjectId,
        ref: "User",
      },
    ],

    status: {
      type: String,
      enum: ["active", "completed", "emergency"],
      default: "active",
    },

    message: {
      type: String,
      default: "",
    },

    location: {
      latitude: {
        type: Number,
      },
      longitude: {
        type: Number,
      },
    },

    // Where this session's owner said they were headed when they
    // started it (chosen on Session Setup). Separate from `location`
    // above, which is their LIVE, moving position -- without this,
    // a trusted contact's Alert Detail screen had no way to show both
    // "where they are right now" and "where they were headed", the
    // way the owner's own session screen already does.
    destination: {
      latitude: {
        type: Number,
      },
      longitude: {
        type: Number,
      },
    },

    // Human-readable name of the destination ("Central Market").
    // Before this only raw coordinates were stored, so a trusted
    // contact's screen could not say WHERE the person was going --
    // it showed the alert message text in the destination field.
    destinationName: {
      type: String,
      default: "",
    },

    // When the person promised to be safe by. The phone's own timer
    // used to be the only thing that knew this, so if the phone died,
    // lost signal or the app was suspended nobody was ever alerted.
    // The server now watches this too (see services/deadlineWatcher).
    expectedEndAt: {
      type: Date,
    },

    // Why the person asked for more time ("Stuck in traffic"), and
    // when. Shown to trusted contacts so a late person is explained,
    // not just "overdue".
    delayReason: {
      type: String,
      default: "",
    },
    delayRequestedAt: {
      type: Date,
    },

    // Set the first time contacts were alerted about a missed
    // deadline / Need Help for the current deadline. Stops the server
    // from alerting again on top of the phone's own escalation.
    deadlineAlertedAt: {
      type: Date,
      default: null,
    },

    // First time the live location came within arrival range of the
    // destination. Lets contacts see "arrived" instead of a dot that
    // just stops moving.
    arrivedAt: {
      type: Date,
    },

    // Last time the phone actually reported a position. `updatedAt`
    // changes on any save, so it can't tell contacts how fresh the
    // location is.
    locationUpdatedAt: {
      type: Date,
    },

    // Set once a trusted contact taps "Mark [name] as Safe" on their
    // side. This is how the OWNER's own Active Session screen learns
    // about it and can show a "Trust confirm you safe!" popup --
    // before this there was no backend record of that action at all,
    // it only ever updated the contact's own local notification list.
    confirmedSafeBy: {
      userId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "User",
      },
      name: {
        type: String,
      },
      at: {
        type: Date,
      },
    },

    startedAt: {
      type: Date,
      default: Date.now,
    },

    completedAt: {
      type: Date,
    },
  },
  {
    timestamps: true,
  },
);

module.exports = mongoose.model("CheckIn", checkInSchema);
