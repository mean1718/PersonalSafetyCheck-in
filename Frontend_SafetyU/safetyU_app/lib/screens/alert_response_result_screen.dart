import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/marker_icons.dart';
import '../services/directions_service.dart';
import '../services/check_in_service.dart';
import '../services/notification_service.dart';

import '../theme/app_theme.dart';
import '../models/contact.dart';
import '../models/help_request.dart';
import '../models/incident.dart';
import '../models/app_notification.dart';
import '../services/app_session.dart';

enum AlertResponseOutcome { canHelp, cantHelp, lateResponse }

/// The outcome screen after a trusted contact responds — "Can Help",
/// "Can't Help", or a "Late response" if the window already closed.
class AlertResponseResultScreen extends StatelessWidget {
  final Contact contact;
  final HelpRequest request;
  final AlertResponseOutcome outcome;

  const AlertResponseResultScreen({
    super.key,
    required this.contact,
    required this.request,
    required this.outcome,
  });

  void _markRequesterSafe(BuildContext context) {
    AppSession.instance.addNotification(
      title: request.requesterName,
      body: 'You marked ${request.requesterName} as safe.',
      kind: NotificationKind.trustedContact,
    );
    // Tell the backend, not just this device's own local notification list
    // -- without this, the requester's own Active Session screen never
    // actually found out this happened at all.
    final checkInId = request.checkInId;
    if (checkInId != null) {
      CheckInService.confirmContactSafe(checkInId).catchError((e) {
        debugPrint('Confirm-safe sync skipped: $e');
      });
    }
    // Also resolve the actual Notification(s) this alert came from, the
    // same way "Can Help"/"Can't Help" already do (responseStatus:
    // 'marked_safe', which the backend treats as resolved). Without this,
    // Home's "You were notified" list has no idea this was ever handled
    // -- it only hides an alert once its notification stops being
    // "pending", so this one would sit there forever looking exactly like
    // an unanswered alert, even though the person is confirmed safe.
    final notificationId = request.notificationId;
    if (notificationId != null) {
      NotificationService.respondToSafetyAlert(notificationId, 'marked_safe')
          .catchError((e) {
        debugPrint('Mark-safe notification sync skipped: $e');
      });
      for (final siblingId in request.siblingNotificationIds) {
        NotificationService.respondToSafetyAlert(siblingId, 'marked_safe')
            .catchError((e) {});
      }
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${request.requesterName} is marked safe.')),
    );
  }

