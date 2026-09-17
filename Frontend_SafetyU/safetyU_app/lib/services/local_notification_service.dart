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
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
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
}
