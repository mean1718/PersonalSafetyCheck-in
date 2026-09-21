import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/marker_icons.dart';
import '../services/directions_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/session_record.dart';
import '../models/app_notification.dart';
import '../models/incident.dart';
import '../models/contact_response_state.dart';
import '../services/alert_sound.dart';
import '../models/contact.dart';
import '../models/chat_message.dart';
import '../services/app_session.dart';
import '../services/check_in_service.dart';
import '../services/emergency_service.dart';
import '../services/chat_service.dart';
import '../theme/app_theme.dart';
import 'session_safe_screen.dart';

/// Which contact tier we're currently trying to reach. Escalates
/// main -> secondary -> emergency responders if nobody can be confirmed
/// safe in time. Since this app has no backend, there is no way to detect
/// whether a contact actually *saw* a message — each stage only tracks
/// that its timer ran out, which is the honest limit of a client-only app.
enum _EscalationStage { personal, main, secondary, emergency }

class ActiveSessionScreen extends StatefulWidget {
  const ActiveSessionScreen({super.key});

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  StreamSubscription<Position>? _positionSub;
  GoogleMapController? _mapController;
  BitmapDescriptor? _meIcon;
  BitmapDescriptor? _destIcon;
  bool _markerIconsRequested = false;
  // The real road-following path to the destination — without this the
  // map just drew a straight line cutting through whatever was in between.
  RouteResult? _walkingRoute;
  int _routeRequestId = 0;
  // Pushes the live position to the backend on a fixed interval,
  // independent of GPS movement. The position STREAM alone
  // (distanceFilter: 5) only fires again once the device has physically
  // moved 5+ meters — on a stationary phone, a desk-bound test, or a
  // browser/emulator with a fixed location, that stream fires once (or
  // never again) for the whole session. Combined with the check-in id
  // arriving asynchronously from the backend a moment after the screen
  // opens, that one stream event can easily land before _checkInId is
  // set, and no update is EVER sent afterward. The trusted contact then
  // sees "Location unavailable" for the entire session even though the
  // app itself has a perfectly good GPS fix, because the backend was
  // simply never told what it is. This timer guarantees a fresh push
  // every few seconds regardless of movement, same pattern already used
  // for the separate "share my location with friends" feature.
  Timer? _locationPushTimer;
  // Where/when the route currently on screen was actually drawn from.
  // Without tracking this, the polyline was fetched once off the very
  // first GPS fix (which on web/emulators is often a rough, low-accuracy
  // reading before the real fix comes in) and then never refreshed —
  // meanwhile the blue "me" marker kept moving with every position-stream
  // update, so the line visibly stopped matching where you actually were.
  LatLng? _routeOrigin;
  DateTime? _routeFetchedAt;

  Future<void> _fetchWalkingRoute() async {
    if (_currentPosition == null) return;
    final requestId = ++_routeRequestId;
    final origin = _currentPosition!;
    try {
      final route = await DirectionsService.route(
        from: origin,
        to: _destinationCoords,
        walking: !_drivingMode,
      );
      if (!mounted || requestId != _routeRequestId) return;
      setState(() {
        _walkingRoute = route;
        _routeOrigin = origin;
        _routeFetchedAt = DateTime.now();
      });
    } catch (e) {
      debugPrint('Route fetch failed: $e');
    }
  }

  /// Called on every live position update. Re-requests the road path only
  /// once you've moved far enough (25m) or enough time has passed (20s)
  /// since the last fetch — keeps the drawn line matching your real
  /// position without hammering the Directions API on every 5m GPS tick.
  void _maybeRefreshWalkingRoute() {
    if (_currentPosition == null) return;
    final lastOrigin = _routeOrigin;
    final lastFetchedAt = _routeFetchedAt;
    if (lastOrigin == null || lastFetchedAt == null) {
      _fetchWalkingRoute();
      return;
    }
    final movedMeters = Geolocator.distanceBetween(
      lastOrigin.latitude,
      lastOrigin.longitude,
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );
    final staleFor = DateTime.now().difference(lastFetchedAt);
    if (movedMeters >= 25 || staleFor >= const Duration(seconds: 20)) {
      _fetchWalkingRoute();
    }
  }

  bool _isInitialized = false;

  int _secondsRemaining = 30 * 60;
  // The countdown is driven by these ABSOLUTE times, not by counting down
  // one tick at a time. A `Timer.periodic` that just did `seconds--` stops
  // (or runs slowly) whenever the phone is locked or the app is in the
  // background -- so the clock froze and the "you missed your deadline"
  // alert to trusted contacts never fired on time. Now the remaining time
  // is always recomputed from the real clock, including the instant the app
  // comes back to the foreground.
  DateTime? _sessionEndTime;
  DateTime _stageEndTime = DateTime.now();

