import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
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
  BitmapDescriptor? _meIcon;
  bool _markerIconRequested = false;
  // The actual road/walking path from where they are to where they were
  // headed -- without this the map only showed two disconnected pins with
  // no sense of the route between them, the way active_session_screen's
  // own map already does for the session owner.
  RouteResult? _route;
  bool _routeInFlight = false;
  LatLng? _routeOrigin;
  DateTime? _routeFetchedAt;
  bool _routeWalking = true;

  // The line from THIS contact to the person, so they can see how to reach
  // them, not just where the person is.
  RouteResult? _routeToUser;
  bool _toUserInFlight = false;
  LatLng? _toUserFrom;
  LatLng? _toUserTo;
  DateTime? _toUserFetchedAt;
  bool _toUserWalking = true;

  // Nobody walks 30 km. Beyond this straight-line distance, routes and
  // travel times are for a car instead of on foot.
  static const double _walkableMeters = 3000;

  String? _delayReason;

  // ---- Live updates ----
  // The screen used to fetch the person's location ONCE when it opened, so
  // a contact watching it saw a frozen dot. It now refreshes every few
  // seconds while the session is live and stops when it ends or the
  // person arrives.
  static const Duration _refreshEvery = Duration(seconds: 5);
  Timer? _refreshTimer;
  Timer? _clockTimer;
  // Ticks every second. Only the widgets that show a running time
  // ("Live · 5s ago", "overdue by 2 min") listen to it — the map and the
  // rest of the screen are NOT rebuilt every second any more.
  final ValueNotifier<int> _clockTick = ValueNotifier<int>(0);
  bool _fetchInFlight = false;
  int _tick = 0;
  GoogleMapController? _mapController;

  String? _destinationName;
  DateTime? _arrivedAt;
  DateTime? _locationUpdatedAt;
  DateTime? _expectedEndAt;
  int? _serverDistanceToDestination;
  bool _sessionEnded = false;
  // Difference between the server's clock and this phone's, so "updated 5s
  // ago" / "overdue" stay right even if this phone's clock is off.
  Duration _clockSkew = Duration.zero;

  // This trusted contact's OWN position, used to show how far they are
  // from the person who needs help.
  LatLng? _myPosition;
  bool _myPositionInFlight = false;
  String? _myPositionProblem;

  DateTime get _serverNow => DateTime.now().add(_clockSkew);

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
        MarkerIcons.me(context),
      ]).then((icons) {
        if (!mounted) return;
        setState(() {
          _liveIcon = icons[0];
          _destinationIcon = icons[1];
          _meIcon = icons[2];
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
    _updateMyPosition();
    _refreshTimer = Timer.periodic(_refreshEvery, (_) {
      _tick++;
      _fetchLiveLocation();
      // The contact's own GPS doesn't need to be re-read as often.
      if (_tick % 3 == 0) _updateMyPosition();
    });
    // Re-draw once a second so "updated 5s ago" and the overdue check stay
    // current between refreshes.
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _clockTick.value++;
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _clockTimer?.cancel();
    _clockTick.dispose();
    super.dispose();
  }

  Future<void> _updateMyPosition() async {
    if (_myPositionInFlight) return;
    _myPositionInFlight = true;
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _myPositionProblem =
              'Allow location access to see how far you are.');
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        _myPosition = LatLng(position.latitude, position.longitude);
        _myPositionProblem = null;
      });
      _fetchRouteToUser();
      _ensureLiveVisible();
    } catch (_) {
      if (mounted && _myPosition == null) {
        setState(() => _myPositionProblem =
            'We could not read your location. Check that location is on and allowed.');
      }
    } finally {
      _myPositionInFlight = false;
    }
  }

  Future<void> _fetchLiveLocation() async {
    final checkInId = widget.request.checkInId;
    if (checkInId == null) {
      _refreshTimer?.cancel();
      if (mounted) setState(() => _isLoadingLocation = false);
      return;
    }
    if (_fetchInFlight) return;
    _fetchInFlight = true;
    try {
      final data = await CheckInService.fetchLocation(checkInId);
      if (!mounted) return;

      if (data?['ended'] == true) {
        // Session over: stop refreshing, keep the last known point on the
        // map, and say plainly that it is no longer live.
        _refreshTimer?.cancel();
        setState(() {
          _sessionEnded = true;
          _isLoadingLocation = false;
        });
        return;
      }

      final location = data?['location'] as Map<String, dynamic>?;
      final destination = data?['destination'] as Map<String, dynamic>?;
      final lat = (location?['latitude'] as num?)?.toDouble();
      final lng = (location?['longitude'] as num?)?.toDouble();
      final destLat = (destination?['latitude'] as num?)?.toDouble();
      final destLng = (destination?['longitude'] as num?)?.toDouble();
      final name = data?['destinationName']?.toString();
      final serverTime =
          DateTime.tryParse(data?['serverTime']?.toString() ?? '');
      final newDestination = (destLat != null && destLng != null)
          ? LatLng(destLat, destLng)
          : null;
      final destinationChanged = newDestination != null &&
          _destinationLocation != null &&
          (newDestination.latitude != _destinationLocation!.latitude ||
              newDestination.longitude != _destinationLocation!.longitude);

      setState(() {
        if (lat != null && lng != null) _liveLocation = LatLng(lat, lng);
        if (newDestination != null) _destinationLocation = newDestination;
        if (name != null && name.isNotEmpty) _destinationName = name;
        _arrivedAt = DateTime.tryParse(data?['arrivedAt']?.toString() ?? '');
        _locationUpdatedAt =
            DateTime.tryParse(data?['locationUpdatedAt']?.toString() ?? '');
        _expectedEndAt =
            DateTime.tryParse(data?['expectedEndAt']?.toString() ?? '');
        final reason = data?['delayReason']?.toString().trim() ?? '';
        _delayReason = reason.isEmpty ? null : reason;
        _serverDistanceToDestination =
            (data?['distanceToDestinationMeters'] as num?)?.toInt();
        if (serverTime != null) {
          _clockSkew = serverTime.difference(DateTime.now());
        }
        _isLoadingLocation = false;
      });
      _fetchRoute(force: destinationChanged);
      _fetchRouteToUser();
      _ensureLiveVisible();
    } finally {
      _fetchInFlight = false;
    }
  }

  /// Re-draws the road path from where the person is NOW — but only when
  /// they've moved a meaningful distance or the line is getting old, so we
  /// don't hammer the Directions API every 5 seconds.
  Future<void> _fetchRoute({bool force = false}) async {
    final from = _liveLocation;
    final to = _destinationLocation;
    if (from == null || to == null || _arrivedAt != null) return;
    if (_routeInFlight) return;
    final origin = _routeOrigin;
    final fetchedAt = _routeFetchedAt;
    if (!force && origin != null && fetchedAt != null) {
      final moved = Geolocator.distanceBetween(
          origin.latitude, origin.longitude, from.latitude, from.longitude);
      final age = DateTime.now().difference(fetchedAt);
      if (moved < 50 && age < const Duration(seconds: 45)) return;
    }
    _routeInFlight = true;
    try {
      final walking = Geolocator.distanceBetween(
              from.latitude, from.longitude, to.latitude, to.longitude) <=
          _walkableMeters;
      final route =
          await DirectionsService.route(from: from, to: to, walking: walking);
      if (!mounted) return;
      setState(() {
        _route = route;
        _routeWalking = walking;
        _routeOrigin = from;
        _routeFetchedAt = DateTime.now();
      });
    } catch (e) {
      debugPrint('Route fetch failed: $e');
    } finally {
      _routeInFlight = false;
    }
  }

  /// Road path from THIS contact to the person, refreshed as either of them
  /// moves. Needs the contact's own position; without it the screen offers
  /// Google Maps directions instead (see [_openDirections]).
  Future<void> _fetchRouteToUser({bool force = false}) async {
    final me = _myPosition;
    final them = _liveLocation;
    if (me == null || them == null || _toUserInFlight || _sessionEnded) return;
    final fromOld = _toUserFrom;
    final toOld = _toUserTo;
    final fetchedAt = _toUserFetchedAt;
    if (!force && fromOld != null && toOld != null && fetchedAt != null) {
      final movedMe = Geolocator.distanceBetween(
          fromOld.latitude, fromOld.longitude, me.latitude, me.longitude);
      final movedThem = Geolocator.distanceBetween(
          toOld.latitude, toOld.longitude, them.latitude, them.longitude);
      final age = DateTime.now().difference(fetchedAt);
      if (movedMe < 50 && movedThem < 50 && age < const Duration(seconds: 45)) {
        return;
      }
    }
    _toUserInFlight = true;
    try {
      final walking = Geolocator.distanceBetween(
              me.latitude, me.longitude, them.latitude, them.longitude) <=
          _walkableMeters;
      final route =
          await DirectionsService.route(from: me, to: them, walking: walking);
      if (!mounted) return;
      setState(() {
        _routeToUser = route;
        _toUserWalking = walking;
        _toUserFrom = me;
        _toUserTo = them;
        _toUserFetchedAt = DateTime.now();
      });
    } catch (e) {
      debugPrint('Route to user failed: $e');
    } finally {
      _toUserInFlight = false;
    }
  }

  /// Hands off to Google Maps for turn-by-turn directions from wherever
  /// THIS phone is to where the person is right now. Works even when this
  /// app can't read the contact's own location.
  Future<void> _openDirections() async {
    final live = _liveLocation;
    if (live == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final mode = _toUserWalking ? 'walking' : 'driving';
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${live.latitude},${live.longitude}&travelmode=$mode',
    );
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps.')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open Google Maps.')),
      );
    }
  }

  Future<void> _copyCoordinates() async {
    final live = _liveLocation;
    if (live == null) return;
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(
      text:
          '${live.latitude.toStringAsFixed(6)}, ${live.longitude.toStringAsFixed(6)}',
    ));
    messenger.showSnackBar(
      const SnackBar(content: Text('Location copied.')),
    );
  }

  /// If the person has moved off the visible part of the map, pan to keep
  /// them (and the destination) in view — without fighting a contact who is
  /// simply looking around while the person is still on screen.
  Future<void> _ensureLiveVisible() async {
    final controller = _mapController;
    final live = _liveLocation;
    if (controller == null || live == null) return;
    try {
      final visible = await controller.getVisibleRegion();
      final inside = live.latitude >= visible.southwest.latitude &&
          live.latitude <= visible.northeast.latitude &&
          live.longitude >= visible.southwest.longitude &&
          live.longitude <= visible.northeast.longitude;
      if (inside) return;
      final dest = _destinationLocation;
      final me = _myPosition;
      final points = <LatLng>[live, if (dest != null) dest, if (me != null) me];
      await controller.animateCamera(
        points.length > 1
            ? CameraUpdate.newLatLngBounds(_boundsFor(points), 40)
            : CameraUpdate.newLatLng(live),
      );
    } catch (_) {
      // Map not ready yet / bounds too small — harmless.
    }
  }

  /// Map height: about a third of the screen, never tiny or huge.
  double _mapHeight(BuildContext context) =>
      (MediaQuery.sizeOf(context).height * 0.32).clamp(190.0, 300.0).toDouble();

  /// A column child that is always present. Showing/hiding it changes only
  /// what is inside, never how many children the parent Column has — so the
  /// widgets around the map keep their place in the tree between rebuilds.
  Widget _slot(bool visible, List<Widget> children) => visible
      ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)
      : const SizedBox.shrink();

  // ---- Labels ----

  String _formatMeters(num meters) => meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(1)} km';

  String _ageLabel(DateTime at) {
    final age = _serverNow.difference(at);
    if (age.inSeconds < 10) return 'just now';
    if (age.inSeconds < 60) return '${age.inSeconds}s ago';
    if (age.inMinutes < 60) return '${age.inMinutes} min ago';
    return '${age.inHours} hr ago';
  }

  String _modeLabel(bool walking) => walking ? 'on foot' : 'by car';

  /// How far THIS contact is from the person: road distance and travel time
  /// when the route is known, otherwise the straight-line distance.
  String get _distanceFromMeLabel {
    final me = _myPosition;
    final them = _liveLocation;
    if (them == null) return 'No location yet';
    if (me == null)
      return _myPositionInFlight ? 'Locating you…' : 'Not available';
    final route = _routeToUser;
    if (route != null) {
      return '${route.distanceLabel} · ${route.durationLabel} ${_modeLabel(_toUserWalking)}';
    }
    return '${_formatMeters(Geolocator.distanceBetween(me.latitude, me.longitude, them.latitude, them.longitude))} (straight line)';
  }

  /// Distance and time the PERSON still has to travel to the destination.
  String get _toDestinationLabel {
    if (_arrivedAt != null) return 'Arrived';
    final route = _route;
    if (route != null) {
      return '${route.distanceLabel} · ${route.durationLabel} ${_modeLabel(_routeWalking)}';
    }
    if (_serverDistanceToDestination != null) {
      return _formatMeters(_serverDistanceToDestination!);
    }
    return _destinationLocation == null ? 'Unknown' : 'Calculating…';
  }

  // How fresh the person's location is: green under 30 s, orange up to
  // 5 min, red beyond that — so a stale dot never looks "live".
  int? get _locationAgeSeconds => _locationUpdatedAt == null
      ? null
      : _serverNow.difference(_locationUpdatedAt!).inSeconds;

  static const Color _warningColor = Color(0xFFF59E0B);

  Color get _freshnessColor {
    if (_sessionEnded) return AppColors.textMuted;
    final age = _locationAgeSeconds;
    if (age == null) return _warningColor;
    if (age < 30) return AppColors.success;
    if (age < 300) return _warningColor;
    return AppColors.danger;
  }

  String get _freshnessLabel {
    if (_sessionEnded) return 'Session ended';
    final at = _locationUpdatedAt;
    if (at == null) return 'Waiting for location';
    final age = _locationAgeSeconds ?? 0;
    if (age < 30) return 'Live · ${_ageLabel(at)}';
    if (age < 300) return 'Last seen ${_ageLabel(at)}';
    return 'No signal · last seen ${_ageLabel(at)}';
  }

  String get _overdueLabel {
    final end = _expectedEndAt;
    if (end == null) return '';
    final d = _serverNow.difference(end);
    if (d.inSeconds < 60) return '${d.inSeconds < 0 ? 0 : d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes} min ${d.inSeconds % 60}s';
    return '${d.inHours} hr ${d.inMinutes % 60} min';
  }

  bool get _isOverdue =>
      _expectedEndAt != null &&
      _arrivedAt == null &&
      !_sessionEnded &&
      _serverNow.isAfter(_expectedEndAt!);

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
      destination: _destinationName ?? widget.request.destination,
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final location = _liveLocation;
    final destinationLocation = _destinationLocation;

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
            // The map is pinned above the scrolling details instead of living
            // inside the scroll view. On Flutter web a map inside a scrolling
            // area (that also rebuilds every few seconds) can leave a ghost of
            // the map on screen while the widgets around it vanish.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: _mapHeight(context),
                  width: double.infinity,
                  child: _isLoadingLocation
                      ? Container(
                          color: AppColors.card,
                          alignment: Alignment.center,
                          child: const CircularProgressIndicator(),
                        )
                      : (location != null || destinationLocation != null)
                          ? GoogleMap(
                              key: const ValueKey('alert-detail-map'),
                              onMapCreated: (controller) {
                                _mapController = controller;
                                // Fit both pins in frame when we have
                                // both -- otherwise just center on
                                // whichever one we actually have.
                                if (location != null &&
                                    destinationLocation != null) {
                                  Future.delayed(
                                      const Duration(milliseconds: 200), () {
                                    controller.animateCamera(
                                      CameraUpdate.newLatLngBounds(
                                        _boundsFor(
                                            [location, destinationLocation]),
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
                              polylines: {
                                if (_route != null)
                                  Polyline(
                                    polylineId:
                                        const PolylineId('to-destination'),
                                    points: _route!.points,
                                    width: 4,
                                    color: AppColors.navy,
                                  ),
                                // The line from YOU to the person.
                                if (_routeToUser != null)
                                  Polyline(
                                    polylineId: const PolylineId('to-user'),
                                    points: _routeToUser!.points,
                                    width: 5,
                                    color: const Color(0xFF2F80ED),
                                  )
                                else if (_myPosition != null &&
                                    location != null)
                                  Polyline(
                                    polylineId:
                                        const PolylineId('to-user-straight'),
                                    points: [_myPosition!, location],
                                    width: 3,
                                    color: const Color(0xFF2F80ED),
                                  ),
                              },
                              markers: {
                                if (location != null)
                                  Marker(
                                    markerId: const MarkerId('live'),
                                    position: location,
                                    icon: _liveIcon ??
                                        BitmapDescriptor.defaultMarker,
                                    infoWindow: InfoWindow(
                                        title:
                                            '${request.requesterName} (live)'),
                                  ),
                                if (_myPosition != null)
                                  Marker(
                                    markerId: const MarkerId('me'),
                                    position: _myPosition!,
                                    icon: _meIcon ??
                                        BitmapDescriptor.defaultMarkerWithHue(
                                            BitmapDescriptor.hueAzure),
                                    infoWindow: const InfoWindow(title: 'You'),
                                  ),
                                if (destinationLocation != null)
                                  Marker(
                                    markerId: const MarkerId('destination'),
                                    position: destinationLocation,
                                    icon: _destinationIcon ??
                                        BitmapDescriptor.defaultMarker,
                                    infoWindow:
                                        const InfoWindow(title: 'Destination'),
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
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // How to reach the person: Google Maps directions from
                    // wherever THIS phone is, plus a copyable position.
                    _slot(location != null, [
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _openDirections,
                              icon: const Icon(Icons.directions, size: 18),
                              label: Text(
                                  'Directions to ${request.requesterName}',
                                  overflow: TextOverflow.ellipsis),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2F80ED),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _copyCoordinates,
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('Copy'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.navy,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 14),
                              side: BorderSide(color: AppColors.border),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                    ]),
                    _slot(
                        _myPosition == null &&
                            !_sessionEnded &&
                            location != null,
                        [
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _warningColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.location_disabled,
                                    size: 18, color: _warningColor),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _myPositionInFlight
                                        ? 'Finding your location to draw the line to ${request.requesterName}…'
                                        : (_myPositionProblem ??
                                            'Your location is off, so the line to ${request.requesterName} cannot be drawn. Use Directions above, or turn location on.'),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textPrimary),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _myPositionInFlight
                                      ? null
                                      : _updateMyPosition,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        ]),
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
                                    Flexible(
                                      child: ValueListenableBuilder<int>(
                                        valueListenable: _clockTick,
                                        builder: (context, _, __) => Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: _freshnessColor.withValues(
                                                alpha: 0.14),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            _freshnessLabel,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                                color: _freshnessColor),
                                          ),
                                        ),
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
                                        'Destination: ${_destinationName ?? request.destination}',
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
                                      'Alert sent ${_formatClock(request.requestedAt.toLocal())}',
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

                    // Status banner: arrived / overdue / session ended.
                    _slot(_delayReason != null && !_sessionEnded, [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _warningColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.update, size: 18, color: _warningColor),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${request.requesterName} asked for more time: “$_delayReason”',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ]),
                    ValueListenableBuilder<int>(
                      valueListenable: _clockTick,
                      builder: (context, _, __) => _slot(
                          _arrivedAt != null || _sessionEnded || _isOverdue, [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: (_isOverdue
                                    ? AppColors.danger
                                    : (_arrivedAt != null
                                        ? AppColors.success
                                        : AppColors.textMuted))
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _isOverdue
                                ? '${request.requesterName} is overdue by $_overdueLabel. They were expected by ${_formatClock(_expectedEndAt!.toLocal())}.'
                                : (_arrivedAt != null
                                    ? '${request.requesterName} arrived at ${_destinationName ?? request.destination} at ${_formatClock(_arrivedAt!.toLocal())}.'
                                    : 'This session has ended — location is no longer being shared.'),
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ]),
                    ),

                    // Distance + time, all live.
                    Row(
                      children: [
                        Expanded(
                          child: _InfoTile(
                            icon: Icons.social_distance,
                            label: 'Distance from you',
                            value: _distanceFromMeLabel,
                            color: const Color(0xFF2F80ED),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _InfoTile(
                            icon: Icons.flag_outlined,
                            label: 'To destination',
                            value: _toDestinationLabel,
                            color: AppColors.navy,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _InfoTile(
                            icon: Icons.access_time,
                            label: 'Alert Time',
                            value: _formatClock(request.requestedAt.toLocal()),
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _InfoTile(
                            icon: Icons.hourglass_bottom,
                            label: 'Expected by',
                            value: _expectedEndAt == null
                                ? 'Not set'
                                : _formatClock(_expectedEndAt!.toLocal()),
                            color: _isOverdue
                                ? AppColors.danger
                                : AppColors.success,
                            valueColor: _isOverdue ? AppColors.danger : null,
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

  /// Text colour of the value. Defaults to the normal text colour, so an
  /// error/status message is no longer painted in the icon's (green) colour.
  final Color? valueColor;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.valueColor,
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
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: valueColor ?? AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
