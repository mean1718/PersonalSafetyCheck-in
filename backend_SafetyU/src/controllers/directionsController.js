// Google's Directions REST endpoint (maps.googleapis.com/maps/api/directions)
// doesn't allow direct browser fetch/XHR calls (no CORS headers) — that's
// why Google ships a separate JS-only google.maps.DirectionsService class
// for web pages, which sidesteps this by not using a raw CORS-checked
// fetch at all. Our Flutter Web app was calling the REST endpoint directly
// with Dart's http package, which IS a raw browser fetch on web — silently
// blocked. Calling it from here (a Node server, not a browser) has no such
// restriction, so this proxies the request instead.
const GOOGLE_DIRECTIONS_URL = "https://maps.googleapis.com/maps/api/directions/json";

const getRoute = async (req, res) => {
  const { originLat, originLng, destLat, destLng, mode } = req.query;
  if (!originLat || !originLng || !destLat || !destLng) {
    return res.status(400).json({
      message: "originLat, originLng, destLat, and destLng are all required.",
    });
  }
  const apiKey = process.env.GOOGLE_MAPS_API_KEY;
  if (!apiKey) {
    return res.status(500).json({
      message: "GOOGLE_MAPS_API_KEY is not set on the server.",
    });
  }
  try {
    const url = new URL(GOOGLE_DIRECTIONS_URL);
    url.searchParams.set("origin", `${originLat},${originLng}`);
    url.searchParams.set("destination", `${destLat},${destLng}`);
    url.searchParams.set("mode", mode === "driving" ? "driving" : "walking");
    url.searchParams.set("key", apiKey);

    const googleRes = await fetch(url.toString());
    const body = await googleRes.json();

    if (body.status !== "OK") {
      return res.status(502).json({
        message: `No route found (${body.status || "unknown error"}).`,
      });
    }

    const route = body.routes?.[0];
    const leg = route?.legs?.[0];
    if (!route || !leg) {
      return res.status(502).json({ message: "No route found." });
    }

    return res.json({
      encodedPolyline: route.overview_polyline.points,
      distanceMeters: leg.distance.value,
      durationSeconds: leg.duration.value,
    });
  } catch (error) {
    return res.status(500).json({ message: "Server error", error: error.message });
  }
};

module.exports = { getRoute };