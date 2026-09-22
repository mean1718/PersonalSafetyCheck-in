const mongoose = require("mongoose");

const userSchema = new mongoose.Schema(
  {
    name: {
      type: String,
      required: true,
      trim: true,
      minlength: 2,
    },

    email: {
      type: String,
      required: true,
      unique: true,
      trim: true,
      lowercase: true,
    },

    password: {
      type: String,
      required: true,
    },

    phone: {
      type: String,
      required: true,
      unique: true,
      // Allows pre-existing accounts created before phone became required;
      // every newly registered account still has a unique phone number.
      sparse: true,
      trim: true,
    },

    role: {
      type: String,
      enum: ["user", "responder"],
      default: "user",
    },

    // ---- Push notifications ----
    // Firebase Cloud Messaging tokens for every device this account is
    // currently signed into. An array (not a single field) because the
    // same person can be logged in on more than one device at once —
    // every registered token gets the push. Registered by Flutter via
    // POST /api/users/device-token after login and on app start; pruned
    // automatically by pushService when Firebase reports a token is dead.
    fcmTokens: { type: [String], default: [] },

    // ---- Responder accounts ----
    // No `sparse`/`unique` here — that combination still indexes a
    // document once officerId is explicitly set to null (sparse only
    // skips a field that's completely ABSENT, not one that's present
    // with value null), and only ONE null is allowed under a unique
    // index. Every normal-user registration was writing officerId: null
    // explicitly (see userController.js), so the very first normal user
    // ever registered claimed that one allowed null slot — every normal
    // user after that hit E11000 "duplicate key ... officerId: null" on
    // registration. The real uniqueness rule (a partial index, below)
    // only looks at documents where officerId is an actual string, so
    // normal users are invisible to it no matter how many there are.
    officerId: {
      type: String,
      trim: true,
      uppercase: true,
    },

    responderStatus: {
      type: String,
      enum: ["pending", "approved", "rejected"],
      default: "pending",
    },

    // ---- Responder online status ----
isOnline: {
  type: Boolean,
  default: false,
},

lastSeenAt: {
  type: Date,
  default: null,
},

    // ---- Emergency Assistant PIN (user accounts only) ----
    emergencyPin: {
      type: String,
      default: null,
    },

    // ---- Plan / paywall (credited by paymentController on confirmed Bakong payments) ----
    isPro: { type: Boolean, default: false },
    proExpiresAt: { type: Date },
    purchasedExtraMainSlots: { type: Number, default: 0 },
    purchasedExtraOtherSlots: { type: Number, default: 0 },
    // Pay-per-contact slots are a 24-hour rental, not a permanent add-on —
    // mirrors proExpiresAt's pattern exactly. Any reader of
    // purchasedExtra*Slots must check this first; see
    // paymentController.getActiveExtraSlots.
    extraSlotsExpireAt: { type: Date },
  },
  { timestamps: true },
);

// Real fix for the officerId uniqueness rule: only documents where
// officerId is an actual string are considered for uniqueness at all.
// Unlike `unique + sparse` on the field itself, this simply never looks
// at normal-user accounts (officerId null/absent), so there's no shared
// "one null slot" for them to collide over, no matter how many there are.
userSchema.index(
  { officerId: 1 },
  {
    unique: true,
    partialFilterExpression: { officerId: { $type: "string" } },
  },
);

module.exports = mongoose.model("User", userSchema);