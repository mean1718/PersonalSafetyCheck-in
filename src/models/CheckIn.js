const mongoose = require("mongoose");

const checkInSchema = new mongoose.Schema(
    {
        user: {
            type: mongoose.Schema.Types.ObjectId,
            ref: "User",
            required: true
        },

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