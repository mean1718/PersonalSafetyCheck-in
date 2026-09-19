const express = require("express");

const router = express.Router();

const {
    registerUser,
    loginUser,
    logoutUser,
    approveResponder,
    registerDeviceToken,
    removeDeviceToken,
    verifyEmergencyPin,
    changeEmergencyPin,
    createEmergencyPin,
} = require("../controllers/userController");

const protect = require("../middleware/authMiddleware");

// =========================================================
// REGISTER
// =========================================================

router.post(
    "/register",
    registerUser
);

// =========================================================
// PUSH NOTIFICATIONS — DEVICE TOKENS
// =========================================================
//
// Register this device's FCM token so trust requests / safety alerts
// can reach it even while SafetyU isn't open. Unregister on logout so
// a shared/borrowed device stops getting this account's pushes.
// =========================================================

router.post("/device-token", protect, registerDeviceToken);
router.post("/device-token/remove", protect, removeDeviceToken);

// =========================================================
// LOGIN
// =========================================================

router.post(
    "/login",
    loginUser
);
router.post(
    "/logout",
    protect,
    logoutUser
);
router.post("/approve-responder", approveResponder);

// =========================================================
// VERIFY EMERGENCY PIN
// =========================================================
//
// Protected because the user must already be signed in.
// =========================================================

router.post(
    "/verify-emergency-pin",
    protect,
    verifyEmergencyPin
);

// =========================================================
// CHANGE EMERGENCY PIN
// =========================================================
//
// Protected because only the signed-in user can change
// their own Emergency PIN.
// =========================================================

router.put(
    "/change-emergency-pin",
    protect,
    changeEmergencyPin
);

// =========================================================
// CREATE EMERGENCY PIN
// =========================================================
//
// Used only by existing users who do not have a PIN yet.
//
// Protected because the signed-in user is creating
// a PIN for their own account.
// =========================================================

router.post(
    "/create-emergency-pin",
    protect,
    createEmergencyPin
);

// =========================================================
// PROFILE
// =========================================================

router.get(
    "/profile",
    protect,
    (req, res) => {
        res.json({
            message: "Access granted",
            user: {
                id: req.authenticatedUser._id,
                name: req.authenticatedUser.name,
                email: req.authenticatedUser.email,
                phone: req.authenticatedUser.phone,
                role: req.authenticatedUser.role,
                officerId:
                    req.authenticatedUser.officerId ||
                    null,
                responderStatus:
                    req.authenticatedUser
                        .responderStatus ||
                    null,
                createdAt:
                    req.authenticatedUser.createdAt,
            },
        });
    }
);

module.exports = router;