  int _secondsUntil(DateTime? t) {
    if (t == null) return 0;
    final ms = t.difference(DateTime.now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  String _destination = 'Central Market';
  String _expectedTimeStr = '';
  LatLng _destinationCoords = const LatLng(11.5696, 104.9210);
  // Whether Session Setup's "Walking / Driving" toggle was set to
  // Driving — read from the navigation arguments; see didChangeDependencies.
  bool _drivingMode = false;

  LatLng? _currentPosition;
  String? _locationStatusMessage;

  bool _emergencyTriggered = false;
  late DateTime _sessionStartedAt;
  bool _hadDelay = false;
  bool _historyLogged = false;

  // Shows the "Trust Confirmed!" popup the first (and only the first)
  // time a trusted contact actually responds this session — never on a
  // fixed delay or just because the session started.
  bool _trustConfirmedDialogShown = false;
  // Separate from the flag above -- that one's for "a contact said Can
  // Help"; this one's for "a contact tapped Mark [me] as Safe", a
  // distinct action with its own popup (see _maybeShowContactConfirmedSafeDialog).
  bool _confirmedSafeDialogShown = false;

  // ---- Backend sync (see services/check_in_service.dart and
  // emergency_service.dart) ----
  // Both are best-effort: every session in this screen already works
  // fully offline/local, so a failed sync (backend not running, not
  // logged in via the backend, etc.) is swallowed rather than shown —
  // it never blocks or changes the local escalation flow above.
  String? _checkInId;
  // If "I'm Safe" is tapped quickly after starting a session, the network
  // call that gives us _checkInId might not have finished yet — this lets
  // _syncSessionEndToBackend wait for it instead of just giving up, which
  // was leaving the session stuck "active" on the server forever (so the
  // contact's alert never cleared, even though Safe really was confirmed).
  Future<String?>? _startBackendCheckInFuture;
  String? _emergencyId;
  bool _emergencyStartInFlight = false;

  // Contacts actually confirmed on the Setup screen for *this* session —
  // escalation must only ever notify these people, never the person's
  // whole friends list regardless of what they picked.
  List<String> _confirmedNotifyContactIds = [];
  List<Contact> get _sessionMainContacts => AppSession.instance
      .contactsByIds(_confirmedNotifyContactIds)
      .where((c) => c.isMainContact)
      .toList();
  List<Contact> get _sessionOtherContacts => AppSession.instance
      .contactsByIds(_confirmedNotifyContactIds)
      .where((c) => !c.isMainContact)
      .toList();

  // ---- Escalation chain ----
  static const int _stageGracePeriodSeconds = 2 * 60; // 2 min per tier

  bool _isAwaitingResponse = false;
  _EscalationStage _stage = _EscalationStage.main;
  int _stageSecondsRemaining = _stageGracePeriodSeconds;
  Timer? _stageTimer;

  // Real trusted contacts actually alerted during this session — used so
  // "I'm Safe" can send a real follow-up chat message only to the people
  // who were genuinely notified, not to everyone.
  final Set<String> _notifiedContactIds = {};
  // Everyone currently being waited on at this escalation stage — a stage
  // times out (or gets an early "can help" response) as a group, not one
  // contact at a time.
  List<Contact> _currentStageTargets = [];

  @override
  void initState() {
    super.initState();
    _sessionStartedAt = DateTime.now();
    WidgetsBinding.instance.addObserver(this);
    // Fresh session — clear any leftover response tracking from a
    // previous alert so Home only ever shows the current one.
    AppSession.instance.clearCurrentAlertResponses();
    // So an early "I can help" response stops further escalation instead
    // of waiting out the full 2-minute stage timer regardless.
    AppSession.instance.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppSession.instance.removeListener(_onSessionChanged);
    _timer?.cancel();
    _stageTimer?.cancel();
    _alertStatusPollTimer?.cancel();
    _positionSub?.cancel();
    _locationPushTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the background/lock screen: catch the clocks up to real
    // time right now (and fire any deadline that passed while away)
    // instead of waiting for a timer that may have been paused.
    if (state != AppLifecycleState.resumed || !mounted) return;
    if (_sessionEndedAsSafe) return;
    if (_timer?.isActive ?? false) _onMainTick();
    final stageTimer = _stageTimer;
    if (stageTimer != null && stageTimer.isActive) {
      _onStageTick(stageTimer, _stage);
    }
  }

  void _onSessionChanged() {
    if (!mounted || !_isAwaitingResponse || _emergencyTriggered) return;
    // Check every contact notified so far this session — not just the
    // current stage's targets — so a "Can Help" that arrives just as it
    // rolls over to the next stage still counts instead of being silently
    // ignored because it's no longer "the current tier".
    if (_notifiedContactIds.isEmpty) return;
    final helper = AppSession.instance.currentAlertResponses.firstWhere(
      (r) =>
          _notifiedContactIds.contains(r.contactId) &&
          r.status == ContactResponseStatus.canHelp,
      orElse: () => ContactResponseState(
          contactId: '',
          contactName: '',
          status: ContactResponseStatus.pending,
          notifiedAt: DateTime.now()),
    );
    if (helper.contactId.isEmpty) return;

    // Someone confirmed they can help — stop escalating.
    _stageTimer?.cancel();
    setState(() => _isAwaitingResponse = false);
    _maybeShowTrustConfirmedDialog();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // BitmapDescriptor.defaultMarkerWithHue doesn't render on web — load
    // real pin images instead, same as every other map screen.
    if (!_markerIconsRequested) {
      _markerIconsRequested = true;
      Future.wait([
        MarkerIcons.me(context),
        MarkerIcons.destination(context),
      ]).then((icons) {
        if (!mounted) return;
        setState(() {
          _meIcon = icons[0];
          _destIcon = icons[1];
        });
      });
    }
    if (_isInitialized) {
      return;
    }
    final dynamic rawArguments = ModalRoute.of(context)?.settings.arguments;

    // RESUME MODE: this screen was reached with no Session Setup
    // arguments at all (e.g. Home's active-session card pushed a bare
    // ActiveSessionScreen()) while AppSession still says a session is
    // active. Before this, that combination either fell through to the
    // hardcoded 11.5696/104.9210 defaults, or — worse — went on to call
    // _startBackendCheckIn() below and silently created a SECOND, brand
    // new backend session on top of the real one still running. This
    // happened whenever the original live screen instance was gone from
    // the Navigator stack for any reason (browser back navigation, the
    // tab losing and re-doing its history, etc.) — Home's card still
    // correctly showed the session as active (AppSession itself was
    // untouched), but tapping it had nothing left to pop back to, and
    // the old fallback just told the person to reopen the app — which
    // didn't actually fix anything either, since reopening lands back on
    // Home with the exact same unreachable "active" session.
    final bool isResume =
        rawArguments is! Map && AppSession.instance.activeCheckInId != null;
    if (isResume) {
      _checkInId = AppSession.instance.activeCheckInId;
      _destination =
          AppSession.instance.activeSessionDestination ?? _destination;
      final endTime = AppSession.instance.activeSessionEndTime;
      if (endTime != null) {
        final remaining = endTime.difference(DateTime.now()).inSeconds;
        _secondsRemaining = remaining > 0 ? remaining : 0;
      }
      _expectedTimeStr = _formatTime(_secondsRemaining);
      final resumePos = AppSession.instance.lastKnownPosition;
      if (resumePos != null) {
        _currentPosition = resumePos;
      }
      _isInitialized = true;
      _sessionEndTime =
          DateTime.now().add(Duration(seconds: _secondsRemaining));
      _startTimer();
      _initLocationTracking();
      // No _startBackendCheckIn() here — that's the whole point of resume
      // mode: the real session (and its backend record) already exists,
      // this just reconnects this screen's timers/polling to it instead
      // of creating a duplicate.
      if (_checkInId != null) {
        CheckInService.alertStatus(_checkInId!)
            .then(_applyAlertStatus)
            .catchError((e) => debugPrint('Alert status sync skipped: $e'));
        _startAlertStatusPolling(_checkInId!);
      }
      _ensureContactsCached();
      return;
    }

    if (rawArguments is Map) {
      _destination =
          rawArguments['destination']?.toString() ?? 'Central Market';
      final dynamic duration = rawArguments['durationSeconds'];
      if (duration is num) {
        _secondsRemaining = duration.toInt();
      }
      _expectedTimeStr = rawArguments['expectedTimeStr']?.toString() ??
          _formatTime(_secondsRemaining);
      // So Home can show a live countdown for this same session even
      // while this screen isn't the one on top (see the back arrow in
      // the AppBar below).
      AppSession.instance.activeSessionEndTime =
          DateTime.now().add(Duration(seconds: _secondsRemaining));
      AppSession.instance.activeSessionDestination = _destination;
      final double latitude =
          (rawArguments['latitude'] as num?)?.toDouble() ?? 11.5696;
      final double longitude =
          (rawArguments['longitude'] as num?)?.toDouble() ?? 104.9210;
      _destinationCoords = LatLng(latitude, longitude);
      // Setup already asked "walking or driving" and sends the answer
      // here — without reading it, this screen always fetched the
      // walking route regardless of what was picked, since
      // _fetchWalkingRoute() used to hardcode walking: true.
      _drivingMode = rawArguments['drivingMode'] == true;
      final dynamic ids = rawArguments['notifyContactIds'];
      // TODO(debug): remove once delivery is confirmed working. Shows the
      // raw value and its type — tells us whether Session Setup ever sent
      // this at all, vs. sent it as the wrong type, vs. sent it empty.
      debugPrint(
          'SafetyU: raw notifyContactIds = $ids (runtimeType: ${ids.runtimeType})');
      if (ids is List) {
        _confirmedNotifyContactIds = ids.map((e) => e.toString()).toList();
        // These people are notified for real the moment the session starts
        // (see _startBackendCheckIn below) — _notifiedContactIds used to
        // only get populated later, during timeout escalation or a manual
        // Need Help tap. That left it completely empty for the entire
        // normal, no-escalation case, which meant "I'm Safe" found nobody
        // to actually message even though real contacts were notified.
        _notifiedContactIds.addAll(_confirmedNotifyContactIds);
        // TODO(debug): remove once delivery is confirmed working.
        debugPrint(
            'SafetyU: session started with notifyContactIds=$_confirmedNotifyContactIds');
      }
    }

    _isInitialized = true;
    _sessionEndTime = DateTime.now().add(Duration(seconds: _secondsRemaining));
    _startTimer();
    _initLocationTracking();
    _startBackendCheckIn();
    _ensureContactsCached();
  }

  // Escalation and manual Need Help both resolve who to message via
  // AppSession.contactsByIds — a local cache normally filled by visiting
  // Friends or Select Contacts. If this screen is reached without that
  // ever having happened, that cache is empty and those flows would
  // silently find nobody to notify. This guarantees it's populated the
  // moment a session actually starts, not just when browsing contacts.
  Future<void> _ensureContactsCached() async {
    try {
      final contacts = await CheckInService.trustedContacts();
      for (final contact in contacts) {
        final userId = contact['userId']?.toString();
        if (userId == null || userId.isEmpty) continue;
        AppSession.instance.upsertContact(Contact(
          id: userId,
          fullName: contact['name']?.toString() ?? 'SafetyU user',
          phone: contact['phone']?.toString() ?? '',
          email: contact['email']?.toString() ?? '',
          relationship: 'Trusted Contact',
          status: ContactStatus.friend,
          tierAssigned: false,
        ));
      }
    } catch (e) {
      debugPrint('Contact cache refresh skipped: $e');
    }
  }

  // =========================================================
  // BACKEND SYNC — check-in + emergency escalation
  // =========================================================

  void _startBackendCheckIn() {
    final pos = AppSession.instance.lastKnownPosition;
    _startBackendCheckInFuture = CheckInService.start(
      contactUserIds: _confirmedNotifyContactIds,
      message: 'Safety session to $_destination',
      destinationName: _destination,
      expectedEndAt: _sessionEndTime,
      latitude: pos?.latitude,
      longitude: pos?.longitude,
      // So a trusted contact's Alert Detail screen can show where this
      // session was actually headed, not just the live-moving position.
      destinationLatitude: _destinationCoords.latitude,
      destinationLongitude: _destinationCoords.longitude,
    ).then((id) {
      if (mounted) {
        _checkInId = id;
        AppSession.instance.activeCheckInId = id;
        if (id != null) {
          // Don't wait for the next periodic tick — if a GPS fix is
          // already sitting in _currentPosition, get it to the backend
          // the moment we actually have somewhere to send it to.
          _pushLocationToBackend();
          CheckInService.alertStatus(id)
              .then(_applyAlertStatus)
              .catchError((e) => debugPrint('Alert status sync skipped: $e'));
          _startAlertStatusPolling(id);
        }
      }
      return id;
    }).catchError((e) {
      debugPrint('CheckIn sync skipped: $e');
      return null;
    });
  }

  /// Applies one GET /alert-status payload: updates the per-contact
  /// responses AppSession already tracks, and separately checks for a
  /// fresh confirmedSafeBy -- shared by every call site below instead of
  /// duplicating this each time.
  void _applyAlertStatus(Map<String, dynamic> data) {
    AppSession.instance.replaceAlertResponsesFromBackend(
        CheckInService.notifiedContactsFrom(data));
    final confirmedSafeBy = data['confirmedSafeBy'] as Map<String, dynamic>?;
    if (confirmedSafeBy != null) {
      _maybeShowContactConfirmedSafeDialog(
          confirmedSafeBy['name']?.toString() ?? 'Your trusted contact');
    }
  }

  // Without this, a contact's real "I can help" only ever gets pulled in
  // at session start and (later) when Emergency escalation kicks off — so
  // a response sent in between was invisible to this screen the whole
  // time, and the "stop escalating once someone confirms" logic below
  // could never actually see it happen. Every few seconds is frequent
  // enough to feel real without hammering the server.
  Timer? _alertStatusPollTimer;
  void _startAlertStatusPolling(String checkInId) {
    _alertStatusPollTimer?.cancel();
    _alertStatusPollTimer =
        Timer.periodic(const Duration(seconds: 6), (_) async {
      if (!mounted) return;
      try {
        final data = await CheckInService.alertStatus(checkInId);
        if (!mounted) return;
        final wasConfirmed = _someoneConfirmedHelp();
        _applyAlertStatus(data);
        if (!wasConfirmed && _someoneConfirmedHelp()) {
          // A response just came in — stop whatever escalation is running
          // right now rather than waiting for its own timer to notice.
          _stageTimer?.cancel();
          setState(() {});
          _maybeShowTrustConfirmedDialog();
        }
      } catch (e) {
        debugPrint('Alert status poll skipped: $e');
      }
    });
  }

  /// Creates the backend Emergency record the first time this session
  /// actually escalates (main, secondary, or the final emergency tier —
  /// whichever happens first). Safe to call more than once; only the
  /// first call does anything.
  Future<void> _ensureEmergencyStarted() async {
    if (_emergencyId != null || _emergencyStartInFlight) return;
    _emergencyStartInFlight = true;
    try {
      final pos = _currentPosition ?? AppSession.instance.lastKnownPosition;
      final id = await EmergencyService.start(
        checkInId: _checkInId ?? '',
        message: 'Needs help near $_destination',
        latitude: pos?.latitude,
        longitude: pos?.longitude,
      );
      _emergencyId = id;
      // Replace the temporary local rows with the backend's notification
      // recipients. This is the point where the actual notified account is
      // known, so Home can never substitute the session owner.
      if (_checkInId != null) {
        final data = await CheckInService.alertStatus(_checkInId!);
        _applyAlertStatus(data);
      }
    } catch (e) {
      debugPrint('Emergency sync skipped: $e');
    } finally {
      _emergencyStartInFlight = false;
    }
  }

  Future<void> _syncEscalationToBackend(_EscalationStage stage) async {
    try {
      await _ensureEmergencyStarted();
      if (stage == _EscalationStage.secondary && _emergencyId != null) {
        await EmergencyService.escalateToSecondary(_emergencyId!);
      }
    } catch (e) {
      debugPrint('Emergency escalation sync skipped: $e');
    }
  }

  Future<void> _syncFinalEscalationToBackend() async {
    try {
      await _ensureEmergencyStarted();
      if (_emergencyId != null) {
        await EmergencyService.escalateToEmergency(_emergencyId!);
      }
    } catch (e) {
      debugPrint('Emergency escalation sync skipped: $e');
    }
  }

  Future<void> _syncSessionEndToBackend() async {
    try {
      if (_emergencyId != null) {
        await EmergencyService.resolve(_emergencyId!);
      }
      // The network call that gives us _checkInId may still be in flight
      // if Safe was tapped right after starting — wait for it (briefly)
      // rather than concluding there's no session to complete.
      _checkInId ??= await _startBackendCheckInFuture?.timeout(
        const Duration(seconds: 8),
        onTimeout: () => null,
      );
      if (_checkInId != null) {
        await CheckInService.complete(_checkInId!);
      }
    } catch (e) {
      debugPrint('Session-end sync skipped: $e');
    }
  }

  // =========================================================
  // COUNTDOWN
  // =========================================================

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _onMainTick());
  }

