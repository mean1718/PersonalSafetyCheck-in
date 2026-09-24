import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart';
import 'package:http/http.dart' as http;
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

/// Draws the real road path between two points.
///
/// 1. Tries our own backend (/directions) first.
/// 2. If that fails for any reason (backend not updated, Google key denied,
///    server asleep), it falls back to the free OpenStreetMap routing
///    service directly, so the line still follows real roads.
class DirectionsService {
  static Future<RouteResult> route({
    required LatLng from,
    required LatLng to,
    bool walking = true,
  }) async {
    try {
      final body = await ApiClient.get(
        '/directions'
        '?originLat=${from.latitude}&originLng=${from.longitude}'
        '&destLat=${to.latitude}&destLng=${to.longitude}'
        '&mode=${walking ? 'walking' : 'driving'}',
      );
      return _fromBody(
        body['encodedPolyline'] as String,
        (body['distanceMeters'] as num).toDouble(),
        (body['durationSeconds'] as num).toDouble(),
      );
    } catch (_) {
      return _routeDirect(from: from, to: to, walking: walking);
    }
  }

  static Future<RouteResult> _routeDirect({
    required LatLng from,
    required LatLng to,
    required bool walking,
  }) async {
    final base = walking
        ? 'https://routing.openstreetmap.de/routed-foot/route/v1/foot'
        : 'https://routing.openstreetmap.de/routed-car/route/v1/driving';
    final url = '$base/${from.longitude},${from.latitude};'
        '${to.longitude},${to.latitude}?overview=full&geometries=polyline';
    final res =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final routes = data['routes'] as List?;
    if (data['code'] != 'Ok' || routes == null || routes.isEmpty) {
      throw Exception('No route found (${data['code']}).');
    }
    final r = routes.first as Map<String, dynamic>;
    return _fromBody(
      r['geometry'] as String,
      (r['distance'] as num).toDouble(),
      (r['duration'] as num).toDouble(),
    );
  }

  static RouteResult _fromBody(String encoded, double dist, double dur) {
    final decoded = decodePolyline(encoded);
    final points = decoded
        .map((pair) => LatLng(pair[0].toDouble(), pair[1].toDouble()))
        .toList();
    return RouteResult(
      points: points,
      distanceMeters: dist,
      durationSeconds: dur,
    );
  }
}
