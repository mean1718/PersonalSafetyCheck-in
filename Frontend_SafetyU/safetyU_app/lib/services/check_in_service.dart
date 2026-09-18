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
    double? destinationLatitude,
    double? destinationLongitude,
  }) async {
    final data = await ApiClient.post('/checkins', {
      if (contactUserIds.isNotEmpty) 'contactUserIds': contactUserIds,
      'message': message,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (destinationLatitude != null)
        'destinationLatitude': destinationLatitude,
      if (destinationLongitude != null)
        'destinationLongitude': destinationLongitude,
    });
    final checkIn = data['checkIn'] as Map<String, dynamic>?;
    return checkIn?['_id']?.toString();
  }

  static Future<void> complete(String checkInId) async {
    await ApiClient.put('/checkins/$checkInId/complete', {});
  }

  /// The full payload from GET /checkins/:id/alert-status -- both the
  /// per-contact can/can't-help responses AND, when set, who confirmed the
  /// owner safe (confirmedSafeBy). Used to be just the notifiedContacts
  /// list; broadened so Active Session's existing poll of this same
  /// endpoint can also drive the "Trust confirm you safe!" popup without
  /// a second polling loop.
  static Future<Map<String, dynamic>> alertStatus(String checkInId) async {
    return ApiClient.get('/checkins/$checkInId/alert-status');
  }

  /// Just the per-contact list, for callers that only need that part.
  static List<Map<String, dynamic>> notifiedContactsFrom(
          Map<String, dynamic> alertStatusData) =>
      (alertStatusData['notifiedContacts'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();

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

  /// The full payload from GET /checkins/:id/location -- both the
  /// session's LIVE location and, if the owner's session sent one, their
  /// original destination. Returns null (rather than throwing) on any
  /// failure -- no backend, session ended, not authorized, etc. -- same
  /// honest fallback pattern used elsewhere in this app for backend sync.
  static Future<Map<String, dynamic>?> fetchLocation(String checkInId) async {
    try {
      return await ApiClient.get('/checkins/$checkInId/location');
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

  // POST /api/checkins/:id/confirm-safe — a trusted contact taps "Mark
  // [owner] as Safe" on their side. This is what lets the OWNER's Active
  // Session screen show a "Trust confirm you safe!" popup -- before this,
  // that tap only ever updated the contact's own local notification list
  // and the owner never actually found out.
  static Future<void> confirmContactSafe(String checkInId) async {
    await ApiClient.post('/checkins/$checkInId/confirm-safe', {});
  }
}
