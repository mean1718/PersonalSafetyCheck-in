// Pay-per-contact slots are a 24-hour rental (see paymentController and
// User.extraSlotsExpireAt), not a permanent balance — so the raw
// purchasedExtraMainSlots/purchasedExtraOtherSlots fields on User are only
// meaningful while extraSlotsExpireAt is still in the future. Every place
// that reads those fields (trustedContactController's limitsFor,
// userController's profile response, paymentController itself) must go
// through this instead of reading them directly, or an expired purchase
// would keep silently granting slots forever.
function activeExtraSlots(user) {
  const stillActive =
    !!user?.extraSlotsExpireAt &&
    new Date(user.extraSlotsExpireAt) > new Date();
  return {
    main: stillActive ? user.purchasedExtraMainSlots || 0 : 0,
    other: stillActive ? user.purchasedExtraOtherSlots || 0 : 0,
    expiresAt: stillActive ? user.extraSlotsExpireAt : null,
  };
}

module.exports = { activeExtraSlots };
