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

  /// Ids of the trusted contacts who were actually alerted about this
  /// person's session before it escalated. When a responder changes this
  /// case's status, these are the people (besides the requester) who get
  /// told — never the requester's whole friends list regardless of who
  /// was really notified.
  final List<String> notifiedContactIds;

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
    List<String>? notifiedContactIds,
  }) : notifiedContactIds = notifiedContactIds ?? const [];

  bool get responded => status != IncidentStatus.newCase;
}
