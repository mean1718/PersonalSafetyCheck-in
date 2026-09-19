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

  static const AndroidNotificationDetails _trustRequestAndroidDetails =
      AndroidNotificationDetails(
    'trust_requests',
    'Trust requests',
    channelDescription: 'Alerts you when someone adds you as a trusted contact',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const AndroidNotificationDetails _safetyAlertAndroidDetails =
      AndroidNotificationDetails(
    'safety_alerts',
    'Safety alerts',
    channelDescription: 'Alerts you when a trusted friend needs you',
    importance: Importance.max,
    priority: Priority.high,
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
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
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
          channel.channelId!,
          channel.channelName!,
          description: channel.channelDescription,
          importance: channel.importance,
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
    if (!_initialized) await init();
    try {
      await _plugin.show(
        id,
        'Safety alert',
        '$ownerName started a safety session and needs you to check in.',
        const NotificationDetails(
          android: _safetyAlertAndroidDetails,
          iOS: DarwinNotificationDetails(),
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
