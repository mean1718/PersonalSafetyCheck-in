import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Puts a real notification in the phone's notification tray/lock screen —
/// the same kind of alert other apps show — instead of only updating
/// something inside SafetyU that's invisible unless the app is already
/// open on screen.
///
/// IMPORTANT — what this can and can't do:
/// This uses `flutter_local_notifications`, which lets the app that is
/// still *running* (foreground OR backgrounded, i.e. the user hasn't
/// force-closed/swiped it away) push a tray notification the instant
/// SafetyU's own code decides to. That covers "I have the app open on a
/// different tab" and "I switched to another app" — the two situations
/// this ticket is actually about.
///
/// It can NOT wake the app up from fully closed/killed, or deliver a
/// notification that originates on someone else's phone (e.g. Panha's
/// device telling Jimin's device "you were just tagged Other") without a
/// real push backend — that needs Firebase Cloud Messaging (or APNs) with
/// the server sending the push, which is a separate, bigger piece of work
/// than this file. This service is the local half of that; call
/// [LocalNotificationService.show] from wherever the app already polls
/// the backend and notices something new (see home_dashboard_screen.dart).
class LocalNotificationService {
  LocalNotificationService._();
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Called when the person taps one of these notifications. Set by
  /// PushNotificationService so a tap opens the alerts screen instead of
  /// just launching the app and leaving them to find it.
  static void Function()? onNotificationTap;

  static const AndroidNotificationDetails _trustRequestAndroidDetails =
      AndroidNotificationDetails(
    'trust_requests',
    'Trust requests',
    channelDescription: 'Alerts you when someone adds you as a trusted contact',
    importance: Importance.high,
    priority: Priority.high,
  );

  // Not const — RawResourceAndroidNotificationSound isn't a const
  // constructor, so this whole details object can't be either.
  static final AndroidNotificationDetails _safetyAlertAndroidDetails =
      AndroidNotificationDetails(
    // Renamed from 'safety_alerts' — Android locks a channel's sound the
    // first time it's created, so bumping the id is the only way to make
    // an existing install actually pick up the new alarm-style sound
    // below instead of silently keeping whatever it had before. See
    // pushService.js's ANDROID_CHANNEL_BY_TYPE, which was updated to
    // match this same id.
    'safety_alerts_v2',
    'Safety alerts',
    channelDescription: 'Alerts you when a trusted friend needs you',
    importance: Importance.max,
    priority: Priority.max,
    // Needs android/app/src/main/res/raw/alarm_sound.mp3 (or .ogg/.wav) —
    // a real audio file this project doesn't have yet. Without it,
    // Android silently falls back to the default notification sound
    // rather than failing, so add one for this to actually sound
    // alarm-like instead of a normal ping.
    sound: RawResourceAndroidNotificationSound('alarm_sound'),
    playSound: true,
    enableVibration: true,
    vibrationPattern:
        Int64List.fromList([0, 800, 400, 800, 400, 800, 400, 800]),
    fullScreenIntent: true,
  );

  static const AndroidNotificationDetails _emergencyAlertAndroidDetails =
      AndroidNotificationDetails(
    'emergency_alerts',
    'Emergency alerts',
    channelDescription: 'Urgent alerts for new emergency responder cases',
    importance: Importance.max,
    priority: Priority.max,
  );

  static const AndroidNotificationDetails _safetyResolvedAndroidDetails =
      AndroidNotificationDetails(
    'safety_resolved',
    'Safe confirmations',
    channelDescription:
        'Lets you know when a trusted friend confirms they\'re safe',
    importance: Importance.high,
    priority: Priority.high,
  );

  static Future<void> init() async {
    // flutter_local_notifications has no web support (and building the
    // Android vibration pattern throws there), so skip it in the browser.
    if (kIsWeb) return;
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (_) => onNotificationTap?.call(),
    );
    // Android 13+ requires this explicit runtime request; older versions
    // and iOS (handled via DarwinInitializationSettings above) ignore it.
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    // Create the high-importance channels up front, at app start, instead
    // of letting them get created lazily the first time _plugin.show() runs.
    // Without this, a push that arrives while the app is fully closed (so
    // this code never runs) is the FIRST thing to reach Android for that
    // channel, and Android silently falls back to its own default/low
    // channel — which is why alerts were only ever showing while the app
    // was already open. The backend push payload references these same
    // channel ids (see pushService.js), so this needs to run before any
    // push can arrive, i.e. every app start, not just after first use.
    for (final channel in [
      _trustRequestAndroidDetails,
      _safetyAlertAndroidDetails,
      _safetyResolvedAndroidDetails,
      _emergencyAlertAndroidDetails,
    ]) {
      await androidPlugin?.createNotificationChannel(
        AndroidNotificationChannel(
          channel.channelId,
          channel.channelName,
          description: channel.channelDescription,
          importance: channel.importance,
          // These were missing before — importance alone doesn't carry
          // the sound/vibration/full-screen behavior over to the actual
          // channel Android creates, only what .show() is told per-call
          // (which can't override a channel's sound once it exists). The
          // safety_alerts_v2 channel needs its alarm sound baked in here,
          // at creation, or it silently plays the platform default.
          playSound: channel.playSound,
          sound: channel.sound,
          enableVibration: channel.enableVibration,
          vibrationPattern: channel.vibrationPattern,
        ),
      );
    }
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    _initialized = true;
  }

  static Future<void> showTrustRequest({
    required int id,
    required String senderName,
  }) async {
    if (kIsWeb) return;
    if (!_initialized) await init();
    try {
      await _plugin.show(
        id,
        'New trust request',
        '$senderName wants to add you as a trusted contact.',
        const NotificationDetails(
          android: _trustRequestAndroidDetails,
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('LocalNotificationService: trust request show failed -> $e');
    }
  }

  static Future<void> showSafetyAlert({
    required int id,
    required String ownerName,
  }) async {
    if (kIsWeb) return;
    if (!_initialized) await init();
    try {
      await _plugin.show(
        id,
        'Safety alert',
        '$ownerName started a safety session and needs you to check in.',
        NotificationDetails(
          android: _safetyAlertAndroidDetails,
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('LocalNotificationService: safety alert show failed -> $e');
    }
  }

  /// Shows a safety alert with the server's own wording ("Sam hasn't checked
  /// in on the way to Central Market and may need help") instead of the
  /// fixed "started a safety session" text, which was wrong for a missed
  /// deadline or a Need Help.
  static Future<void> showSafetyAlertMessage({
    required int id,
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    if (!_initialized) await init();
    try {
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: _safetyAlertAndroidDetails,
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('LocalNotificationService: safety alert show failed -> $e');
    }
  }

  static Future<void> showEmergencyAlert({
    required int id,
    required String userName,
  }) async {
    if (kIsWeb) return;
    if (!_initialized) await init();
    try {
      await _plugin.show(
        id,
        'New Emergency',
        '$userName needs immediate emergency assistance.',
        const NotificationDetails(
          android: _emergencyAlertAndroidDetails,
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('LocalNotificationService: emergency alert show failed -> $e');
    }
  }

  /// A trusted friend just confirmed they're safe (session completed, or
  /// "I'm Safe" sent from chat). Separate from [showSafetyAlert] so this
  /// doesn't say "needs you to check in" about someone who no longer does.
  static Future<void> showSafetyResolved({
    required int id,
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    if (!_initialized) await init();
    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: _safetyResolvedAndroidDetails,
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('LocalNotificationService: safety resolved show failed -> $e');
    }
  }
}
