const User = require("../models/User");
const Location = require("../models/Location");
const TrustedContact = require("../models/TrustedContact");

const toNumber = (value) => {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
};

// Great-circle distance in meters between two lat/lng points.
const distanceMeters = (lat1, lon1, lat2, lon2) => {
  const R = 6371000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
};

// POST /api/location — called every few seconds while the person has
// "Share my location" turned on in the app. Upserts their live pointer
// and (re)enables sharing, since posting a ping implies sharing is on.
const updateLocation = async (req, res) => {
  const latitude = toNumber(req.body.latitude);
  const longitude = toNumber(req.body.longitude);
  const accuracy = toNumber(req.body.accuracy);
  const heading = toNumber(req.body.heading);

  if (latitude === null || longitude === null) {
    return res
      .status(400)
      .json({ message: "latitude and longitude are required." });
  }

  try {
    const location = await Location.findOneAndUpdate(
      { user: req.user.id },
      {
        $set: {
          latitude,
          longitude,
          ...(accuracy !== null ? { accuracy } : {}),
          ...(heading !== null ? { heading } : {}),
          sharingEnabled: true,
        },
      },
      { upsert: true, new: true },
    );
    return res.json({ message: "Location updated.", location });
  } catch (error) {
    return res.status(500).json({ message: "Server error" });
  }
};

// POST /api/location/stop — turns sharing off. The pointer stays in the
// DB (so it doesn't error if a stray ping races in) but is excluded from
// every contacts'-locations response below.
const stopSharing = async (req, res) => {
  try {
    await Location.findOneAndUpdate(
      { user: req.user.id },
      { $set: { sharingEnabled: false } },
    );
    return res.json({ message: "Location sharing stopped." });
  } catch (error) {
    return res.status(500).json({ message: "Server error" });
  }
};

// GET /api/location/contacts — every trusted contact who (a) is a real
// SafetyU user, and (b) currently has sharing turned on, with their last
// known point and distance from the requester's own last known point.
const listContactLocations = async (req, res) => {
  try {
    const [me, contacts] = await Promise.all([
      Location.findOne({ user: req.user.id }),
      TrustedContact.find({ user: req.user.id, isActive: true }),
    ]);

    // Backfill contactUser for older records that predate that field.
    const missingLink = contacts.filter((c) => !c.contactUser && c.phone);
    if (missingLink.length) {
      const users = await User.find({
        phone: { $in: missingLink.map((c) => c.phone) },
      }).select("_id phone");
      const byPhone = new Map(users.map((u) => [u.phone, u._id]));
      await Promise.all(
        missingLink
          .filter((c) => byPhone.has(c.phone))
          .map((c) => {
            c.contactUser = byPhone.get(c.phone);
            return c.save();
          }),
      );
    }

    const linkedIds = contacts.map((c) => c.contactUser).filter(Boolean);
    const locations = await Location.find({
      user: { $in: linkedIds },
      sharingEnabled: true,
    });
    const locationByUser = new Map(
      locations.map((l) => [l.user.toString(), l]),
    );

    const result = contacts
      .filter(
        (c) => c.contactUser && locationByUser.has(c.contactUser.toString()),
      )
      .map((c) => {
        const loc = locationByUser.get(c.contactUser.toString());
        return {
          contactId: c._id,
          userId: c.contactUser,
          name: c.name,
          relationship: c.relationship,
          latitude: loc.latitude,
          longitude: loc.longitude,
          accuracy: loc.accuracy ?? null,
          updatedAt: loc.updatedAt,
          distanceMeters:
            me != null
              ? Math.round(
                  distanceMeters(
                    me.latitude,
                    me.longitude,
                    loc.latitude,
                    loc.longitude,
                  ),
                )
              : null,
        };
      });

    return res.json({ contacts: result });
  } catch (error) {
    return res.status(500).json({ message: "Server error" });
  }
};

module.exports = { updateLocation, stopSharing, listContactLocations };
