const express = require("express");
const { getRoute } = require("../controllers/directionsController");
const protect = require("../middleware/authMiddleware");
const router = express.Router();
router.use(protect);
router.get("/", getRoute);
module.exports = router;