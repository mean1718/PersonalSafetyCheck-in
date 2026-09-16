import 'api_client.dart';

/// Connects Flutter to the backend Emergency API.
///
/// Emergency Assistant flow:
///
///   CheckInService.start()
///          ↓
///   EmergencyService.start(directEmergency: true)
///          ↓
///   EmergencyService.escalateToEmergency()
///          ↓
///   Responder notification
///
/// Normal safety-session flows can still use this service
/// without setting directEmergency.
class EmergencyService {
  // =========================================================
  // START EMERGENCY
  // =========================================================

  static Future<String?> start({
    required String checkInId,
    String? message,
    double? latitude,
    double? longitude,
    bool directEmergency = false,
  }) async {
    final data = await ApiClient.post(
      '/emergency',
      {
        'checkInId': checkInId,

        if (message != null)
          'message': message,

        if (latitude != null)
          'latitude': latitude,

        if (longitude != null)
          'longitude': longitude,

        if (directEmergency)
          'directEmergency': true,
      },
    );

    final emergency =
        data['emergency']
            as Map<String, dynamic>?;

    return emergency?['_id']?.toString();
  }

  // =========================================================
  // ESCALATE TO SECONDARY
  // =========================================================

  static Future<void> escalateToSecondary(
    String emergencyId,
  ) async {
    await ApiClient.post(
      '/emergency/$emergencyId/secondary',
      {},
    );
  }

  // =========================================================
  // ESCALATE TO EMERGENCY RESPONDER
  // =========================================================

  static Future<void> escalateToEmergency(
    String emergencyId,
  ) async {
    await ApiClient.post(
      '/emergency/$emergencyId/emergency',
      {},
    );
  }

  // =========================================================
  // RESOLVE
  // =========================================================

  static Future<void> resolve(
    String emergencyId,
  ) async {
    await ApiClient.put(
      '/emergency/$emergencyId/resolve',
      {},
    );
  }
}