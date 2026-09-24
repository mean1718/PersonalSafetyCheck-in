// Google's Directions REST endpoint (maps.googleapis.com/maps/api/directions)
// doesn't allow direct browser fetch/XHR calls (no CORS headers) — that's
// why Google ships a separate JS-only google.maps.DirectionsService class
// for web pages, which sidesteps this by not using a raw CORS-checked
// fetch at all. Our Flutter Web app was calling the REST endpoint directly
// with Dart's http package, which IS a raw browser fetch on web — silently
// blocked. Calling it from here (a Node server, not a browser) has no such
// restriction, so this proxies the request instead.
const getRoute = async (req, res) => {
  const { originLat, originLng, destLat, destLng, mode } = req.query;
  if (!originLat || !originLng || !destLat || !destLng) {
    return res.status(400).json({ message: "originLat, originLng, destLat, and destLng are all required." });
  }
  try {
    const base = mode === "driving"
      ? "https://routing.openstreetmap.de/routed-car/route/v1/driving"
      : "https://routing.openstreetmap.de/routed-foot/route/v1/foot";
    const url = `${base}/${originLng},${originLat};${destLng},${destLat}?overview=full&geometries=polyline`;

    const r = await fetch(url);
    const body = await r.json();
    const route = body.routes?.[0];
    if (body.code !== "Ok" || !route) {
      return res.status(502).json({ message: `No route found (${body.code || "unknown"}).` });
    }
    return res.json({
      encodedPolyline: route.geometry,
      distanceMeters: route.distance,
      durationSeconds: route.duration,
    });
  } catch (error) {
    return res.status(500).json({ message: "Server error", error: error.message });
  }
};

module.exports = { getRoute };