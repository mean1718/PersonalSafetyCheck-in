const express = require("express");

const router = express.Router();

const {
  registerUser,
  loginUser,
  registerDeviceToken,
  removeDeviceToken,
} = require("../controllers/userController");
const protect = require("../middleware/authMiddleware");

// Register
router.post("/register", registerUser);

// Login
router.post("/login", loginUser);

// Push notifications — register this device's FCM token so trust
// requests / safety alerts can reach it even while SafetyU isn't open.
router.post("/device-token", protect, registerDeviceToken);
router.post("/device-token/remove", protect, removeDeviceToken);

// Protected profile
router.get("/profile", protect, (req, res) => {
  res.json({
    message: "Access granted",
    user: {
      id: req.authenticatedUser._id,
      name: req.authenticatedUser.name,
      email: req.authenticatedUser.email,
      phone: req.authenticatedUser.phone,
      role: req.authenticatedUser.role,
      createdAt: req.authenticatedUser.createdAt,
    },
  });
});

module.exports = router;
