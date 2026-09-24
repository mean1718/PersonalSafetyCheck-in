const express = require("express");
const dotenv = require("dotenv");
const path = require("path");
const cors = require("cors");

// Load .env from src/config/.env
dotenv.config({
  path: path.join(__dirname, "config", ".env"),
});

// Check if MongoDB URI is loaded
console.log("MONGODB_URI loaded:", !!process.env.MONGODB_URI);

const connectDB = require("./config/db");
const userRoutes = require("./routes/userRoutes");
const checkInRoutes = require("./routes/checkInRoutes");
const trustedContactRoutes = require("./routes/trustedContactRoutes");
const trustRequestRoutes = require("./routes/trustRequestRoutes");
const emergencyRoutes = require("./routes/emergencyRoutes");
const notificationRoutes = require("./routes/notificationRoutes");
const locationRoutes = require("./routes/locationRoutes");
const chatRoutes = require("./routes/ChatRoutes");
const directionsRoutes = require("./routes/directionsRoutes");
const paymentRoutes = require("./routes/paymentRoutes");
const { startDeadlineWatcher } = require("./services/deadlineWatcher");

const app = express();

// Middleware
app.use(cors());
app.use(express.json());

// Connect MongoDB
// The missed-deadline watcher only starts once the database is connected.
connectDB().then(startDeadlineWatcher);

// Routes
app.use("/api/users", userRoutes);
app.use("/api/checkins", checkInRoutes);
app.use("/api/trusted-contacts", trustedContactRoutes);
app.use("/api/trust-requests", trustRequestRoutes);
app.use("/api/emergency", emergencyRoutes);
app.use("/api/notifications", notificationRoutes);
app.use("/api/location", locationRoutes);
app.use("/api/chat", chatRoutes);
app.use("/api/directions", directionsRoutes);
app.use("/api/payments", paymentRoutes);

// Test route
app.get("/", (req, res) => {
  res.json({
    message: "Personal Safety Check-In API is running",
  });
});

// Health check (handy for Render + for testing the app's base URL)
app.get("/api/health", (req, res) => {
  res.json({ status: "ok", time: new Date().toISOString() });
});

// Unknown route -> JSON 404 that says exactly which route was not found.
// Without this, Express sends an HTML "Cannot POST ..." page and the app can
// only show a bare "Server error (404)".
app.use((req, res) => {
  res.status(404).json({
    message: `Route not found: ${req.method} ${req.originalUrl}`,
  });
});

// Last-resort error handler so unexpected errors also come back as JSON.
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  console.error("Unhandled error:", err);
  res.status(err.status || 500).json({
    message: err.status && err.status < 500 ? err.message : "Server error",
  });
});

// Server
const PORT = process.env.PORT || 5000;

app.listen(PORT, "0.0.0.0", () => {
  console.log(`Server running on port ${PORT}`);
});