  void _onMainTick() {
    if (!mounted) {
      _timer?.cancel();
      return;
    }
    final left = _secondsUntil(_sessionEndTime);
    if (left > 0) {
      if (left != _secondsRemaining) setState(() => _secondsRemaining = left);
      return;
    }
    _timer?.cancel();
    setState(() => _secondsRemaining = 0);
    if (!_isAwaitingResponse && !_emergencyTriggered) {
      // Give the session owner themselves a 2-minute window to confirm
      // they're safe BEFORE anyone else is told anything — trusted
      // contacts used to be alerted the instant the countdown hit zero,
      // with no chance for the owner to just tap "I'm Safe" a moment
      // late. _EscalationStage.personal notifies nobody; _onStageTick
      // below moves on to the real first alert (.main) only if this
      // grace period runs out too.
      _enterEscalation(_EscalationStage.personal);
    }
  }

  // Guards _endSessionAsSafe against running twice — e.g. the owner taps
  // "I'm Safe" at roughly the same moment a trusted contact's confirm-safe
  // poll comes back, or the confirm-safe dialog's own 30s timer fires
  // after the owner already ended it manually.
  bool _sessionEndedAsSafe = false;

  void _confirmSafe() {
    _endSessionAsSafe(navigateToSafeScreen: true);
  }

