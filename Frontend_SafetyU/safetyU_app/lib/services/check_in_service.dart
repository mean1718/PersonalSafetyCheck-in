import 'api_client.dart';

/// Wires a safety session's start/complete to the backend's CheckIn
/// records:
///   POST /api/checkins        (start)
///   PUT  /api/checkins/:id/complete
///
/// Returns/accepts the backend's Mongo `_id` as a plain String — nothing
/// else about a CheckIn is currently read back by the app, so there's no
/// separate Dart model for it.
class CheckInService {
  static Future<List<Map<String, dynamic>>> trustedContacts() async {
    final data = await ApiClient.get('/checkins/trusted-contacts');
    return (data['contacts'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
  }

  static Future<String?> start({
    List<String> contactUserIds = const [],
    String message = '',
    double? latitude,
    double? longitude,
  }) async {
    final data = await ApiClient.post('/checkins', {
      if (contactUserIds.isNotEmpty) 'contactUserIds': contactUserIds,
      'message': message,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    });
    final checkIn = data['checkIn'] as Map<String, dynamic>?;
    return checkIn?['_id']?.toString();
  }

  static Future<void> complete(String checkInId) async {
    await ApiClient.put('/checkins/$checkInId/complete', {});
  }

  static Future<List<Map<String, dynamic>>> alertStatus(
      String checkInId) async {
    final data = await ApiClient.get('/checkins/$checkInId/alert-status');
    return (data['notifiedContacts'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
  }

  // Same call as alertStatus, but returns the session's own status too —
  // used to notice a trusted contact resolved the whole session
  // ("marked_safe") on the person's behalf, not just a per-contact reply.
  static Future<Map<String, dynamic>> alertStatusFull(String checkInId) async {
    return ApiClient.get('/checkins/$checkInId/alert-status');
  }

  static Future<void> updateLocation(
    String checkInId, {
    required double latitude,
    required double longitude,
  }) async {
    await ApiClient.put('/checkins/$checkInId/location', {
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  static Future<Map<String, dynamic>?> fetchLocation(String checkInId) async {
    try {
      final data = await ApiClient.get('/checkins/$checkInId/location');
      return data['location'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  // GET /api/checkins — every check-in *this* signed-in account has ever
  // started, most recent first. History used to only ever show whatever
  // happened to still be sitting in local memory since the last login,
  // which meant a fresh sign-in — or another account's leftover
  // memory — showed the wrong thing (or nothing at all). This is the
  // real, per-account record from the server.
  static Future<List<Map<String, dynamic>>> myCheckIns() async {
    final data = await ApiClient.get('/checkins');
    return (data['checkIns'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
  }

  // POST /api/checkins/:id/need-help — creates a fresh, real safety_alert
  // notification for the given contacts. The original session-start
  // notification only reflects state from when the session began; if a
  // contact already responded to it, nothing would otherwise resurface on
  // their Home screen for this more urgent later moment.
  static Future<void> needHelpNow(
      String checkInId, List<String> contactUserIds) async {
    await ApiClient.post('/checkins/$checkInId/need-help', {
      if (contactUserIds.isNotEmpty) 'contactUserIds': contactUserIds,
    });
  }
}
