import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'api_client.dart';
import '../models/incident.dart';
import 'app_session.dart';

class EmergencyResponderService {
  /// Fetch cases available to this responder.
  static Future<List<Incident>> fetchCases() async {
    final data =
        await ApiClient.get('/emergency/responder/cases');

    final emergencies =
        (data['emergencies'] as List<dynamic>? ?? []);

    final incidents = <Incident>[];

    for (final item in emergencies) {
      if (item is! Map<String, dynamic>) {
        continue;
      }

      final emergency = item;

      final status =
          emergency['status']?.toString();

      if (status != 'emergency' &&
          status != 'in_progress' &&
          status != 'resolved') {
        continue;
      }

      final location =
          emergency['location']
              as Map<String, dynamic>?;

      final latitude =
          (location?['latitude'] as num?)
              ?.toDouble();

      final longitude =
          (location?['longitude'] as num?)
              ?.toDouble();

      if (latitude == null ||
          longitude == null) {
        continue;
      }

      final user =
          emergency['user']
              as Map<String, dynamic>?;

      final station =
          emergency['assignedStation']
              as Map<String, dynamic>?;

      final emergencyId =
          emergency['_id']?.toString();

      if (emergencyId == null ||
          emergencyId.isEmpty) {
        continue;
      }

      final stationAddress =
          station?['address']?.toString();

      final stationName =
          station?['name']?.toString();

      String destination;

      if (stationAddress != null &&
          stationAddress.isNotEmpty) {
        destination = stationAddress;
      } else if (stationName != null &&
          stationName.isNotEmpty) {
        destination = stationName;
      } else {
        destination = 'Emergency location';
      }

      incidents.add(
        Incident(
          id: emergencyId,

          personName:
              user?['name']?.toString() ??
                  'Unknown User',

          phone:
              user?['phone']?.toString() ??
                  '',

          destination:
              destination,

          location: LatLng(
            latitude,
            longitude,
          ),

          startedAt:
              DateTime.tryParse(
                    emergency['createdAt']
                            ?.toString() ??
                        '',
                  ) ??
                  DateTime.now(),

          status:
              _mapStatus(status),

          locationIsStale: false,

          notifiedContactIds:
              const [],

          resolvedAt:
              status == 'resolved'
                  ? DateTime.tryParse(
                      emergency['updatedAt']
                              ?.toString() ??
                          '',
                    )
                  : null,
        ),
      );
    }

    return incidents;
  }

  static IncidentStatus _mapStatus(
    String? status,
  ) {
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

  /// Responder takes the case.
  static Future<void> acceptCase(
    String emergencyId,
  ) async {
    await ApiClient.put(
      '/emergency/$emergencyId/accept',
      {},
    );
  }

  /// Responder resolves the case.
  static Future<void> resolveCase(
    String emergencyId,
  ) async {
    await ApiClient.put(
      '/emergency/$emergencyId/resolve',
      {},
    );
  }

  static String? get currentResponderId =>
      AppSession.instance.backendUserId;
}