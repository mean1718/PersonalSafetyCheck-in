//import 'package:latlong2/latlong.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'api_client.dart';
import '../models/incident.dart';
import 'app_session.dart';

class EmergencyResponderService {
  /// Fetch emergency cases assigned to the responder's station.
  static Future<List<Incident>> fetchCases() async {
    final data = await ApiClient.get('/emergency');

    final emergencies =
        (data['emergencies'] as List<dynamic>? ?? []);

    final incidents = <Incident>[];

    for (final item in emergencies) {
      final emergency = item as Map<String, dynamic>;

      final status = emergency['status']?.toString();

      // Only show emergencies that have reached police/emergency
      // escalation.
      if (status != 'emergency' &&
          status != 'in_progress' &&
          status != 'resolved') {
        continue;
      }

      final location =
          emergency['location'] as Map<String, dynamic>?;

      final latitude =
          (location?['latitude'] as num?)?.toDouble();

      final longitude =
          (location?['longitude'] as num?)?.toDouble();

      // A responder case needs a valid location.
      if (latitude == null || longitude == null) {
        continue;
      }

      final user =
          emergency['user'] as Map<String, dynamic>?;

      final station =
          emergency['assignedStation']
              as Map<String, dynamic>?;

      final emergencyId =
          emergency['_id']?.toString();

      if (emergencyId == null) {
        continue;
      }

      incidents.add(
        Incident(
          id: emergencyId,
          personName:
              user?['name']?.toString() ?? 'Unknown User',
          phone:
              user?['phone']?.toString() ?? '',
          destination:
              station?['address']?.toString() ??
              station?['name']?.toString() ??
              'Emergency location',
          location: LatLng(
            latitude,
            longitude,
          ),
          startedAt:
              DateTime.tryParse(
                    emergency['createdAt']?.toString() ?? '',
                  ) ??
                  DateTime.now(),
          status: _mapStatus(status),
          locationIsStale: false,
          notifiedContactIds: const [],
          resolvedAt:
              status == 'resolved'
                  ? DateTime.tryParse(
                      emergency['updatedAt']?.toString() ?? '',
                    )
                  : null,
        ),
      );
    }

    return incidents;
  }

  static IncidentStatus _mapStatus(String? status) {
    switch (status) {
      case 'in_progress':
        return IncidentStatus.inProgress;

      case 'resolved':
        return IncidentStatus.resolved;

      case 'emergency':
      default:
        return IncidentStatus.newCase;
    }
  }

  /// Accept an emergency case.
  static Future<void> acceptCase(String emergencyId) async {
    await ApiClient.put(
      '/emergency/$emergencyId/accept',
      {},
    );
  }

  /// Resolve an emergency case.
  static Future<void> resolveCase(String emergencyId) async {
    await ApiClient.put(
      '/emergency/$emergencyId/resolve',
      {},
    );
  }

  /// Returns the current responder's backend user ID.
  static String? get currentResponderId =>
      AppSession.instance.backendUserId;
}