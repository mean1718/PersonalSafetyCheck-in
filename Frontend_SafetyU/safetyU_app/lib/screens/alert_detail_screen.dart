import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/marker_icons.dart';
import '../services/directions_service.dart';

import '../theme/app_theme.dart';
import '../models/contact.dart';
import '../models/help_request.dart';
import '../models/contact_response_state.dart';
import '../services/app_session.dart';
import '../services/check_in_service.dart';
import '../services/notification_service.dart';
import 'alert_response_result_screen.dart';

/// "Alert detail" — what a trusted contact sees when they open a safety
/// session alert. They decide right here whether they can help — there's
/// no separate "Can you Help?" middle screen anymore.
///
/// NEW: on open, this now asks the backend for the Safety User's REAL,
/// live location (GET /checkins/:id/location) instead of only showing the
/// snapshot baked into [request] at the time it was built. If that call
/// fails (no backend, session ended, not authorized, etc.) it falls back
/// to the snapshot — same honest fallback pattern used elsewhere in this
/// app for backend sync.
class AlertDetailScreen extends StatefulWidget {
  final Contact contact;
  final HelpRequest request;
  // Set when this screen was opened from a real backend alert (Home's
  // incoming-alert card). When present, responding here actually calls
  // PUT /notifications/:id/response so the session owner sees the real
  // response — not just a local-only update on this device.
  final String? notificationId;
  // Other still-pending alerts from the same sender (repeated/duplicate
  // test sessions pile these up fast) — resolved with the same outcome
  // the moment this one is, so she never has to tap through each one.
  final List<String> siblingNotificationIds;

  const AlertDetailScreen({
    super.key,
    required this.contact,
    required this.request,
    this.notificationId,
    this.siblingNotificationIds = const [],
  });

