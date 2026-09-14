const Location = require("../models/Location");
const TrustRequest = require("../models/TrustRequest");

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

// GET /api/location/contacts — every trusted contact who (a) is a
// confirmed friend via a real, accepted TrustRequest — the same system
// Friends/chat/check-ins already use — and (b) currently has sharing
// turned on, with their last known point and distance from the
// requester's own last known point.
//
// This used to query the older, separate TrustedContact model (manually
// entered phone-number contacts, backfilled to a user account), which has
// nothing to do with the real accepted-TrustRequest relationships the
// rest of the app is built on. That meant this endpoint could never find
// anyone real — a confirmed friend from Friends/Select Contacts simply
// isn't in that other table at all.
const listContactLocations = async (req, res) => {
  try {
    const relationships = await TrustRequest.find({
      status: "accepted",
      $or: [{ sender: req.user.id }, { receiver: req.user.id }],
    }).populate("sender", "name phone").populate("receiver", "name phone");

    const contacts = relationships
      .map((r) => {
        const other = r.sender._id.toString() === req.user.id.toString()
          ? r.receiver
          : r.sender;
        return other ? { userId: other._id, name: other.name } : null;
      })
      .filter(Boolean);

    const [me, locations] = await Promise.all([
      Location.findOne({ user: req.user.id }),
      Location.find({
        user: { $in: contacts.map((c) => c.userId) },
        sharingEnabled: true,
      }),
    ]);
    const locationByUser = new Map(
      locations.map((l) => [l.user.toString(), l]),
    );

    const result = contacts
      .filter((c) => locationByUser.has(c.userId.toString()))
      .map((c) => {
        const loc = locationByUser.get(c.userId.toString());
        return {
          // No separate "contact record" id exists anymore now that this
          // reads straight from confirmed users — the real user id is
          // used consistently everywhere else in the app (Contact.id),
          // so it's used here too instead of inventing a second id.
          contactId: c.userId,
          userId: c.userId,
          name: c.name,
          relationship: "Trusted Contact",
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