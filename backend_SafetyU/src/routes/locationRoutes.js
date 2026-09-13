const express = require("express");
const {
  updateLocation,
  stopSharing,
  listContactLocations,
} = require("../controllers/locationController");
const protect = require("../middleware/authMiddleware");
const router = express.Router();
router.use(protect);
router.post("/", updateLocation);
router.post("/stop", stopSharing);
router.get("/contacts", listContactLocations);
module.exports = router;
