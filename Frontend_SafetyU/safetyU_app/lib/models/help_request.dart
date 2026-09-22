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
  // Where the session owner actually said they were headed (from the
  // CheckIn's stored destination coordinates), separate from [location]
  // above which is their LIVE, moving position. Null until fetched from
  // the backend -- AlertDetailScreen fills this in alongside the live
  // location fetch, the same way it fills in [location].
  final LatLng? destinationLocation;
  // The Notification this specific alert was responded to from, plus any
  // duplicate/sibling notifications for the same event (see
  // AlertDetailScreen.siblingNotificationIds). Carried forward so
  // AlertResponseResultScreen's "Mark [name] as Safe" can mark the SAME
  // notification(s) resolved (responseStatus: 'marked_safe') that "Can
  // Help"/"Can't Help" already do -- without this, marking someone safe
  // never touched the notification itself, so it kept showing up in "You
  // were notified" as still-pending forever, even after the session had
  // genuinely ended.
  final String? notificationId;
  final List<String> siblingNotificationIds;

  const HelpRequest({
    required this.requesterName,
    required this.requesterPhone,
    required this.destination,
    required this.location,
    required this.distanceKm,
    required this.requestedAt,
    this.checkInId,
    this.destinationLocation,
    this.notificationId,
    this.siblingNotificationIds = const [],
  });
}