  // The actual "this session is over, mark it safe" logic — shared by the
  // owner tapping "I'm Safe" themselves AND a trusted contact confirming
  // them safe from their own side (see _maybeShowContactConfirmedSafeDialog
  // below). Before this, a contact's confirmation only ever showed a
  // reassurance popup on the owner's screen — the session itself, and
  // Home's "SESSION ACTIVE" card, stayed active until the owner also
  // separately tapped "I'm Safe" themselves.
  Future<void> _endSessionAsSafe({required bool navigateToSafeScreen}) async {
    if (_sessionEndedAsSafe) return;
    _sessionEndedAsSafe = true;

    _timer?.cancel();
    _stageTimer?.cancel();
    _alertStatusPollTimer?.cancel();
    _logHistory(SessionOutcome.safe);
    _syncSessionEndToBackend();

    // One last check for anyone who responded (e.g. "Can Help") in the
    // gap between the last 6s poll and right now -- without this, Home's
    // "Your Alert Status" froze on whatever it last happened to see,
    // showing a contact as still "Waiting..." forever even after they'd
    // already responded, simply because nothing ever asked again after
    // this exact moment. Best-effort and bounded, so a slow/offline
    // backend can't delay actually ending the session.
    if (_checkInId != null) {
      try {
        final data = await CheckInService.alertStatus(_checkInId!)
            .timeout(const Duration(seconds: 4));
        _applyAlertStatus(data);
      } catch (e) {
        debugPrint('Final alert status refresh skipped: $e');
      }
    }

    // This session is over, so stop re-fetching/polling it — but keep
    // who-was-notified visible on Home as a "Safe" confirmation instead
    // of silently disappearing. It's cleared for real the next time a
    // new session starts (see clearCurrentAlertResponses in initState).
    AppSession.instance.activeCheckInId = null;
    AppSession.instance.activeSessionEndTime = null;
    AppSession.instance.activeSessionDestination = null;
    if (AppSession.instance.currentAlertResponses.isNotEmpty) {
      AppSession.instance.markCurrentSessionSafe();
    } else {
      AppSession.instance.clearCurrentAlertResponses();
    }

    // Tell every trusted contact who was actually alerted during this
    // session that the person is safe now — a real chat message, not just
    // an in-app log. This sends straight to the real, backend-confirmed
    // ids from session start — not filtered through AppSession.friends,
    // which is just a local cache that may not be populated yet if this
    // screen hasn't been visited recently, silently sending to nobody.
    for (final contactId in _notifiedContactIds) {
      _sendRealChatMessage(
        contactId,
        "I'm safe now. Thanks for checking on me!",
        kind: ChatMessageKind.safeCheckIn,
        backendKind: 'safeCheckIn',
      );
    }

    if (!navigateToSafeScreen || !mounted) return;

    final notifiedNames = AppSession.instance.friends
        .where((c) => _notifiedContactIds.contains(c.id))
        .map((c) => c.fullName)
        .toList();
    final String? contactName = notifiedNames.isEmpty
        ? null
        : notifiedNames.length == 1
            ? notifiedNames.first
            : notifiedNames.length == 2
                ? '${notifiedNames[0]} and ${notifiedNames[1]}'
                : '${notifiedNames[0]} and ${notifiedNames.length - 1} others';
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
          builder: (_) => SessionSafeScreen(notifiedContactName: contactName)),
    );
  }

  void _logHistory(SessionOutcome outcome) {
    if (_historyLogged) {
      return;
    }
    _historyLogged = true;
    AppSession.instance.addSessionRecord(
      SessionRecord(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        destination: _destination,
        startedAt: _sessionStartedAt,
        endedAt: DateTime.now(),
        outcome: outcome,
        hadDelay: _hadDelay,
      ),
    );
  }

  // =========================================================
  // ESCALATION CHAIN: main -> secondary -> emergency
  // =========================================================

  void _enterEscalation(_EscalationStage stage) {
    if (!mounted || _emergencyTriggered) {
      return;
    }
    if (_someoneConfirmedHelp()) {
      // Someone's already on the way — escalating further (notifying more
      // people, or going to Emergency Responders) would be noise, not
      // safety. Stop the chain here and just wait for the session to be
      // resolved normally.
      _stageTimer?.cancel();
      setState(() {});
      return;
    }
    setState(() {
      _isAwaitingResponse = true;
      _stage = stage;
      _stageSecondsRemaining = _stageGracePeriodSeconds;
      _stageEndTime =
          DateTime.now().add(const Duration(seconds: _stageGracePeriodSeconds));
    });

    // Real alert feedback so the person notices even if the phone is face
    // down or they've stepped away — more urgent pulses at each escalation.
    AlertSoundService.playAlert(
        times: stage == _EscalationStage.emergency ? 5 : 3);

    _notifyStage(stage);

    if (stage == _EscalationStage.emergency) {
      _escalateToEmergencyResponders();
      return;
    }

    // No backend Emergency record yet during the personal grace period —
    // nobody's been notified, so there's nothing real to escalate. That
    // starts for real once .main actually fires below.
    if (stage != _EscalationStage.personal) {
      _syncEscalationToBackend(stage);
    }
    _stageTimer?.cancel();
    _stageTimer = Timer.periodic(
      const Duration(seconds: 1),
      (Timer timer) => _onStageTick(timer, stage),
    );
  }

  void _onStageTick(Timer timer, _EscalationStage stage) {
    if (!mounted) {
      timer.cancel();
      return;
    }
    if (_someoneConfirmedHelp()) {
      // Don't wait for this stage's countdown to run out — the moment
      // anyone confirms, stop ticking toward the next, louder stage.
      timer.cancel();
      setState(() {});
      return;
    }
    final left = _secondsUntil(_stageEndTime);
    if (left > 0) {
      if (left != _stageSecondsRemaining) {
        setState(() => _stageSecondsRemaining = left);
      }
      return;
    }
    timer.cancel();
    // Nobody at this stage responded in time — record that on Home for
    // every one of them, not just one, before moving on.
    for (final target in _currentStageTargets) {
      AppSession.instance.markContactTimedOut(target.id);
    }
    final next = switch (stage) {
      // Grace period ran out with no response — this is the real first
      // alert to trusted contacts, exactly the old flow from here on.
      _EscalationStage.personal => _EscalationStage.main,
      _EscalationStage.main => _EscalationStage.secondary,
      _EscalationStage.secondary => _EscalationStage.emergency,
      _EscalationStage.emergency => _EscalationStage.emergency,
    };
    _enterEscalation(next);
  }

  bool _someoneConfirmedHelp() => AppSession.instance.currentAlertResponses
      .any((r) => r.status == ContactResponseStatus.canHelp);

  // The popup itself. Its message only ever gets shown from the two call
  // sites above — both of which only fire once currentAlertResponses has
  // actually flipped a contact to "canHelp" — so there's no path where
  // this appears before a trusted contact has genuinely responded.
  void _maybeShowTrustConfirmedDialog() {
    if (_trustConfirmedDialogShown || !mounted) return;
    _trustConfirmedDialogShown = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // No "OK" button — this is a quick reassurance, not a decision
        // the person needs to make, so it clears itself on its own.
        Future.delayed(const Duration(seconds: 4), () {
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
        });
        return Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check, color: AppColors.success, size: 32),
                ),
                const SizedBox(height: 18),
                Text('Trust Confirmed!',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 10),
                Text(
                  'Your trusted contact has confirmed your alert. They are now aware that you are safe.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.4),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // The dialog shown when a trusted contact taps "Mark [me] as Safe" on
  // their side (see confirmContactSafe / _applyAlertStatus above) -- a
  // distinct action from confirming "Can Help", so it gets its own popup
  // rather than reusing _maybeShowTrustConfirmedDialog's text.
  void _maybeShowContactConfirmedSafeDialog(String contactName) {
    if (_confirmedSafeDialogShown || !mounted) return;
    _confirmedSafeDialogShown = true;
    // A trusted contact confirming the owner safe now actually ends this
    // session too — not just a reassurance popup. Without this, the
    // session (and Home's "SESSION ACTIVE" card) stayed active until the
    // owner ALSO separately tapped "I'm Safe" themselves.
    // navigateToSafeScreen: false — the dialog below handles its own
    // "show then go to Home" flow instead of the usual SessionSafeScreen
    // handoff that a manual "I'm Safe" tap gets.
    _endSessionAsSafe(navigateToSafeScreen: false);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // Shown for 10s, then closes itself AND takes the person to Home —
        // same "peek" push used by the back arrow, so the session itself
        // just keeps running underneath rather than being ended by this.
        Future.delayed(const Duration(seconds: 10), () {
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
          if (mounted) {
            Navigator.of(context).pushNamed('/home');
          }
        });
        return Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check, color: AppColors.success, size: 32),
                ),
                const SizedBox(height: 18),
                Text('Trust confirm you safe!',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 10),
                Text(
                  'Your trusted contact has confirmed you are safe. You are now aware that you are safe.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.4),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // thread — the trusted contact never actually received "Need Help" or
  // "I'm Safe" at all, they were only ever visible on the sender's own
  // phone. This sends the real message too, so it actually reaches them.
  void _sendRealChatMessage(String contactId, String text,
      {required ChatMessageKind kind, required String backendKind}) {
    AppSession.instance.sendChatMessage(contactId, text, kind: kind);
    ChatService.send(
      contactId,
      text,
      kind: backendKind,
      // Links the safety_alert Notification this creates back to this
      // session's real CheckIn — see chat_service.dart / ChatController.js.
      // Without this, the alert generated from THIS message (its exact
      // text is what shows on Alert Detail) could never resolve a live
      // location, no matter what the contact's screen tried to fetch.
      checkInId: backendKind == 'helpRequest' ? _checkInId : null,
    ).catchError((e) {
      debugPrint('Chat delivery skipped: $e');
    });
  }

  String? _confirmedHelperName() {
    for (final r in AppSession.instance.currentAlertResponses) {
      if (r.status == ContactResponseStatus.canHelp) return r.contactName;
    }
    return null;
  }

  Future<void> _notifyStage(_EscalationStage stage) async {
    if (stage == _EscalationStage.personal) {
      // Nobody is notified during the owner's own 2-minute grace period —
      // that's the entire point of this stage. _onStageTick moves on to
      // _EscalationStage.main (the real first alert) once its timer runs
      // out with still no response.
      _currentStageTargets = [];
      return;
    }
    List<Contact> targets;
    if (stage == _EscalationStage.main) {
      targets = _sessionMainContacts;
    } else if (stage == _EscalationStage.secondary) {
      targets = _sessionOtherContacts;
    } else {
      targets = [];
    }

    if (stage != _EscalationStage.emergency && targets.isEmpty) {
      // Nobody confirmed at this tier for this session — skip straight to
      // the next one instead of waiting out a timer for nobody.
      final next = stage == _EscalationStage.main
          ? _EscalationStage.secondary
          : _EscalationStage.emergency;
      if (mounted) {
        _enterEscalation(next);
      }
      return;
    }

    _currentStageTargets = targets;

    // Everyone at this tier is alerted at the same time. A real per-contact
    // OS Share sheet would mean tapping through N separate popups with no
    // user interaction expected, so the automatic broadcast lives entirely
    // inside the app (an in-app notification + a chat message carrying a
    // live location link) — the same "delivery" a push/SMS backend would
    // provide, which this build doesn't have. The manual "Share My
    // Location" button still opens the real OS share sheet for when the
    // person wants to send it somewhere themselves.
    final LatLng? position =
        _currentPosition ?? AppSession.instance.lastKnownPosition;
    final String? mapsUrl = position != null
        ? 'https://maps.google.com/?q=${position.latitude},${position.longitude}'
        : null;
    final String locationLine = mapsUrl != null
        ? '\nMy live location: $mapsUrl'
        : '\n(Location unavailable right now.)';

    for (var i = 0; i < targets.length; i++) {
      final target = targets[i];
      AppSession.instance.registerContactNotified(target);
      AppSession.instance.addNotification(
        title: target.fullName,
        body: 'Alerted about your safety session near $_destination.',
        kind: NotificationKind.trustedContact,
      );
      _notifiedContactIds.add(target.id);
      // The actual push/chat delivery to each contact is staggered 5s
      // apart (fire-and-forget, not awaited) so several contacts don't
      // all buzz at the exact same instant, which read as one confusing
      // simultaneous alert rather than distinct notifications. Everything
      // above this — the local "notified" state, the in-app notification,
      // and the needHelpNow call right below — stays immediate and
      // unstaggered on purpose: none of that should ever wait on a
      // network delay during an actual emergency escalation.
      final text =
          "I need help! I haven't checked in near $_destination.$locationLine\nCan you help?";
      Future.delayed(Duration(seconds: 5 * i), () {
        if (!mounted) return;
        _sendRealChatMessage(
          target.id,
          text,
          kind: ChatMessageKind.helpRequest,
          backendKind: 'helpRequest',
        );
      });
    }
    // A real, fresh alert — not just a chat message — so it actually shows
    // up on each contact's Home screen even if they already answered the
    // original session-start notification.
    if (_checkInId != null && targets.isNotEmpty) {
      CheckInService.needHelpNow(_checkInId!, targets.map((t) => t.id).toList())
          .catchError((e) => debugPrint('Need-help re-alert skipped: $e'));
    }

    if (_confirmedNotifyContactIds.isEmpty && stage == _EscalationStage.main) {
      AppSession.instance.addNotification(
        title: 'SafetyU System',
        body:
            'No trusted contacts were confirmed for this session — escalating to Emergency Responders.',
        kind: NotificationKind.escalation,
      );
    }
  }

  void _escalateToEmergencyResponders() {
    if (_emergencyTriggered) {
      return;
    }
    _emergencyTriggered = true;
    _stageTimer?.cancel();
    _logHistory(SessionOutcome.sos);
    _syncFinalEscalationToBackend();

    final position = _currentPosition ??
        AppSession.instance.lastKnownPosition ??
        _destinationCoords;
    final isStale = _currentPosition == null;

    AppSession.instance.addIncident(
      Incident(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        personName: AppSession.instance.fullName.isEmpty
            ? 'SafetyU User'
            : AppSession.instance.fullName,
        phone: AppSession.instance.phone,
        destination: _destination,
        location: position,
        startedAt: _sessionStartedAt,
        locationIsStale: isStale,
        notifiedContactIds: _notifiedContactIds.toList(),
      ),
    );

    AppSession.instance.addNotification(
      title: 'SafetyU System',
      body: 'No confirmation received — escalated to Emergency Responders.',
      kind: NotificationKind.escalation,
    );

    if (!mounted) {
      return;
    }
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Escalated to Emergency Responders with your location.'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 5),
      ),
    );

    _shareLocation();
  }

  // =========================================================
  // NEED HELP — manual override, skips straight to final escalation
  // =========================================================

  void _triggerEmergencyAlert() {
    _stageTimer?.cancel();
    AlertSoundService.playAlert(times: 5);
    if (mounted) {
      setState(() {
        _isAwaitingResponse = true;
        _stage = _EscalationStage.emergency;
      });
    }

    // Manual "Need Help" skips the timed main/secondary stages, but every
    // main contact should still get a real chat alert, not just Emergency
    // Responders.
    final mains = _sessionMainContacts;
    _currentStageTargets = mains;
    final LatLng? position =
        _currentPosition ?? AppSession.instance.lastKnownPosition;
    final String locationLine = position != null
        ? '\nMy live location: https://maps.google.com/?q=${position.latitude},${position.longitude}'
        : '\n(Location unavailable right now.)';
    for (var i = 0; i < mains.length; i++) {
      final main = mains[i];
      AppSession.instance.registerContactNotified(main);
      AppSession.instance.addNotification(
        title: main.fullName,
        body: 'Alerted about your safety session near $_destination.',
        kind: NotificationKind.trustedContact,
      );
      _notifiedContactIds.add(main.id);
      final text =
          "I need help right now near $_destination.$locationLine\nCan you help?";
      Future.delayed(Duration(seconds: 5 * i), () {
        if (!mounted) return;
        _sendRealChatMessage(
          main.id,
          text,
          kind: ChatMessageKind.helpRequest,
          backendKind: 'helpRequest',
        );
      });
    }
    if (_checkInId != null && mains.isNotEmpty) {
      CheckInService.needHelpNow(_checkInId!, mains.map((c) => c.id).toList())
          .catchError((e) => debugPrint('Need-help re-alert skipped: $e'));
    }

    _escalateToEmergencyResponders();
  }

  // =========================================================
  // LOCATION
  // =========================================================

  /// Cambodia's real national police number (117) — verified, not guessed.
  /// This never auto-dials on its own; it only opens the phone dialer when
  /// the person themselves taps the button, same as any other emergency
  /// call. If this app ever supports other countries, this needs to become
  /// location-aware rather than a single hardcoded number.
  Future<void> _callPolice() async {
    final uri = Uri(scheme: 'tel', path: '117');
    try {
      final launched = await launchUrl(uri);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the dialer.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the dialer.')),
        );
      }
    }
  }

  void _pushLocationToBackend() {
    final checkInId = _checkInId;
    // Fall back to the last position the app ever got: if the live GPS
    // fix is slow (or the person is standing still, so the movement
    // stream stays quiet), contacts still get a fresh "last seen" time
    // instead of a location that silently goes stale for minutes.
    final position = _currentPosition ?? AppSession.instance.lastKnownPosition;
    if (checkInId == null || position == null) return;
    CheckInService.updateLocation(
      checkInId,
      latitude: position.latitude,
      longitude: position.longitude,
    ).catchError((e) => debugPrint('Location sync skipped: $e'));
  }

  Future<void> _initLocationTracking() async {
    // Start the 8-second location heartbeat FIRST. It used to start only
    // at the very end, so any early exit below (permission prompt, slow
    // first GPS fix, a browser that answers late) meant the timer never
    // started and the trusted contact saw "last seen 4 min ago" forever.
    _locationPushTimer?.cancel();
    _locationPushTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _pushLocationToBackend(),
    );

    // Seed the road route immediately from whatever position Session
    // Setup already had (it just got its own GPS fix a few seconds ago to
    // show its own route preview) rather than waiting on a brand new
    // high-accuracy fix below, which can legitimately take up to 20s on
    // web/emulators. Without this, the map showed nothing but a straight
    // line — or nothing at all — for the first chunk of every session,
    // which is most of a short test session. The real fix below still
    // runs right after and any meaningful movement will refresh it via
    // _maybeRefreshWalkingRoute.
    if (_currentPosition == null) {
      final seed = AppSession.instance.lastKnownPosition;
      if (seed != null) {
        setState(() => _currentPosition = seed);
        _fetchWalkingRoute();
      }
    }

    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _setLocationStatus(
            'Turn on location services to share your live position.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _setLocationStatus(
              'Location permission denied. Live tracking is off.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _setLocationStatus(
            'Location permission is permanently denied. Enable it in system settings.');
        return;
      }

      // A slow first GPS fix must NOT switch live sharing off: if it
      // fails or times out we still subscribe to the position stream
      // below, which delivers the first fix whenever it arrives.
      try {
        final Position initial = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 20),
        );
        if (!mounted) {
          return;
        }
        final initialLatLng = LatLng(initial.latitude, initial.longitude);
        setState(() {
          _currentPosition = initialLatLng;
          _locationStatusMessage = null;
        });
        AppSession.instance.updateLastKnownPosition(initialLatLng);
        _fetchWalkingRoute();

        try {
          _mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(_currentPosition!, 15.0),
          );
        } catch (_) {}
      } catch (e) {
        debugPrint('[ACTIVE] First GPS fix not ready yet: $e');
        _setLocationStatus('Still looking for your GPS position…');
      }
      if (!mounted) {
        return;
      }

      _positionSub?.cancel();
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, distanceFilter: 5),
      ).listen(
        (Position position) {
          if (!mounted) {
            return;
          }
          final latLng = LatLng(position.latitude, position.longitude);
          setState(() {
            _currentPosition = latLng;
            _locationStatusMessage = null;
          });
          // Keep the last-known-position cache fresh on every real fix, so
          // if GPS/connectivity drops right before an escalation, we still
          // have a real (if slightly old) location to send instead of
          // nothing at all.
          AppSession.instance.updateLastKnownPosition(latLng);
          _maybeRefreshWalkingRoute();
          if (_checkInId != null) {
            CheckInService.updateLocation(
              _checkInId!,
              latitude: position.latitude,
              longitude: position.longitude,
            ).catchError((e) => debugPrint('Location sync skipped: $e'));
          }
        },
        onError: (Object error) {
          debugPrint('[ACTIVE] Location stream error: $error');
          _setLocationStatus(
              'Lost live location — using your last known position.');
        },
      );
    } catch (e) {
      debugPrint('[ACTIVE] Location initialization error: $e');
      _setLocationStatus('Could not get your current location.');
    }
  }

  void _setLocationStatus(String message) {
    if (!mounted) {
      return;
    }
    setState(() => _locationStatusMessage = message);
  }

  /// Lightweight connectivity check using only dart:io — no extra package
  /// needed. Not perfectly reliable on every network config, but good
  /// enough to tell "clearly offline" from "clearly online".
  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('example.com')
          .timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // =========================================================
  // SHARE LOCATION
  // =========================================================

  Future<void> _shareLocation({Contact? specificContact}) async {
    LatLng? position = _currentPosition;
    bool isStale = false;

    if (position == null) {
      position = AppSession.instance.lastKnownPosition;
      isStale = position != null;
    }

    if (position == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Still getting your location. Please try again in a moment.')),
      );
      return;
    }

    final online = await _hasInternet();

    final String mapsUrl =
        'https://maps.google.com/?q=${position.latitude},${position.longitude}';
    final contact = specificContact ?? AppSession.instance.mainContact;
    final String greeting = contact != null ? 'Hi ${contact.fullName}, ' : '';

    final String staleNote = isStale &&
            AppSession.instance.lastKnownPositionAt != null
        ? '\n(Last known location as of ${_formatClock(AppSession.instance.lastKnownPositionAt!)} — live signal was unavailable.)'
        : '';

    final String offlineNote = online
        ? ''
        : "\n\nNote: you're currently offline. This will send automatically through your Messages app once you're back online.";

    await Share.share(
      '$greeting'
      'I\'m heading to $_destination.\n\n'
      'My name: ${AppSession.instance.fullName.isEmpty ? "SafetyU User" : AppSession.instance.fullName}\n'
      'My phone: ${AppSession.instance.phone}\n\n'
      'Location:\n$mapsUrl$staleNote\n\n'
      'Time remaining: ${_formatTime(_secondsRemaining)}$offlineNote',
      subject: 'SafetyU Safety Session',
    );

    if (!online && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "You're offline — sharing through your phone's native Share sheet, which will deliver once reconnected.")),
      );
    }
  }

  String _formatTime(int seconds) {
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    final int secs = seconds % 60;
    final String minutesString = minutes.toString().padLeft(2, '0');
    final String secondsString = secs.toString().padLeft(2, '0');
    if (hours > 0) {
      final String hoursString = hours.toString().padLeft(2, '0');
      return '$hoursString:$minutesString:$secondsString';
    }
    return '$minutesString:$secondsString';
  }

  String _formatClock(DateTime t) {
    final hour24 = t.hour;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $period';
  }

  String _formatClockFromNow(int secondsFromNow) {
    return _formatClock(DateTime.now().add(Duration(seconds: secondsFromNow)));
  }

  // =========================================================
  // UI
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final String appBarTitle =
        _hadDelay ? 'Delay Session Active' : 'Safety Session Active';

    return PopScope(
      // The countdown, escalation, and alert-status polling all live on
      // this screen's State — if it gets popped (back button/gesture),
      // dispose() cancels every one of those timers and the whole safety
      // session silently stops running, even though the backend still
      // thinks it's active. Blocking back here is what keeps it running;
      // I'm Safe / Need Help / Request Delay are the only real exits.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "Your safety session is still active. Use I'm Safe or Need Help to end it."),
          ),
        );
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
            tooltip: 'Back to Home',
            // This does NOT end or pause the session -- it pushes a fresh
            // Home screen ON TOP of this one, so this screen (and every
            // timer/poll it's running) stays alive, untouched, right where
            // it is underneath. Tapping the live countdown card on that
            // Home screen pops back to reveal this exact screen again.
            // A real pop here would dispose this State and silently kill
            // the session (see the PopScope comment below) -- that's why
            // this pushes instead of popping.
            onPressed: () => Navigator.of(context).pushNamed('/home'),
          ),
          title: Text(appBarTitle,
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              icon: Icon(Icons.share_location, color: AppColors.navy),
              tooltip: 'Share my live location',
              onPressed: () => _shareLocation(),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                if (_isAwaitingResponse)
                  _EscalationBanner(
                    stage: _stage,
                    sosSent: _emergencyTriggered,
                    helpConfirmedBy: _confirmedHelperName(),
                    onCallPolice: _callPolice,
                  )
                else
                  Container(
                    height: 260,
                    width: double.infinity,
                    margin: const EdgeInsets.all(20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: GoogleMap(
                        onMapCreated: (c) => _mapController = c,
                        initialCameraPosition: CameraPosition(
                            target: _currentPosition ?? _destinationCoords,
                            zoom: 15.0),
                        polylines: _walkingRoute != null
                            ? {
                                Polyline(
                                  polylineId:
                                      const PolylineId('to-destination'),
                                  points: _walkingRoute!.points,
                                  width: 4,
                                  color: AppColors.navy,
                                ),
                              }
                            : _currentPosition == null
                                ? {}
                                : {
                                    Polyline(
                                      polylineId:
                                          const PolylineId('to-destination'),
                                      points: [
                                        _currentPosition!,
                                        _destinationCoords,
                                      ],
                                      width: 3,
                                      color:
                                          AppColors.navy.withValues(alpha: 0.4),
                                    ),
                                  },
                        markers: {
                          Marker(
                            markerId: const MarkerId('destination'),
                            position: _destinationCoords,
                            icon: _destIcon ?? BitmapDescriptor.defaultMarker,
                          ),
                          if (_currentPosition != null)
                            Marker(
                              markerId: const MarkerId('me'),
                              position: _currentPosition!,
                              icon: _meIcon ?? BitmapDescriptor.defaultMarker,
                            ),
                        },
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 22, bottom: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _formatTime(_secondsRemaining),
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w800,
                          color: _isAwaitingResponse
                              ? AppColors.textMuted
                              : AppColors.navy,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Count Down Time',
                          style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: AppColors.border.withValues(alpha: 0.5)))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_destination,
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 4),
                      Text(
                        _hadDelay
                            ? 'Expected arrival with delay: $_expectedTimeStr'
                            : 'Expected arrival: $_expectedTimeStr',
                        style: TextStyle(
                            fontSize: 12.5, color: AppColors.textSecondary),
                      ),
                      if (_locationStatusMessage != null) ...[
                        const SizedBox(height: 5),
                        Text(_locationStatusMessage!,
                            style: const TextStyle(
                                fontSize: 11.5, color: Colors.redAccent)),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _confirmSafe,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryButton,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(26)),
                          ),
                          child: const Text("I'm Safe",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton(
                          onPressed: () async {
                            final dynamic result = await Navigator.pushNamed(
                              context,
                              '/request-delay',
                              arguments: <String, dynamic>{
                                'remainingSeconds': _secondsRemaining,
                                'destination': _destination
                              },
                            );
                            if (!mounted) {
                              return;
                            }
                            if (result is Map) {
                              final int extraSeconds =
                                  result['extraSeconds'] as int? ?? 0;
                              final String? newDestination =
                                  result['destination'] as String?;
                              final String? delayReason =
                                  result['reason'] as String?;
                              final double? newLat =
                                  (result['latitude'] as num?)?.toDouble();
                              final double? newLng =
                                  (result['longitude'] as num?)?.toDouble();

                              setState(() {
                                if (extraSeconds > 0) {
                                  final now = DateTime.now();
                                  final base = (_sessionEndTime != null &&
                                          _sessionEndTime!.isAfter(now))
                                      ? _sessionEndTime!
                                      : now;
                                  _sessionEndTime =
                                      base.add(Duration(seconds: extraSeconds));
                                  _secondsRemaining =
                                      _secondsUntil(_sessionEndTime);
                                  _hadDelay = true;
                                  _expectedTimeStr =
                                      _formatClockFromNow(_secondsRemaining);
                                  // Keep Home's live countdown in sync with
                                  // the extended time.
                                  AppSession.instance.activeSessionEndTime =
                                      DateTime.now().add(
                                          Duration(seconds: _secondsRemaining));
                                }
                                if (newDestination != null &&
                                    newDestination.isNotEmpty) {
                                  _destination = newDestination;
                                  AppSession.instance.activeSessionDestination =
                                      newDestination;
                                }
                                if (newLat != null && newLng != null) {
                                  _destinationCoords = LatLng(newLat, newLng);
                                  _walkingRoute = null;
                                }
                                if (_isAwaitingResponse &&
                                    !_emergencyTriggered) {
                                  _isAwaitingResponse = false;
                                  _stage = _EscalationStage.main;
                                  _stageTimer?.cancel();
                                  _stageSecondsRemaining =
                                      _stageGracePeriodSeconds;
                                }
                              });

                              // Tell the server too, so the missed-deadline
                              // alert and the contacts' view follow the new
                              // time / destination instead of the old ones.
                              if ((extraSeconds > 0 ||
                                      (newDestination != null &&
                                          newDestination.isNotEmpty)) &&
                                  _sessionEndTime != null) {
                                final endTime = _sessionEndTime!;
                                (_startBackendCheckInFuture ??
                                        Future<String?>.value(_checkInId))
                                    .then((id) async {
                                  final checkInId = id ?? _checkInId;
                                  if (checkInId == null) return;
                                  await CheckInService.extend(
                                    checkInId,
                                    endTime,
                                    destinationName: newDestination,
                                    destinationLatitude: newLat,
                                    destinationLongitude: newLng,
                                    reason: delayReason,
                                  );
                                }).catchError((e) => debugPrint(
                                        'Deadline sync skipped: $e'));
                              }

                              if (newLat != null && newLng != null) {
                                _fetchWalkingRoute();
                              }
                              if (extraSeconds > 0 && !_emergencyTriggered) {
                                _startTimer();
                              }
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            backgroundColor: AppColors.card,
                            side: BorderSide(
                                color: AppColors.border.withValues(alpha: 0.8)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(26)),
                          ),
                          child: Text('Request Delay',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _triggerEmergencyAlert,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF6554),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(26)),
                          ),
                          child: const Text('Need Help',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isAwaitingResponse && !_emergencyTriggered)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _stage == _EscalationStage.personal
                                  ? 'We will alert your trusted contacts in'
                                  : _stage == _EscalationStage.main
                                      ? 'We will alert your other contacts in'
                                      : 'We will alert Emergency Responders in',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600),
                            ),
                            Text(_formatTime(_stageSecondsRemaining),
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFFF6554),
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: 1 -
                                (_stageSecondsRemaining /
                                    _stageGracePeriodSeconds),
                            minHeight: 6,
                            backgroundColor:
                                AppColors.border.withValues(alpha: 0.5),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFFFF6554)),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EscalationBanner extends StatelessWidget {
  final _EscalationStage stage;
  final bool sosSent;
  final String? helpConfirmedBy;
  final VoidCallback onCallPolice;

  const _EscalationBanner({
    required this.stage,
    required this.sosSent,
    required this.onCallPolice,
    this.helpConfirmedBy,
  });

  @override
  Widget build(BuildContext context) {
    String title;
    String subtitle;

    if (helpConfirmedBy != null) {
      title = 'Help is on the way';
      subtitle =
          "$helpConfirmedBy confirmed they can help. We've stopped alerting anyone else — tap I'm Safe once they've reached you.";
    } else if (sosSent) {
      title = 'SOS Sent';
      subtitle =
          'Your Emergency Responders have been alerted with your location.';
    } else if (stage == _EscalationStage.personal) {
      title = 'Time is up!';
      subtitle =
          "Please confirm you're safe within 2 minutes, or we'll alert your trusted contacts.";
    } else if (stage == _EscalationStage.main) {
      title = 'Time is up!';
      subtitle = 'Are you safe? Your main contacts have been notified.';
    } else {
      title = 'Still no response';
      subtitle =
          "You haven't confirmed you're safe yet — your other contacts have been told.";
    }

    final calm = helpConfirmedBy != null;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
      decoration: BoxDecoration(
        color: calm
            ? AppColors.success.withValues(alpha: 0.1)
            : AppColors.dangerLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: calm
                ? AppColors.success.withValues(alpha: 0.4)
                : const Color(0xFFFFC9C0)),
      ),
      child: Column(
        children: [
          Icon(calm ? Icons.check_circle_outline : Icons.error_outline,
              color: calm ? AppColors.success : const Color(0xFFFF6554),
              size: 34),
          const SizedBox(height: 10),
          Text(title,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: calm ? AppColors.success : const Color(0xFFFF6554))),
          if (sosSent) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onCallPolice,
                icon: const Icon(Icons.call, size: 18),
                label: const Text('Call Police (117)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6554),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 46),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
