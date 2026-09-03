import 'package:latlong2/latlong.dart';

/// A real escalated safety session, created only when a session actually
/// reaches final "Emergency" escalation — not seeded example data. This is
/// what the Emergency Responder Dashboard reads from.
class Incident {
  final String id;
  final String personName;
  final String phone;
  final String destination;
  final LatLng location;
  final DateTime startedAt;
  final bool locationIsStale;
  bool responded;

  Incident({
    required this.id,
    required this.personName,
    required this.phone,
    required this.destination,
    required this.location,
    required this.startedAt,
    this.locationIsStale = false,
    this.responded = false,
  });
}
