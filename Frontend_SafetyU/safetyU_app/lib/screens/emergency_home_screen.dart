import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../services/marker_icons.dart';
import '../theme/app_theme.dart';
import '../models/incident.dart';
import '../services/app_session.dart';
import '../services/alert_sound.dart';
import '../services/notification_service.dart';
import '../widgets/responder_bottom_nav.dart';

/// Officer Dashboard — landing screen for the Emergency Responder role.
///
/// Real emergency cases are loaded from backend
/// `emergency_alert` notifications.
///
/// Flow:
///
/// Backend emergency
///      ↓
/// NotificationService.fetchAll()
///      ↓
/// emergency_alert notification
///      ↓
/// Create Incident
///      ↓
/// AppSession.activeIncidents
///      ↓
/// Responder dashboard / Cases
class EmergencyHomeScreen extends StatefulWidget {
  const EmergencyHomeScreen({super.key});

  @override
  State<EmergencyHomeScreen> createState() =>
      _EmergencyHomeScreenState();
}

class _EmergencyHomeScreenState extends State<EmergencyHomeScreen> {
  GoogleMapController? _mapController;

  StreamSubscription<Position>? _positionSub;

  Timer? _notificationTimer;

  LatLng? _myPosition;

  int _lastKnownIncidentCount = 0;

  BitmapDescriptor? _meIcon;
  BitmapDescriptor? _incidentIcon;

  bool _markerIconsRequested = false;