  void _viewLiveLocation(BuildContext context) {
    final location = request.location;
    final destination = request.destinationLocation;
    if (location == null && destination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No live location shared yet.')),
      );
      return;
    }
    // Drops down from the TOP of the screen instead of sliding up from the
    // bottom (a plain showModalBottomSheet) -- easier to see at a glance
    // without it competing with the buttons at the bottom of this screen.
    showGeneralDialog(
      context: context,
      barrierLabel: 'Live location',
      barrierDismissible: true,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, __) => const SizedBox.shrink(),
      transitionBuilder: (context, animation, _, __) {
        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -1),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                  parent: animation, curve: Curves.easeOutCubic)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Material(
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    height: 320,
                    child: Stack(
                      children: [
                        FutureBuilder<_MapAssets>(
                          // BitmapDescriptor.defaultMarkerWithHue doesn't
                          // render on web — load real pin images instead.
                          // The route is fetched here too so this whole
                          // one-shot dialog just re-renders once, same
                          // FutureBuilder pattern, when everything's ready.
                          future:
                              _loadMapAssets(context, location, destination),
                          builder: (context, snapshot) {
                            final liveIcon = snapshot.data?.liveIcon;
                            final destIcon = snapshot.data?.destinationIcon;
                            final route = snapshot.data?.route;
                            return GoogleMap(
                              onMapCreated: (controller) {
                                if (location != null && destination != null) {
                                  Future.delayed(
                                      const Duration(milliseconds: 200), () {
                                    controller.animateCamera(
                                      CameraUpdate.newLatLngBounds(
                                        _boundsFor([location, destination]),
                                        40,
                                      ),
                                    );
                                  });
                                }
                              },
                              initialCameraPosition: CameraPosition(
                                target: location ?? destination!,
                                zoom: 15,
                              ),
                              polylines: route == null
                                  ? {}
                                  : {
                                      Polyline(
                                        polylineId:
                                            const PolylineId('to-destination'),
                                        points: route.points,
                                        width: 4,
                                        color: AppColors.navy,
                                      ),
                                    },
                              markers: {
                                if (location != null)
                                  Marker(
                                    markerId: const MarkerId('live'),
                                    position: location,
                                    icon: liveIcon ??
                                        BitmapDescriptor.defaultMarker,
                                    infoWindow: const InfoWindow(
                                        title: 'Current location'),
                                  ),
                                if (destination != null)
                                  Marker(
                                    markerId: const MarkerId('destination'),
                                    position: destination,
                                    icon: destIcon ??
                                        BitmapDescriptor.defaultMarker,
                                    infoWindow:
                                        const InfoWindow(title: 'Destination'),
                                  ),
                              },
                            );
                          },
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Material(
                            color: Colors.white,
                            shape: const CircleBorder(),
                            elevation: 2,
                            child: IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Loads both marker icons and, when we have both endpoints, the actual
  /// road/walking route between them -- bundled into one Future so this
  /// one-shot dialog only needs a single FutureBuilder.
  Future<_MapAssets> _loadMapAssets(
      BuildContext context, LatLng? location, LatLng? destination) async {
    final icons = await Future.wait([
      MarkerIcons.destination(context),
      MarkerIcons.contactSelected(context),
    ]);
    RouteResult? route;
    if (location != null && destination != null) {
      try {
        route = await DirectionsService.route(
            from: location, to: destination, walking: true);
      } catch (e) {
        debugPrint('Route fetch failed: $e');
      }
    }
    return _MapAssets(
        liveIcon: icons[0], destinationIcon: icons[1], route: route);
  }

  /// Smallest LatLngBounds containing every point given -- fits both the
  /// live location and destination pins in frame together.
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

  void _backToHome(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _alertEmergencyResponders(BuildContext context) {
    AppSession.instance.addIncident(
      Incident(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        personName: request.requesterName.isEmpty
            ? 'SafetyU User'
            : request.requesterName,
        phone: request.requesterPhone,
        destination: request.destination,
        location: request.location ?? const LatLng(11.5696, 104.9210),
        startedAt: request.requestedAt,
        locationIsStale: request.location == null,
        notifiedContactIds: [contact.id],
      ),
    );
    AppSession.instance.addNotification(
      title: 'SafetyU System',
      body:
          '${contact.fullName} could not help and alerted Emergency Responders for ${request.requesterName}.',
      kind: NotificationKind.escalation,
    );
    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'Emergency Responders have been alerted for ${request.requesterName}.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (outcome) {
      case AlertResponseOutcome.canHelp:
        return _CanHelpScaffold(
          request: request,
          onViewLiveLocation: () => _viewLiveLocation(context),
          onMarkSafe: () => _markRequesterSafe(context),
        );

      case AlertResponseOutcome.cantHelp:
        return _ResultScaffold(
          title: "Can't Help",
          icon: Icons.close,
          iconColor: AppColors.danger,
          subtitle:
              "Thanks for responding.\nIf this looks serious, you can alert Emergency Responders directly.",
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => _alertEmergencyResponders(context),
                  icon: const Icon(Icons.warning_amber_rounded, size: 18),
                  label: const Text('Alert Emergency Responders'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () => _backToHome(context),
                  child: const Text('Back To Home'),
                ),
              ),
            ],
          ),
        );

      case AlertResponseOutcome.lateResponse:
        return _ResultScaffold(
          title: 'Late response',
          icon: Icons.schedule,
          iconColor: AppColors.textMuted,
          subtitle:
              "Thanks for responding.\nDon't worry, another contact will help.",
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => _backToHome(context),
              child: const Text('Back To Home'),
            ),
          ),
        );
    }
  }
}

/// Dedicated, more polished layout for the "Can Help" success state — the
/// main destination of the whole respond flow, so it gets the most care.
class _CanHelpScaffold extends StatelessWidget {
  final HelpRequest request;
  final VoidCallback onViewLiveLocation;
  final VoidCallback onMarkSafe;

  const _CanHelpScaffold({
    required this.request,
    required this.onViewLiveLocation,
    required this.onMarkSafe,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.success.withValues(alpha: 0.22),
                      AppColors.success.withValues(alpha: 0.06),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.success.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 32),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                "You're Helping!",
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                '${request.requesterName} has been notified that you\'re on the way. Thanks for responding.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textSecondary,
                    height: 1.45),
              ),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.navy.withValues(alpha: 0.1),
                      child: Text(
                        request.requesterName.isNotEmpty
                            ? request.requesterName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                            color: AppColors.navy, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            request.requesterName,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Near ${request.destination}',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton.icon(
                  onPressed: onViewLiveLocation,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: AppColors.navy.withValues(alpha: 0.3)),
                  ),
                  icon: Icon(Icons.location_on, color: AppColors.navy),
                  label: Text('View Live Location',
                      style: TextStyle(
                          color: AppColors.navy, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: onMarkSafe,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success),
                  // Explicit about *who* this marks safe — this confirms
                  // the requester's safety, not the responder's own.
                  child: Text('Mark ${request.requesterName} as Safe'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultScaffold extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final String subtitle;
  final Widget child;

  const _ResultScaffold({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 40),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textSecondary,
                    height: 1.4),
              ),
              const Spacer(),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Bundle of what the live-location popup's map needs to render in one
/// go: both marker icons and, when both endpoints are known, the actual
/// road/walking route between them.
class _MapAssets {
  final BitmapDescriptor liveIcon;
  final BitmapDescriptor destinationIcon;
  final RouteResult? route;

  const _MapAssets({
    required this.liveIcon,
    required this.destinationIcon,
    required this.route,
  });
}
