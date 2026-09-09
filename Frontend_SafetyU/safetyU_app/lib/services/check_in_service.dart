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
  static Future<String?> start({
    String message = '',
    double? latitude,
    double? longitude,
  }) async {
    final data = await ApiClient.post('/checkins', {
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
}