const express = require("express");

const router = express.Router();

const {
  addTrustedContact,
  getTrustedContacts,
  deleteTrustedContact,
} = require("../controllers/trustedContactController");

const protect = require("../middleware/authMiddleware");

// Add trusted contact
router.post("/", protect, addTrustedContact);

// Get my trusted contacts
router.get("/", protect, getTrustedContacts);

// Delete trusted contact
router.delete("/:id", protect, deleteTrustedContact);

module.exports = router;