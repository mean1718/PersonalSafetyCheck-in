const TrustedContact = require("../models/TrustedContact");

// Add trusted contact
const addTrustedContact = async (req, res) => {
  try {
    const { name, phone, relationship, priority } = req.body;

    if (!name || !phone || !relationship || !priority) {
      return res.status(400).json({
        message: "All fields are required",
      });
    }

    // Check if user already has this priority
    const existingContact = await TrustedContact.findOne({
      user: req.user.id,
      priority,
      isActive: true,
    });

    if (existingContact) {
      return res.status(400).json({
        message: `You already have a ${priority} trusted contact`,
      });
    }

    const contact = await TrustedContact.create({
      user: req.user.id,
      name,
      phone,
      relationship,
      priority,
    });

    res.status(201).json({
      message: "Trusted contact added successfully",
      contact,
    });
  } catch (error) {
    res.status(500).json({
      message: "Server error",
      error: error.message,
    });
  }
};

// Get user's trusted contacts
const getTrustedContacts = async (req, res) => {
  try {
    const contacts = await TrustedContact.find({
      user: req.user.id,
      isActive: true,
    }).sort({ priority: 1 });

    res.status(200).json({
      contacts,
    });
  } catch (error) {
    res.status(500).json({
      message: "Server error",
      error: error.message,
    });
  }
};

// Delete trusted contact
const deleteTrustedContact = async (req, res) => {
  try {
    const contact = await TrustedContact.findOne({
      _id: req.params.id,
      user: req.user.id,
    });

    if (!contact) {
      return res.status(404).json({
        message: "Trusted contact not found",
      });
    }

    contact.isActive = false;
    await contact.save();

    res.status(200).json({
      message: "Trusted contact deleted successfully",
    });
  } catch (error) {
    res.status(500).json({
      message: "Server error",
      error: error.message,
    });
  }
};

module.exports = {
  addTrustedContact,
  getTrustedContacts,
  deleteTrustedContact,
};