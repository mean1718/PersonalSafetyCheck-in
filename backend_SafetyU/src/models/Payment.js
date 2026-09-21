const mongoose = require("mongoose");

const paymentSchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    // What this payment is for — drives what the app does when it's paid.
    purpose: {
      type: String,
      enum: ["pro_subscription", "pay_per_contact"],
      required: true,
    },
    extraContacts: { type: Number, default: 0 }, // only used for pay_per_contact
    // Split of extraContacts by which limit it's meant to raise — needed
    // so a confirmed payment credits the right counter on the User.
    extraMainSlots: { type: Number, default: 0 },
    extraOtherSlots: { type: Number, default: 0 },
    amount: { type: Number, required: true },
    currency: { type: String, enum: ["USD", "KHR"], required: true },
    // The currency/amount actually printed on the KHQR (the fields above are
    // always the internal USD ledger amount). These were being set by
    // paymentController but were missing from this schema, so Mongoose
    // silently dropped them: reused QRs came back with the wrong currency
    // and the amount could never be verified against Bakong.
    qrCurrency: { type: String, enum: ["USD", "KHR"], default: "USD" },
    qrAmount: { type: Number },
    qrString: { type: String, required: true },
    // NOT unique: Bakong's KHQR md5 for an individual dynamic QR is
    // computed from account + amount + currency + merchant fields, and in
    // practice does NOT vary with billNumber the way the EMVCo spec
    // suggests it should — so two separate purchases of the same item
    // (e.g. two $2.99 Pro subscriptions, even by different users) can
    // legitimately produce the same md5. Enforcing uniqueness on it here
    // caused every repeat purchase to 500 out with a duplicate-key error.
    // Status lookups below always scope by { md5, user }, so this is safe.
    md5: { type: String, required: true, index: true },
    status: {
      type: String,
      enum: ["pending", "paid", "expired"],
      default: "pending",
      index: true,
    },
    expiresAt: { type: Date, required: true },
    paidAt: { type: Date },
    // Set only once the purchase has actually been applied to the User
    // (Pro activated / slots granted). Lets a half-finished confirmation be
    // safely retried without ever crediting twice.
    credited: { type: Boolean, default: false },
    // Bakong's own transaction hash, kept as proof of what confirmed this.
    bakongHash: { type: String },
  },
  { timestamps: true },
);

module.exports = mongoose.model("Payment", paymentSchema);
