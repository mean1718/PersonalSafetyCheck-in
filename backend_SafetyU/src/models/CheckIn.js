const mongoose = require("mongoose");

const checkInSchema = new mongoose.Schema(
    {
        user: {
            type: mongoose.Schema.Types.ObjectId,
            ref: "User",
            required: true
        },

        trustedContactUser: {
            type: mongoose.Schema.Types.ObjectId,
            ref: "User",
            required: false
        },

        // The accounts selected for this particular session.  Keep the
        // singular field above for existing records, but use this list for
        // all newly-created sessions so every selected contact can be
        // notified and tracked independently.
        trustedContactUsers: [{
            type: mongoose.Schema.Types.ObjectId,
            ref: "User"
        }],

        status: {
            type: String,
            enum: ["active", "completed", "emergency"],
            default: "active"
        },

        message: {
            type: String,
            default: ""
        },

        location: {
            latitude: {
                type: Number
            },
            longitude: {
                type: Number
            }
        },

        startedAt: {
            type: Date,
            default: Date.now
        },

        completedAt: {
            type: Date
        }
    },
    {
        timestamps: true
    }
);

module.exports = mongoose.model("CheckIn", checkInSchema);
