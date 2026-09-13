import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

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

/// Draws the actual walkable/drivable road path between two points using
/// OSRM's public routing server (https://project-osrm.org — free, no API
/// key, fine for development/light use). For production traffic, swap the
/// base URL for a self-hosted OSRM instance or a paid provider (Google
/// Directions, Mapbox) — the parsing below only needs the base URL to change.
class DirectionsService {
  static const _baseUrl = 'https://router.project-osrm.org/route/v1';

  static Future<RouteResult> route({
    required LatLng from,
    required LatLng to,
    bool walking = true,
  }) async {
    final profile = walking ? 'foot' : 'driving';
    final uri = Uri.parse(
      '$_baseUrl/$profile/${from.longitude},${from.latitude};'
      '${to.longitude},${to.latitude}'
      '?overview=full&geometries=geojson',
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception('Could not fetch a route (${res.statusCode}).');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final routes = body['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) {
      throw Exception('No route found between these two points.');
    }
    final route = routes.first as Map<String, dynamic>;
    final coords = (route['geometry']['coordinates'] as List<dynamic>)
        .map((c) => LatLng((c as List)[1] as double, c[0] as double))
        .toList();
    return RouteResult(
      points: coords,
      distanceMeters: (route['distance'] as num).toDouble(),
      durationSeconds: (route['duration'] as num).toDouble(),
    );
  }
}
