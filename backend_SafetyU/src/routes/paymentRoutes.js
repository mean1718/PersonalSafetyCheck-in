// src/routes/paymentRoutes.js
const express = require("express");
const router = express.Router();

const paymentController = require("../controllers/paymentController");
const authMiddleware = require("../middleware/authMiddleware");

// Fallbacks to prevent server crash and identify the exact missing piece
const getPricing =
  paymentController.getPricing ||
  ((req, res) => res.status(500).json({ error: "getPricing missing" }));
const createKhqrPayment =
  paymentController.createKhqrPayment ||
  ((req, res) => res.status(500).json({ error: "createKhqrPayment missing" }));
const checkKhqrStatus =
  paymentController.checkKhqrStatus ||
  ((req, res) => res.status(500).json({ error: "checkKhqrStatus missing" }));
const protect =
  authMiddleware.protect || authMiddleware || ((req, res, next) => next());

router.get("/pricing", getPricing);
router.post("/khqr", protect, createKhqrPayment);
router.get("/khqr/:md5/status", protect, checkKhqrStatus);

module.exports = router;
