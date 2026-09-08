const CheckIn = require("../models/CheckIn");

// Start a safety check-in
const startCheckIn = async (req, res) => {
    try {
        const { message, latitude, longitude } = req.body;

        const checkIn = await CheckIn.create({
            user: req.user.id,
            message: message || "",
            location: {
                latitude: latitude || null,
                longitude: longitude || null
            },
            status: "active"
        });

        res.status(201).json({
            message: "Safety check-in started",
            checkIn
        });

    } catch (error) {
        res.status(500).json({
            message: "Server error",
            error: error.message
        });
    }
};


// Complete a safety check-in
const completeCheckIn = async (req, res) => {
    try {
        const checkIn = await CheckIn.findOne({
            _id: req.params.id,
            user: req.user.id
        });

        if (!checkIn) {
            return res.status(404).json({
                message: "Check-in not found"
            });
        }

        checkIn.status = "completed";
        checkIn.completedAt = new Date();

        await checkIn.save();

        res.status(200).json({
            message: "Safety check-in completed",
            checkIn
        });

    } catch (error) {
        res.status(500).json({
            message: "Server error",
            error: error.message
        });
    }
};


// Get user's check-ins
const getMyCheckIns = async (req, res) => {
    try {
        const checkIns = await CheckIn.find({
            user: req.user.id
        }).sort({ createdAt: -1 });

        res.status(200).json({
            checkIns
        });

    } catch (error) {
        res.status(500).json({
            message: "Server error",
            error: error.message
        });
    }
};


module.exports = {
    startCheckIn,
    completeCheckIn,
    getMyCheckIns
};