  /// Emergency notification IDs that have already
  /// been converted into Incident objects.
  final Set<String> _loadedEmergencyNotificationIds = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Load real pin images for Google Maps.
    if (!_markerIconsRequested) {
      _markerIconsRequested = true;

      Future.wait([
        MarkerIcons.me(context),
        MarkerIcons.destination(context),
      ]).then((icons) {
        if (!mounted) return;

        setState(() {
          _meIcon = icons[0];
          _incidentIcon = icons[1];
        });
      });
    }
  }

  @override
  void initState() {
    super.initState();

    _lastKnownIncidentCount =
        AppSession.instance.activeIncidents.length;

    _initLocationTracking();

    // Load emergency notifications immediately.
    _loadEmergencyNotifications();

    // Keep checking for new emergency notifications.
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _loadEmergencyNotifications(),
    );

    AppSession.instance.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    _positionSub?.cancel();

    _notificationTimer?.cancel();

    AppSession.instance.removeListener(_onSessionChanged);

    super.dispose();
  }

  // =========================================================
  // LOAD REAL EMERGENCY NOTIFICATIONS
  // =========================================================

  Future<void> _loadEmergencyNotifications() async {
    try {
      final notifications = await NotificationService.fetchAll();

      final emergencyNotifications = notifications.where(
        (notification) {
          return notification['type']?.toString() == 'emergency_alert';
        },
      ).toList();

      bool addedAny = false;

      for (final notification in emergencyNotifications) {
        final notificationId =
            notification['_id']?.toString();

        if (notificationId == null) {
          continue;
        }

        // Already converted into a case.
        if (_loadedEmergencyNotificationIds.contains(notificationId)) {
          continue;
        }

        // ---------------------------------------------------
        // Sender
        // ---------------------------------------------------

        final sender =
            notification['sender'] as Map<String, dynamic>?;

        // ---------------------------------------------------
        // Emergency location
        // ---------------------------------------------------

        final location =
            notification['location'] as Map<String, dynamic>?;

        final latitude =
            (location?['latitude'] as num?)?.toDouble();

        final longitude =
            (location?['longitude'] as num?)?.toDouble();

        // Without a valid location we cannot
        // create a map-based Incident.
        if (latitude == null || longitude == null) {
          debugPrint(
            'Emergency notification $notificationId '
            'has no valid location.',
          );

          _loadedEmergencyNotificationIds.add(notificationId);

          continue;
        }

        // ---------------------------------------------------
        // Notification creation time
        // ---------------------------------------------------

        final createdAt =
            DateTime.tryParse(
              notification['createdAt']?.toString() ?? '',
            ) ??
            DateTime.now();

        // ---------------------------------------------------
        // Create real Incident
        // ---------------------------------------------------

        final incident = Incident(
          id: notificationId,
          personName:
              sender?['name']?.toString() ?? 'SafetyU User',
          phone:
              sender?['phone']?.toString() ?? '',
          destination:
              'Emergency Assistant — current location',
          location: LatLng(latitude, longitude),
          startedAt: createdAt,
          notifiedContactIds: const [],
        );

        // Add to shared responder case list.
        AppSession.instance.addIncident(incident);

        _loadedEmergencyNotificationIds.add(notificationId);

        addedAny = true;

        // ---------------------------------------------------
        // Mark notification as read.
        // ---------------------------------------------------

        try {
          await NotificationService.markRead(notificationId);
        } catch (e) {
          debugPrint(
            'Could not mark emergency notification '
            'as read: $e',
          );
        }
      }

      if (addedAny && mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint(
        'Emergency notification polling failed: $e',
      );
    }
  }

  // =========================================================
  // SESSION CHANGE
  // =========================================================

  void _onSessionChanged() {
    final count =
        AppSession.instance.activeIncidents.length;

    if (count > _lastKnownIncidentCount) {
      // A brand-new emergency case just came in.
      AlertSoundService.playAlert(
        times: 4,
      );
    }

    _lastKnownIncidentCount = count;

    if (mounted) {
      setState(() {});
    }
  }

  // =========================================================
  // LOCATION
  // =========================================================

  Future<void> _initLocationTracking() async {
    final bool serviceEnabled =
        await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      return;
    }

    LocationPermission permission =
        await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission =
          await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    try {
      final pos =
          await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _myPosition = LatLng(
          pos.latitude,
          pos.longitude,
        );
      });
    } catch (_) {}

    _positionSub =
        Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen((pos) {
      if (!mounted) {
        return;
      }

      setState(() {
        _myPosition = LatLng(
          pos.latitude,
          pos.longitude,
        );
      });
    });
  }

  // =========================================================
  // LOGOUT
  // =========================================================

  void _logout() {
    AppSession.instance.signOut();

    Navigator.pushNamedAndRemoveUntil(
      context,
      '/login',
      (route) => false,
    );
  }

  // =========================================================
  // NAVIGATION
  // =========================================================

  void _onNavTap(int index) {
    switch (index) {
      case 1:
        Navigator.pushNamed(
          context,
          '/cases',
        );
        break;

      case 2:
        Navigator.pushNamed(
          context,
          '/reports',
        );
        break;

      case 3:
        Navigator.pushNamed(
          context,
          '/profile',
        );
        break;
    }
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final incidents =
        AppSession.instance.activeIncidents;

    final newCount = incidents
        .where(
          (i) =>
              i.status ==
              IncidentStatus.newCase,
        )
        .length;

    final inProgressCount = incidents
        .where(
          (i) =>
              i.status ==
              IncidentStatus.inProgress,
        )
        .length;

    final resolvedCount = incidents
        .where(
          (i) =>
              i.status ==
              IncidentStatus.resolved,
        )
        .length;

    final newIncidents = incidents
        .where(
          (i) =>
              i.status ==
              IncidentStatus.newCase,
        )
        .toList();

    final newestIncident =
        newIncidents.isNotEmpty
            ? newIncidents.first
            : null;

    final recentlyResolved =
        incidents
            .where(
              (i) =>
                  i.status ==
                  IncidentStatus.resolved,
            )
            .toList()
          ..sort(
            (a, b) =>
                (b.resolvedAt ?? b.startedAt)
                    .compareTo(
                  a.resolvedAt ?? a.startedAt,
                ),
          );

    return Scaffold(
      backgroundColor: AppColors.background,

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            20,
            16,
            20,
            24,
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              // =================================================
              // HEADER
              // =================================================

              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.navy,
                      borderRadius:
                          BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.local_police,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Incoming Officer',
                          style: TextStyle(
                            fontSize: 12.5,
                            color:
                                AppColors.textSecondary,
                          ),
                        ),

                        Text(
                          AppSession.instance.fullName.isEmpty
                              ? 'Officer'
                              : AppSession.instance.fullName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight:
                                FontWeight.w800,
                            color:
                                AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Notification button
                  GestureDetector(
                    onTap: () =>
                        Navigator.pushNamed(
                      context,
                      '/notifications',
                    ),
                    child: Container(
                      padding:
                          const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.border,
                        ),
                      ),
                      child: Icon(
                        Icons.notifications_none,
                        color:
                            AppColors.textPrimary,
                        size: 20,
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Logout button
                  GestureDetector(
                    onTap: _logout,
                    child: Container(
                      padding:
                          const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.border,
                        ),
                      ),
                      child: Icon(
                        Icons.logout,
                        color:
                            AppColors.textPrimary,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // =================================================
              // NEW EMERGENCY BANNER
              // =================================================

              if (newestIncident != null)
                GestureDetector(
                  onTap: () =>
                      Navigator.pushNamed(
                    context,
                    '/case-detail',
                    arguments: newestIncident.id,
                  ),
                  child: Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color:
                          AppColors.dangerLight,
                      borderRadius:
                          BorderRadius.circular(14),
                      border: Border.all(
                        color:
                            const Color(0xFFFFC9C0),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: AppColors.danger,
                        ),

                        const SizedBox(width: 10),

                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                'New Emergency',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight:
                                      FontWeight.w800,
                                  color:
                                      AppColors.danger,
                                ),
                              ),

                              Text(
                                '${newestIncident.personName} needs help',
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      AppColors.danger,
                                ),
                              ),
                            ],
                          ),
                        ),

                        Icon(
                          Icons.chevron_right,
                          color: AppColors.danger,
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // =================================================
              // MAP
              // =================================================

              ClipRRect(
                borderRadius:
                    BorderRadius.circular(16),
                child: SizedBox(
                  height: 160,
                  child: GoogleMap(
                    onMapCreated: (controller) {
                      _mapController = controller;
                    },
                    initialCameraPosition:
                        CameraPosition(
                      target:
                          _myPosition ??
                          const LatLng(
                            11.5696,
                            104.9210,
                          ),
                      zoom: 13.0,
                    ),
                    markers: {
                      if (_myPosition != null)
                        Marker(
                          markerId:
                              const MarkerId('me'),
                          position: _myPosition!,
                          icon:
                              _meIcon ??
                              BitmapDescriptor
                                  .defaultMarker,
                        ),

                      for (final incident
                          in incidents.where(
                        (i) =>
                            i.status !=
                            IncidentStatus.resolved,
                      ))
                        Marker(
                          markerId:
                              MarkerId(incident.id),
                          position:
                              incident.location,
                          icon:
                              _incidentIcon ??
                              BitmapDescriptor
                                  .defaultMarker,
                        ),
                    },
                  ),
                ),
              ),

              const SizedBox(height: 22),

              // =================================================
              // TODAY'S OVERVIEW
              // =================================================

              Text(
                "Today's Overview",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight:
                      FontWeight.w800,
                  color:
                      AppColors.textPrimary,
                ),
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _StatPill(
                      count: newCount,
                      label: 'New',
                      color:
                          AppColors.danger,
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: _StatPill(
                      count: inProgressCount,
                      label: 'In Progress',
                      color:
                          const Color(0xFFE59A2E),
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: _StatPill(
                      count: resolvedCount,
                      label: 'Resolved',
                      color:
                          AppColors.success,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              // =================================================
              // RECENT ACTIVITY
              // =================================================

              Text(
                'Recent Activity',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight:
                      FontWeight.w800,
                  color:
                      AppColors.textPrimary,
                ),
              ),

              const SizedBox(height: 10),

              if (recentlyResolved.isEmpty)
                Text(
                  'No resolved cases yet.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color:
                        AppColors.textSecondary,
                  ),
                )
              else
                ...recentlyResolved
                    .take(3)
                    .map(
                  (incident) => Padding(
                    padding:
                        const EdgeInsets.only(
                      bottom: 10,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration:
                              BoxDecoration(
                            color:
                                AppColors.success
                                    .withValues(
                              alpha: 0.12,
                            ),
                            shape:
                                BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check,
                            color:
                                AppColors.success,
                            size: 18,
                          ),
                        ),

                        const SizedBox(width: 10),

                        Expanded(
                          child: Text(
                            'Case #${incident.id.substring(incident.id.length - 3)} marked as resolved',
                            style: TextStyle(
                              fontSize: 12.5,
                              color:
                                  AppColors.textPrimary,
                              fontWeight:
                                  FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),

      bottomNavigationBar:
          ResponderBottomNav(
        currentIndex: 0,
        onTap: _onNavTap,
      ),
    );
  }
}

// ===========================================================
// STAT PILL
// ===========================================================

class _StatPill extends StatelessWidget {
  final int count;
  final String label;
  final Color color;

  const _StatPill({
    required this.count,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        vertical: 14,
        horizontal: 8,
      ),
      decoration:
          BoxDecoration(
        color: AppColors.card,
        borderRadius:
            BorderRadius.circular(14),
        border:
            Border.all(
          color:
              color.withValues(
            alpha: 0.4,
          ),
        ),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 18,
              fontWeight:
                  FontWeight.w800,
              color: color,
            ),
          ),

          const SizedBox(height: 2),

          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color:
                  AppColors.textSecondary,
            ),
            textAlign:
                TextAlign.center,
          ),
        ],
      ),
    );
  }
}