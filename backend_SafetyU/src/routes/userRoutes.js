const express = require("express");

const router = express.Router();

const { registerUser, loginUser } = require("../controllers/userController");
const protect = require("../middleware/authMiddleware");

// Register
router.post("/register", registerUser);

// Login
router.post("/login", loginUser);

// Protected profile
router.get("/profile", protect, (req, res) => {
    res.json({
        message: "Access granted",
        user: req.user
    });
});

module.exports = router;