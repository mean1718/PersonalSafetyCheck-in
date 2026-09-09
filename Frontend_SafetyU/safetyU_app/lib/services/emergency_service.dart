import 'api_client.dart';

/// Wires the app's main -> secondary -> emergency escalation chain to the
/// backend's Emergency records:
///   POST /api/emergency                        (start — needs a primary
///                                                trusted contact to exist
///                                                on the backend, and a
///                                                real checkInId)
///   POST /api/emergency/:id/secondary
///   POST /api/emergency/:id/emergency
///   PUT  /api/emergency/:id/resolve
class EmergencyService {
  static Future<String?> start({
    required String checkInId,
    String? message,
    double? latitude,
    double? longitude,
  }) async {
    final data = await ApiClient.post('/emergency', {
      'checkInId': checkInId,
      if (message != null) 'message': message,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    });
    final emergency = data['emergency'] as Map<String, dynamic>?;
    return emergency?['_id']?.toString();
  }

  static Future<void> escalateToSecondary(String emergencyId) async {
    await ApiClient.post('/emergency/$emergencyId/secondary', {});
  }

  static Future<void> escalateToEmergency(String emergencyId) async {
    await ApiClient.post('/emergency/$emergencyId/emergency', {});
  }

  static Future<void> resolve(String emergencyId) async {
    await ApiClient.put('/emergency/$emergencyId/resolve', {});
  }
}