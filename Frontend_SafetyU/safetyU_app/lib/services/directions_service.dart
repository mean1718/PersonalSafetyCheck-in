import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart';
import 'api_client.dart';

class RouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  const RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  String get distanceLabel => distanceMeters < 1000
      ? '${distanceMeters.round()} m'
      : '${(distanceMeters / 1000).toStringAsFixed(1)} km';

  String get durationLabel {
    final minutes = (durationSeconds / 60).round();
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60} hr ${minutes % 60} min';
  }
}

/// Draws the actual walkable/drivable road path between two points — the
/// same routing data the Google Maps app itself uses, so the line on our
/// map follows real streets and turns instead of cutting a straight
/// diagonal through buildings.
///
/// This goes through OUR OWN backend (see directionsController.js) rather
/// than calling Google's Directions REST endpoint directly from here.
/// That endpoint has no CORS headers, so a direct call works fine on
/// Android/iOS (no browser involved) but is silently blocked by the
/// browser on Flutter Web — which was exactly what was happening before.
/// Google's own fix for web pages is a separate JS-only class
/// (google.maps.DirectionsService) that isn't a real CORS-checked fetch;
/// since we don't have access to that from Dart, proxying through our
/// backend (a server calling another server — no CORS involved at all)
/// is the actual fix, and also stops the API key from ever appearing in
/// the browser's network tab.
class DirectionsService {
  static Future<RouteResult> route({
    required LatLng from,
    required LatLng to,
    bool walking = true,
  }) async {
    final body = await ApiClient.get(
      '/directions'
      '?originLat=${from.latitude}&originLng=${from.longitude}'
      '&destLat=${to.latitude}&destLng=${to.longitude}'
      '&mode=${walking ? 'walking' : 'driving'}',
    );
    final encoded = body['encodedPolyline'] as String;
    // This used to be a hand-written decoder using the same algorithm —
    // but it used the `~` (bitwise complement) operator to handle negative
    // deltas, which has a documented Dart-web (Chrome) compatibility bug:
    // native Android/iOS builds compute it correctly (real 64-bit ints),
    // but compiling to JavaScript for web can silently produce wrong
    // values for that exact operator. That's almost certainly why routes
    // decoded fine in theory (right point *count*) but rendered as a
    // straight line on web specifically — some points' coordinates were
    // simply wrong. Using the official, actively maintained package here
    // instead, whose changelog explicitly lists fixing this same bug.
    final decoded = decodePolyline(encoded);
    final points = decoded
        .map((pair) => LatLng(pair[0].toDouble(), pair[1].toDouble()))
        .toList();
    return RouteResult(
      points: points,
      distanceMeters: (body['distanceMeters'] as num).toDouble(),
      durationSeconds: (body['durationSeconds'] as num).toDouble(),
    );
  }
}
