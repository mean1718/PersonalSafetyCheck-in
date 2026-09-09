const express = require("express");
const dotenv = require("dotenv");
const path = require("path");
const cors = require("cors");

// Load .env from src/config/.env
dotenv.config({
    path: path.join(__dirname, "config", ".env")
});

// Check if MongoDB URI is loaded
console.log("MONGODB_URI loaded:", !!process.env.MONGODB_URI);

const connectDB = require("./config/db");
const userRoutes = require("./routes/userRoutes");
const checkInRoutes = require("./routes/checkInRoutes");
const trustedContactRoutes = require("./routes/trustedContactRoutes");
const emergencyRoutes = require("./routes/emergencyRoutes");

const app = express();

// Middleware
app.use(cors());
app.use(express.json());

// Connect MongoDB
connectDB();

// Routes
app.use("/api/users", userRoutes);
app.use("/api/checkins", checkInRoutes);
app.use("/api/trusted-contacts", trustedContactRoutes);
app.use("/api/emergency", emergencyRoutes);

// Test route
app.get("/", (req, res) => {
    res.json({
        message: "Personal Safety Check-In API is running"
    });
});

// Server
const PORT = process.env.PORT || 5000;

app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
});