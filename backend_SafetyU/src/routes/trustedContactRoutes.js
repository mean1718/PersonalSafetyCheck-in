const express = require("express");

const router = express.Router();

const {
  addTrustedContact,
  getTrustedContacts,
  getTrustedContact,
  updateTrustedContact,
  deleteTrustedContact,
} = require("../controllers/trustedContactController");

const protect = require("../middleware/authMiddleware");

// Add trusted contact
router.use(protect);
router.route("/").get(getTrustedContacts).post(addTrustedContact);
router.route("/:id").get(getTrustedContact).put(updateTrustedContact).patch(updateTrustedContact).delete(deleteTrustedContact);

module.exports = router;
