import 'package:latlong2/latlong.dart';

/// Lifecycle of a real escalated incident, as an officer works it.
enum IncidentStatus { newCase, inProgress, resolved }

extension IncidentStatusX on IncidentStatus {
  String get label {
    switch (this) {
      case IncidentStatus.newCase:
        return 'New';
      case IncidentStatus.inProgress:
        return 'In Progress';
      case IncidentStatus.resolved:
        return 'Resolved';
    }
  }
}

/// A real escalated safety session, created only when a session actually
/// reaches final "Emergency" escalation — not seeded example data. This is
/// what the Emergency Responder Dashboard and Cases screens read from.
class Incident {
  final String id;
  final String personName;
  final String phone;
  final String destination;
  final LatLng location;
  final DateTime startedAt;
  final bool locationIsStale;
  IncidentStatus status;
  DateTime? resolvedAt;

  Incident({
    required this.id,
    required this.personName,
    required this.phone,
    required this.destination,
    required this.location,
    required this.startedAt,
    this.locationIsStale = false,
    this.status = IncidentStatus.newCase,
    this.resolvedAt,
  });

  bool get responded => status != IncidentStatus.newCase;
}