  @override
  State<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends State<AlertDetailScreen> {
  LatLng? _liveLocation;
  // Where the session owner said they were headed, fetched from the
  // backend alongside the live location -- kept separate so the map can
  // show both "where they are right now" and "where they were headed",
  // the same distinction the owner's own session screen shows.
  LatLng? _destinationLocation;
  bool _isLoadingLocation = true;
  bool _sending = false;
  // Red pin -- the live, moving position. Violet pin -- the destination
  // they set when the session started. Same palette as everywhere else
  // markers are shown in this app (see MarkerIcons).
  BitmapDescriptor? _liveIcon;
  BitmapDescriptor? _destinationIcon;
  bool _markerIconRequested = false;
  // The actual road/walking path from where they are to where they were
  // headed -- without this the map only showed two disconnected pins with
  // no sense of the route between them, the way active_session_screen's
  // own map already does for the session owner.
  RouteResult? _route;
  bool _routeRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // BitmapDescriptor.defaultMarkerWithHue doesn't render on web — load a
    // real pin image instead, same as every other map screen.
    if (!_markerIconRequested) {
      _markerIconRequested = true;
      Future.wait([
        MarkerIcons.destination(context),
        MarkerIcons.contactSelected(context),
      ]).then((icons) {
        if (!mounted) return;
        setState(() {
          _liveIcon = icons[0];
          _destinationIcon = icons[1];
        });
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _liveLocation = widget.request.location;
    _destinationLocation = widget.request.destinationLocation;
    _fetchLiveLocation();
  }

  Future<void> _fetchLiveLocation() async {
    final checkInId = widget.request.checkInId;
    if (checkInId == null) {
      setState(() => _isLoadingLocation = false);
      return;
    }
    final data = await CheckInService.fetchLocation(checkInId);
    if (!mounted) return;
    final location = data?['location'] as Map<String, dynamic>?;
    final destination = data?['destination'] as Map<String, dynamic>?;
    final lat = (location?['latitude'] as num?)?.toDouble();
    final lng = (location?['longitude'] as num?)?.toDouble();
    final destLat = (destination?['latitude'] as num?)?.toDouble();
    final destLng = (destination?['longitude'] as num?)?.toDouble();
    setState(() {
      if (lat != null && lng != null) {
        _liveLocation = LatLng(lat, lng);
      }
      if (destLat != null && destLng != null) {
        _destinationLocation = LatLng(destLat, destLng);
      }
      _isLoadingLocation = false;
    });
    _fetchRoute();
  }

  Future<void> _fetchRoute() async {
    if (_routeRequested) return;
    final from = _liveLocation;
    final to = _destinationLocation;
    if (from == null || to == null) return;
    _routeRequested = true;
    try {
      final route =
          await DirectionsService.route(from: from, to: to, walking: true);
      if (!mounted) return;
      setState(() => _route = route);
    } catch (e) {
      debugPrint('Route fetch failed: $e');
      _routeRequested = false;
    }
  }

  /// Smallest LatLngBounds containing every point given -- used to fit
  /// both the live location and destination pins in frame together,
  /// whichever side of each other they end up on.
  LatLngBounds _boundsFor(List<LatLng> points) {
    var minLat = points.first.latitude, maxLat = points.first.latitude;
    var minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  String _formatClock(DateTime t) {
    final hour24 = t.hour;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $period';
  }

  Future<void> _respond(
      BuildContext context, AlertResponseOutcome outcome) async {
    if (_sending) return;
    final notificationId = widget.notificationId;
    if (notificationId != null) {
      setState(() => _sending = true);
      final responseStatus =
          outcome == AlertResponseOutcome.canHelp ? 'can_help' : 'cannot_help';
      try {
        await NotificationService.respondToSafetyAlert(
            notificationId, responseStatus);
      } catch (_) {
        if (mounted) {
          setState(() => _sending = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Could not send your response. Try again.')),
          );
        }
        return;
      }
      // Best-effort — if one of these fails, it just stays pending and
      // she can resolve it normally later; it doesn't block this response.
      for (final siblingId in widget.siblingNotificationIds) {
        try {
          await NotificationService.respondToSafetyAlert(
              siblingId, responseStatus);
        } catch (_) {}
      }
    }

    AppSession.instance.recordContactOutcome(
      widget.contact.id,
      outcome == AlertResponseOutcome.canHelp
          ? ContactResponseStatus.canHelp
          : ContactResponseStatus.cantHelp,
    );
    if (outcome == AlertResponseOutcome.canHelp) {
      // Let every other contact who was also alerted (and hasn't answered
      // yet) know someone's already on it, so they don't all show up too.
      AppSession.instance
          .notifyOthersHelping(widget.contact.id, widget.contact.fullName);
    }
    if (!mounted) return;
    // Carry forward whatever live location this screen actually fetched —
    // widget.request only ever holds the original snapshot (often null),
    // so without this the result screen's "View Live Location" always
    // reports "No live location shared yet.", even right after this
    // screen showed it on the map.
    final updatedRequest = HelpRequest(
      requesterName: widget.request.requesterName,
      requesterPhone: widget.request.requesterPhone,
      destination: widget.request.destination,
      location: _liveLocation,
      distanceKm: widget.request.distanceKm,
      requestedAt: widget.request.requestedAt,
      checkInId: widget.request.checkInId,
      destinationLocation: _destinationLocation,
    );
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AlertResponseResultScreen(
          contact: widget.contact,
          request: updatedRequest,
          outcome: outcome,
          notificationId: widget.notificationId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final location = _liveLocation;
    final destinationLocation = _destinationLocation;
    final distanceLabel = request.distanceKm != null
        ? '${request.distanceKm!.toStringAsFixed(1)} km'
        : 'Unavailable';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Alert detail',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
            Text(
              'View and respond to this alert',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 180,
                        width: double.infinity,
                        child: _isLoadingLocation
                            ? Container(
                                color: AppColors.card,
                                alignment: Alignment.center,
                                child: const CircularProgressIndicator(),
                              )
                            : (location != null || destinationLocation != null)
                                ? GoogleMap(
                                    onMapCreated: (controller) {
                                      // Fit both pins in frame when we have
                                      // both -- otherwise just center on
                                      // whichever one we actually have.
                                      if (location != null &&
                                          destinationLocation != null) {
                                        Future.delayed(
                                            const Duration(milliseconds: 200),
                                            () {
                                          controller.animateCamera(
                                            CameraUpdate.newLatLngBounds(
                                              _boundsFor([
                                                location,
                                                destinationLocation
                                              ]),
                                              40,
                                            ),
                                          );
                                        });
                                      }
                                    },
                                    initialCameraPosition: CameraPosition(
                                      target: location ?? destinationLocation!,
                                      zoom: 14.5,
                                    ),
                                    polylines: _route == null
                                        ? {}
                                        : {
                                            Polyline(
                                              polylineId: const PolylineId(
                                                  'to-destination'),
                                              points: _route!.points,
                                              width: 4,
                                              color: AppColors.navy,
                                            ),
                                          },
                                    markers: {
                                      if (location != null)
                                        Marker(
                                          markerId: const MarkerId('live'),
                                          position: location,
                                          icon: _liveIcon ??
                                              BitmapDescriptor.defaultMarker,
                                          infoWindow: const InfoWindow(
                                              title: 'Current location'),
                                        ),
                                      if (destinationLocation != null)
                                        Marker(
                                          markerId:
                                              const MarkerId('destination'),
                                          position: destinationLocation,
                                          icon: _destinationIcon ??
                                              BitmapDescriptor.defaultMarker,
                                          infoWindow: const InfoWindow(
                                              title: 'Destination'),
                                        ),
                                    },
                                  )
                                : Container(
                                    color: AppColors.card,
                                    alignment: Alignment.center,
                                    child: Text(
                                      'Location unavailable',
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          color: AppColors.textSecondary),
                                    ),
                                  ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Contact identity card — the person's own profile
                    // avatar/initials, not a generic mascot.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor:
                                AppColors.navy.withValues(alpha: 0.1),
                            child: Text(
                              request.requesterName.isNotEmpty
                                  ? request.requesterName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                  color: AppColors.navy,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      request.requesterName,
                                      style: TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.textPrimary),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.success
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        'Online',
                                        style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.success),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.place_outlined,
                                        size: 13, color: AppColors.textMuted),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'Destination: ${request.destination}',
                                        style: TextStyle(
                                            fontSize: 12.5,
                                            color: AppColors.textSecondary),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(Icons.schedule,
                                        size: 13, color: AppColors.textMuted),
                                    const SizedBox(width: 4),
                                    Text(
                                      _formatClock(request.requestedAt),
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: AppColors.textMuted),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Distance + alert time — Route was dropped since this
                    // app has no real routing data to show honestly.
                    Row(
                      children: [
                        Expanded(
                          child: _InfoTile(
                            icon: Icons.social_distance,
                            label: 'Distance',
                            value: distanceLabel,
                            color: AppColors.success,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _InfoTile(
                            icon: Icons.access_time,
                            label: 'Alert Time',
                            value: _formatClock(request.requestedAt),
                            color: AppColors.navy,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.shield_outlined,
                              size: 18, color: AppColors.success),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${request.requesterName} has triggered an alert. Please check the location and respond if needed.',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textPrimary,
                                  height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: OutlinedButton(
                        onPressed: _sending
                            ? null
                            : () => _respond(
                                context, AlertResponseOutcome.cantHelp),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppColors.danger),
                        ),
                        child: Text("I Can't Help",
                            style: TextStyle(color: AppColors.danger)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _sending
                            ? null
                            : () =>
                                _respond(context, AlertResponseOutcome.canHelp),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                        ),
                        child: _sending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text('Respond to ${request.requesterName}'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}
