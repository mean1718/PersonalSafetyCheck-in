import 'package:google_maps_flutter/google_maps_flutter.dart';
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
    final points = _decodePolyline(encoded);
    // ignore: avoid_print
    print('[DIRECTIONS] encoded length=${encoded.length}, '
        'decoded ${points.length} points. '
        'First 3: ${points.take(3).toList()} '
        'Last 3: ${points.skip(points.length > 3 ? points.length - 3 : 0).toList()}');
    return RouteResult(
      points: points,
      distanceMeters: (body['distanceMeters'] as num).toDouble(),
      durationSeconds: (body['durationSeconds'] as num).toDouble(),
    );
  }

  /// Decodes Google's polyline encoding format into a list of coordinates.
  /// This is the standard algorithm Google documents at
  /// https://developers.google.com/maps/documentation/utilities/polylinealgorithm
  static List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int shift = 0, result = 0, b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}
