import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Wraps real geolocation with a fallback that only ever activates in
/// debug builds (kDebugMode) — this exists purely so testing doesn't
/// require manually re-setting a fake GPS location in Chrome DevTools'
/// Sensors panel every single time (that override doesn't persist across
/// page refreshes, which made every test run start from "no location at
/// all" unless it was freshly re-set).
///
/// In a real release build, kDebugMode is always false, so this behaves
/// exactly like calling Geolocator directly — no fallback, no behavior
/// change, nothing to worry about shipping.
class DebugLocation {
  DebugLocation._();

  /// Central Phnom Penh — an arbitrary but real, sensible default so a
  /// route/distance calculation still makes sense during testing instead
  /// of e.g. (0,0), which would produce a route halfway across the world.
  static const LatLng fallback = LatLng(11.5564, 104.9282);

  /// Same contract as Geolocator.getCurrentPosition, except in debug mode
  /// it never actually throws or hangs — if real geolocation fails or
  /// takes longer than [timeout], it returns [fallback] instead.
  static Future<LatLng> getCurrentPosition({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(timeout);
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[DebugLocation] Real geolocation unavailable ($e) — using fallback Phnom Penh coordinates for testing.');
        return fallback;
      }
      rethrow;
    }
  }

  /// Same idea, but for confirming permission/service availability is
  /// real (used where the calling code needs a true/false rather than a
  /// position) — succeeds in debug mode even if real geolocation would
  /// have failed, since the fallback position stands in for it.
  static Future<bool> isAvailable() async {
    try {
      await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 6));
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[DebugLocation] Real geolocation unavailable ($e) — treating as available anyway (debug fallback).');
        return true;
      }
      return false;
    }
  }
}
