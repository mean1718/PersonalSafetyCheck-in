import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../firebase_options.dart';
import 'api_client.dart';
import 'app_session.dart';
import 'local_notification_service.dart';

/// This is the piece that makes trust requests and safety alerts show up
/// on the phone even when SafetyU is fully closed — not just backgrounded.
/// [LocalNotificationService] can only fire from code that's already
/// running; this uses Firebase Cloud Messaging, where the *backend* sends
/// the push straight to the OS, which wakes the device and shows it
/// itself — the same mechanism WhatsApp/Facebook/etc. use.
///
/// Requires `flutterfire configure` to have been run in this project
/// (generates `lib/firebase_options.dart`, imported above) and a matching
/// `backend_SafetyU/serviceAccountKey.json` on the server side — without
/// both, [init] fails quietly and the app falls back to local-only
/// notifications.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Deliberately near-empty: every push this backend sends includes a
  // `notification` payload (see backend_SafetyU/src/services/pushService.js),
  // and Android/iOS show that in the tray automatically — even with the
  // app fully killed — with no app code required. This handler only
  // exists so Firebase has a registered entry point; it's where you'd add
  // handling for a future data-only (silent) push.
}

class PushNotificationService {
  PushNotificationService._();
  static String? _lastRegisteredToken;
  static bool _ready = false;

  static Future<void> init() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      debugPrint('PushNotificationService: Firebase not configured yet -> $e. '
          'Run `flutterfire configure` — see push_notification_service.dart '
          'for the full setup steps. Falling back to local-only notifications.');
      return;
    }
    _ready = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await FirebaseMessaging.instance
        .requestPermission(alert: true, badge: true, sound: true);

    // A push that arrives while the app is already open (foreground)
    // does NOT show a tray notification on its own — route it through
    // the same local-notification plumbing the rest of the app uses so
    // it's still visible, matching what happens when the app is closed.
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      final type = message.data['type'];
      if (type == 'emergency_alert') {
        LocalNotificationService.showEmergencyAlert(
          id: message.hashCode,
          userName: notification.body ?? 'A SafetyU user',
        );
      } else if (type == 'trust_request') {
        LocalNotificationService.showTrustRequest(
          id: message.hashCode,
          senderName: notification.body ?? 'Someone',
        );
      } else if (type == 'checkin_completed') {
        LocalNotificationService.showSafetyResolved(
          id: message.hashCode,
          title: notification.title ?? 'SafetyU',
          body:
              notification.body ?? 'A trusted friend confirmed they\'re safe.',
        );
      } else {
        LocalNotificationService.showSafetyAlert(
          id: message.hashCode,
          ownerName: notification.title ?? 'A trusted friend',
        );
      }
    });

    FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken);
    await registerAfterLogin();
  }

  /// Sends this device's current push token to the backend. Safe to call
  /// any time — it no-ops if Firebase never initialized or nobody's
  /// signed in yet — but call it explicitly right after AuthService.login
  /// succeeds, since [init] itself usually runs before login (at app
  /// start), when there's no auth token yet to attach the token to.
  static Future<void> registerAfterLogin() async {
    if (!_ready) return;
    if (AppSession.instance.authToken == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registerToken(token);
    } catch (e) {
      debugPrint('PushNotificationService: could not read FCM token -> $e');
    }
  }

  static Future<void> _registerToken(String token) async {
    if (token == _lastRegisteredToken) return;
    if (AppSession.instance.authToken == null) return;
    try {
      await ApiClient.post('/users/device-token', {'token': token});
      _lastRegisteredToken = token;
    } catch (e) {
      debugPrint('PushNotificationService: token registration failed -> $e');
    }
  }

  /// Call on logout — stops this account's pushes reaching a device it's
  /// no longer signed into.
  static Future<void> unregister() async {
    final token = _lastRegisteredToken;
    if (token == null) return;
    try {
      await ApiClient.post('/users/device-token/remove', {'token': token});
    } catch (_) {
      // Best effort — the token will simply go stale server-side.
    }
    _lastRegisteredToken = null;
  }
}
