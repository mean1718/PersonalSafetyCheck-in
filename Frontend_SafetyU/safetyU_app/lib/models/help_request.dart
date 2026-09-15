import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Read-only context for one "can you help" request shown to a trusted
/// contact. SafetyU has no backend, so there's no live feed from the
/// contact's own phone — this is built from the signed-in person's own
/// real, most recent session data (destination + last known position),
/// used to show that contact what they would actually see. Nothing here
/// is fabricated placeholder data.
class HelpRequest {
  final String requesterName;
  final String requesterPhone;
  final String destination;
  final LatLng? location;
  final double? distanceKm;
  final DateTime requestedAt;
  // NEW: the backend CheckIn _id for this session, if one was created.
  // Used by AlertDetailScreen to fetch the Safety User's REAL, live
  // location from the backend instead of relying on this snapshot.
  final String? checkInId;

  const HelpRequest({
    required this.requesterName,
    required this.requesterPhone,
    required this.destination,
    required this.location,
    required this.distanceKm,
    required this.requestedAt,
    this.checkInId,
  });
}
