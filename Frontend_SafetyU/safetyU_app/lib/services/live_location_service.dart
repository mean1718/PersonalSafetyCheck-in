import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'api_client.dart';

/// One live location point for a trusted contact, as returned by
/// GET /api/location/contacts.
class ContactLocation {
  final String contactId;
  final String userId;
  final String name;
  final String relationship;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime updatedAt;
  final int? distanceMeters;

  const ContactLocation({
    required this.contactId,
    required this.userId,
    required this.name,
    required this.relationship,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.updatedAt,
    this.distanceMeters,
  });

  factory ContactLocation.fromJson(Map<String, dynamic> json) =>
      ContactLocation(
        contactId: json['contactId']?.toString() ?? '',
        userId: json['userId']?.toString() ?? '',
        name: json['name'] as String? ?? '',
        relationship: json['relationship'] as String? ?? '',
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracy: (json['accuracy'] as num?)?.toDouble(),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
            DateTime.now(),
        distanceMeters: (json['distanceMeters'] as num?)?.toInt(),
      );

  /// Human-friendly "how far away", e.g. "850 m" or "3.2 km".
  String get distanceLabel {
    final d = distanceMeters;
    if (d == null) return '';
    if (d < 1000) return '$d m away';
    return '${(d / 1000).toStringAsFixed(1)} km away';
  }

  /// Human-friendly "how stale", e.g. "just now", "4 min ago".
  String get freshnessLabel {
    final age = DateTime.now().difference(updatedAt);
    if (age.inSeconds < 30) return 'Live • just now';
    if (age.inMinutes < 1) return 'Live • ${age.inSeconds}s ago';
    if (age.inMinutes < 60) return '${age.inMinutes} min ago';
    return '${age.inHours} hr ago';
  }
}

/// Handles turning "Share my location" on/off and pushing periodic GPS
/// pings to the backend while it's on. A single app-wide instance, same
/// pattern as AppSession.
class LiveLocationService {
  LiveLocationService._internal();
  static final LiveLocationService instance = LiveLocationService._internal();

  Timer? _pingTimer;
  bool _sharing = false;
  bool get isSharing => _sharing;

  /// Requests permission (prompting the system dialog if needed) and, if
  /// granted, starts sending this device's position to the backend every
  /// few seconds. Returns false if permission was denied.
  Future<bool> startSharing({
    Duration interval = const Duration(seconds: 8),
  }) async {
    if (!await _ensurePermission()) return false;

    _sharing = true;
    await _pingOnce();
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(interval, (_) => _pingOnce());
    return true;
  }

  Future<void> stopSharing() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    _sharing = false;
    try {
      await ApiClient.post('/location/stop', {});
    } catch (_) {
      // Best-effort — if this fails the next ping simply won't happen
      // since the timer is already cancelled.
    }
  }

  Future<void> _pingOnce() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await ApiClient.post('/location', {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'heading': position.heading,
      });
    } catch (_) {
      // Transient GPS/network hiccups shouldn't kill the whole sharing
      // session — just skip this tick and try again on the next timer fire.
    }
  }

  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<Position> currentPosition() => Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

  Future<List<ContactLocation>> fetchContactLocations() async {
    final data = await ApiClient.get('/location/contacts');
    final list = data['contacts'] as List<dynamic>? ?? [];
    return list
        .map((e) => ContactLocation.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
