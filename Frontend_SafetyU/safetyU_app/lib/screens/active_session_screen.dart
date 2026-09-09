import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
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
import '../theme/app_theme.dart';
import 'session_safe_screen.dart';

/// Which contact tier we're currently trying to reach. Escalates
/// main -> secondary -> emergency responders if nobody can be confirmed
/// safe in time. Since this app has no backend, there is no way to detect
/// whether a contact actually *saw* a message — each stage only tracks
/// that its timer ran out, which is the honest limit of a client-only app.
enum _EscalationStage { main, secondary, emergency }

class ActiveSessionScreen extends StatefulWidget {
  const ActiveSessionScreen({super.key});

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
  Timer? _timer;
  StreamSubscription<Position>? _positionSub;
  final MapController _mapController = MapController();

  bool _isInitialized = false;

  int _secondsRemaining = 30 * 60;
  String _destination = 'Central Market';
  String _expectedTimeStr = '';
  LatLng _destinationCoords = const LatLng(11.5696, 104.9210);

  LatLng? _currentPosition;
  String? _locationStatusMessage;

  bool _emergencyTriggered = false;
  late DateTime _sessionStartedAt;
  bool _hadDelay = false;
  bool _historyLogged = false;

  // ---- Backend sync (see services/check_in_service.dart and
  // emergency_service.dart) ----
  // Both are best-effort: every session in this screen already works
  // fully offline/local, so a failed sync (backend not running, not
  // logged in via the backend, etc.) is swallowed rather than shown —
  // it never blocks or changes the local escalation flow above.
  String? _checkInId;
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
    // Fresh session — clear any leftover response tracking from a
    // previous alert so Home only ever shows the current one.
    AppSession.instance.clearCurrentAlertResponses();
    // So an early "I can help" response stops further escalation instead
    // of waiting out the full 2-minute stage timer regardless.
    AppSession.instance.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    AppSession.instance.removeListener(_onSessionChanged);
    _timer?.cancel();
    _stageTimer?.cancel();
    _positionSub?.cancel();
    super.dispose();
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('${helper.contactName} can help — pausing further alerts.')),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInitialized) {
      return;
    }
    final dynamic rawArguments = ModalRoute.of(context)?.settings.arguments;
    if (rawArguments is Map) {
      _destination =
          rawArguments['destination']?.toString() ?? 'Central Market';
      final dynamic duration = rawArguments['durationSeconds'];
      if (duration is num) {
        _secondsRemaining = duration.toInt();
      }
      _expectedTimeStr = rawArguments['expectedTimeStr']?.toString() ??
          _formatTime(_secondsRemaining);
      final double latitude =
          (rawArguments['latitude'] as num?)?.toDouble() ?? 11.5696;
      final double longitude =
          (rawArguments['longitude'] as num?)?.toDouble() ?? 104.9210;
      _destinationCoords = LatLng(latitude, longitude);
      final dynamic ids = rawArguments['notifyContactIds'];
      if (ids is List) {
        _confirmedNotifyContactIds = ids.map((e) => e.toString()).toList();
      }
    }

    _isInitialized = true;
    _startTimer();
    _initLocationTracking();
    _startBackendCheckIn();
  }

  // =========================================================
  // BACKEND SYNC — check-in + emergency escalation
  // =========================================================

  void _startBackendCheckIn() {
    final pos = AppSession.instance.lastKnownPosition;
    CheckInService.start(
      message: 'Safety session to $_destination',
      latitude: pos?.latitude,
      longitude: pos?.longitude,
    ).then((id) {
      if (mounted) _checkInId = id;
    }).catchError((e) {
      debugPrint('CheckIn sync skipped: $e');
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
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        timer.cancel();
        if (!_isAwaitingResponse && !_emergencyTriggered) {
          _enterEscalation(_EscalationStage.main);
        }
      }
    });
  }

  void _confirmSafe() {
    _timer?.cancel();
    _stageTimer?.cancel();
    _logHistory(SessionOutcome.safe);
    _syncSessionEndToBackend();

    // Tell every trusted contact who was actually alerted during this
    // session that the person is safe now — a real chat message, not just
    // an in-app log.
    for (final contact in AppSession.instance.friends) {
      if (_notifiedContactIds.contains(contact.id)) {
        AppSession.instance.sendChatMessage(
          contact.id,
          "I'm safe now. Thanks for checking on me!",
          kind: ChatMessageKind.safeCheckIn,
        );
      }
    }

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
    setState(() {
      _isAwaitingResponse = true;
      _stage = stage;
      _stageSecondsRemaining = _stageGracePeriodSeconds;
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

    _syncEscalationToBackend(stage);
    _stageTimer?.cancel();
    _stageTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_stageSecondsRemaining > 0) {
        setState(() => _stageSecondsRemaining--);
      } else {
        timer.cancel();
        // Nobody at this stage responded in time — record that on Home for
        // every one of them, not just one, before moving on.
        for (final target in _currentStageTargets) {
          AppSession.instance.markContactTimedOut(target.id);
        }
        final next = stage == _EscalationStage.main
            ? _EscalationStage.secondary
            : _EscalationStage.emergency;
        _enterEscalation(next);
      }
    });
  }

  Future<void> _notifyStage(_EscalationStage stage) async {
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

    for (final target in targets) {
      AppSession.instance.registerContactNotified(target);
      AppSession.instance.addNotification(
        title: target.fullName,
        body: 'Alerted about your safety session near $_destination.',
        kind: NotificationKind.trustedContact,
      );
      _notifiedContactIds.add(target.id);
      AppSession.instance.sendChatMessage(
        target.id,
        "I need help! I haven't checked in near $_destination.$locationLine\nCan you help?",
        kind: ChatMessageKind.helpRequest,
      );
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
    for (final main in mains) {
      AppSession.instance.registerContactNotified(main);
      AppSession.instance.addNotification(
        title: main.fullName,
        body: 'Alerted about your safety session near $_destination.',
        kind: NotificationKind.trustedContact,
      );
      _notifiedContactIds.add(main.id);
      AppSession.instance.sendChatMessage(
        main.id,
        "I need help right now near $_destination.$locationLine\nCan you help?",
        kind: ChatMessageKind.helpRequest,
      );
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

  Future<void> _initLocationTracking() async {
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

      final Position initial = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (!mounted) {
        return;
      }
      final initialLatLng = LatLng(initial.latitude, initial.longitude);
      setState(() {
        _currentPosition = initialLatLng;
        _locationStatusMessage = null;
      });
      AppSession.instance.updateLastKnownPosition(initialLatLng);

      try {
        _mapController.move(_currentPosition!, 15.0);
      } catch (_) {}

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
          setState(() => _currentPosition = latLng);
          // Keep the last-known-position cache fresh on every real fix, so
          // if GPS/connectivity drops right before an escalation, we still
          // have a real (if slightly old) location to send instead of
          // nothing at all.
          AppSession.instance.updateLastKnownPosition(latLng);
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

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        automaticallyImplyLeading: false,
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
                  onCallPolice: _callPolice,
                )
              else
                Container(
                  height: 180,
                  width: double.infinity,
                  margin: const EdgeInsets.all(20),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                          initialCenter: _currentPosition ?? _destinationCoords,
                          initialZoom: 15.0),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.safetyu.app',
                        ),
                        if (_currentPosition != null)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                  points: [
                                    _currentPosition!,
                                    _destinationCoords
                                  ],
                                  strokeWidth: 3,
                                  color: AppColors.navy.withValues(alpha: 0.4)),
                            ],
                          ),
                        MarkerLayer(
                          markers: [
                            Marker(
                                point: _destinationCoords,
                                child: Icon(Icons.location_on,
                                    color: AppColors.navy, size: 38)),
                            if (_currentPosition != null)
                              Marker(
                                  point: _currentPosition!,
                                  child: const Icon(Icons.my_location,
                                      color: Colors.blueAccent, size: 30)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _formatTime(_secondsRemaining),
                      style: TextStyle(
                        fontSize: 54,
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
                          backgroundColor: AppColors.navy,
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
                            final double? newLat =
                                (result['latitude'] as num?)?.toDouble();
                            final double? newLng =
                                (result['longitude'] as num?)?.toDouble();

                            setState(() {
                              if (extraSeconds > 0) {
                                _secondsRemaining += extraSeconds;
                                _hadDelay = true;
                                _expectedTimeStr =
                                    _formatClockFromNow(_secondsRemaining);
                              }
                              if (newDestination != null &&
                                  newDestination.isNotEmpty) {
                                _destination = newDestination;
                              }
                              if (newLat != null && newLng != null) {
                                _destinationCoords = LatLng(newLat, newLng);
                              }
                              if (_isAwaitingResponse && !_emergencyTriggered) {
                                _isAwaitingResponse = false;
                                _stage = _EscalationStage.main;
                                _stageTimer?.cancel();
                                _stageSecondsRemaining =
                                    _stageGracePeriodSeconds;
                              }
                            });

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
                            _stage == _EscalationStage.main
                                ? 'Escalates to other contacts in'
                                : 'Escalates to Emergency Responders in',
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
    );
  }
}

class _EscalationBanner extends StatelessWidget {
  final _EscalationStage stage;
  final bool sosSent;
  final VoidCallback onCallPolice;

  const _EscalationBanner(
      {required this.stage, required this.sosSent, required this.onCallPolice});

  @override
  Widget build(BuildContext context) {
    String title;
    String subtitle;

    if (sosSent) {
      title = 'SOS Sent';
      subtitle =
          'Your Emergency Responders have been alerted with your location.';
    } else if (stage == _EscalationStage.main) {
      title = 'Time is up!';
      subtitle = 'Are you safe? Your main contacts have been notified.';
    } else {
      title = 'Escalating';
      subtitle =
          'No confirmation yet — your other contacts have been notified.';
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.dangerLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFC9C0)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF6554), size: 34),
          const SizedBox(height: 10),
          Text(title,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFF6554))),
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
