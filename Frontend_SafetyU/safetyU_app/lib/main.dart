import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'models/contact.dart';
import 'services/route_observer.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/account_type_screen.dart';
import 'screens/home_dashboard_screen.dart';
import 'screens/trusted_contacts_screen.dart';
import 'screens/edit_contact_screen.dart';
import 'screens/session_setup_screen.dart';
import 'screens/active_session_screen.dart';
import 'screens/request_delay_screen.dart';
import 'screens/emergency_sos_screen.dart';
import 'screens/emergency_home_screen.dart';
import 'screens/location_permission_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/history_screen.dart';
import 'screens/personal_info_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/select_contacts_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/cases_screen.dart';
import 'screens/case_detail_screen.dart';
import 'screens/update_case_screen.dart';
import 'screens/case_resolved_screen.dart';
import 'screens/report_screen.dart';
import 'services/local_notification_service.dart';
import 'services/push_notification_service.dart';
import 'screens/emergency_pin_setup_screen.dart';

// ---------------------------------------------------------------------------
// DEBUG ONLY: make every Flutter error visible on screen.
//
// Flutter's red screen often shows only a follow-up message and hides the
// ORIGINAL error; layout errors show nothing at all (the widgets just go
// missing). In debug builds this records each distinct error — with where it
// came from — and shows a small red "errors" button on every screen. Tap it
// to read them, so one screenshot is enough to find the bug. Release builds
// are not affected.
// ---------------------------------------------------------------------------
final List<String> _recordedErrors = <String>[];
final Map<String, int> _errorCounts = <String, int>{};
final ValueNotifier<int> _errorTick = ValueNotifier<int>(0);

void _recordError(String message, StackTrace? stack) {
  final firstLine = message.split('\n').first;
  final seen = _errorCounts[firstLine] ?? 0;
  _errorCounts[firstLine] = seen + 1;
  if (seen == 0 && _recordedErrors.length < 8) {
    final trimmedStack = (stack?.toString() ?? 'no stack')
        .split('\n')
        .where((line) => line.trim().isNotEmpty && !line.contains('dart-sdk'))
        .take(10)
        .join('\n');
    _recordedErrors.add(
      '#${_recordedErrors.length + 1}  ${message.split('\n').take(6).join('\n')}\n$trimmedStack',
    );
  }
  // Errors can arrive in the middle of building/layout, so update the
  // button after the frame instead of during it.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _errorTick.value++;
  });
  WidgetsBinding.instance.scheduleFrame();
}

void _installDebugErrorScreen() {
  if (!kDebugMode) return;

  final previousHandler = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    _recordError(details.exceptionAsString(), details.stack);
    previousHandler?.call(details);
  };

  // Errors that happen outside the widget tree (timers, futures).
  final previousPlatformHandler = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    _recordError('$error', stack);
    return previousPlatformHandler?.call(error, stack) ?? false;
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: const Color(0xFF7A0E12),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(
            'ERRORS (send a screenshot of this):\n\n'
            '${_recordedErrors.isEmpty ? details.exceptionAsString() : _recordedErrors.join('\n\n')}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  };
}

/// The small red button (bottom-left) that opens the recorded errors.
class _DebugErrorOverlay extends StatefulWidget {
  const _DebugErrorOverlay();

  @override
  State<_DebugErrorOverlay> createState() => _DebugErrorOverlayState();
}

class _DebugErrorOverlayState extends State<_DebugErrorOverlay> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _errorTick,
      builder: (context, _, __) {
        if (_recordedErrors.isEmpty) return const SizedBox.shrink();
        if (!_open) {
          return Positioned(
            left: 8,
            bottom: 8,
            child: Material(
              color: const Color(0xFFB3261E),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => setState(() => _open = true),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    '⚠ ${_recordedErrors.length} error(s) - tap',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          );
        }
        return Positioned.fill(
          child: Material(
            color: const Color(0xFF3B0A0C),
            child: SafeArea(
              child: Column(
                children: [
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _open = false),
                        child: const Text('Close',
                            style: TextStyle(color: Colors.white)),
                      ),
                      TextButton(
                        onPressed: () {
                          _recordedErrors.clear();
                          _errorCounts.clear();
                          _errorTick.value++;
                          setState(() => _open = false);
                        },
                        child: const Text('Clear',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _recordedErrors.join('\n\n'),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11.5, height: 1.3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _installDebugErrorScreen();
  // Fire-and-forget: sets up the notification channels/permissions so the
  // app can put alerts in the phone's tray the moment something needs one
  // (see local_notification_service.dart). Never blocks app startup.
  LocalNotificationService.init();
  // Registers this device for real push notifications (trust requests,
  // safety alerts) that arrive even while SafetyU is fully closed — see
  // push_notification_service.dart for the one-time Firebase setup this
  // needs before it actually does anything.
  PushNotificationService.init();
  runApp(const SafetyUApp());
}

class SafetyUApp extends StatelessWidget {
  const SafetyUApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ListenableBuilder rebuilds the whole MaterialApp (and therefore its
    // `theme`) whenever ThemeController.instance.toggle()/setDark() is
    // called — this is what makes the dark mode switch in Profile actually
    // change colors app-wide instead of just being a stored preference.
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'SafetyU',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.current,
          initialRoute: '/',
          navigatorKey: rootNavigatorKey,
          // Debug only: the "errors" button described above.
          builder: (context, child) {
            if (!kDebugMode) return child ?? const SizedBox.shrink();
            return Stack(
              children: [
                child ?? const SizedBox.shrink(),
                const _DebugErrorOverlay(),
              ],
            );
          },
          navigatorObservers: [appRouteObserver],
          routes: {
            '/': (context) => const SplashScreen(),
            '/login': (context) => const LoginScreen(),
            '/signup': (context) => const SignUpScreen(),
            '/account-type': (context) => const AccountTypeScreen(),
            '/home': (context) => const HomeDashboardScreen(),
            '/contacts': (context) => const TrustedContactsScreen(),
            '/session-setup': (context) => const SessionSetupScreen(),
            '/active-session': (context) => const ActiveSessionScreen(),
            '/request-delay': (context) => const RequestDelayScreen(),
            '/emergency-sos': (context) => const EmergencySosScreen(),
            '/emergency-home': (context) => const EmergencyHomeScreen(),
            '/location-permission': (context) =>
                const LocationPermissionScreen(),
            '/notifications': (context) => const NotificationsScreen(),
            '/profile': (context) => const ProfileScreen(),
            '/history': (context) => const HistoryScreen(),
            '/personal-info': (context) => const PersonalInfoScreen(),
            '/change-password': (context) => const ChangePasswordScreen(),
            '/select-contacts': (context) => const SelectContactsScreen(),
            '/cases': (context) => const CasesScreen(),
            '/case-detail': (context) => const CaseDetailScreen(),
            '/update-case': (context) => const UpdateCaseScreen(),
            '/case-resolved': (context) => const CaseResolvedScreen(),
            '/reports': (context) => const ReportsScreen(),
            '/create-emergency-pin': (context) =>
                const EmergencyPinSetupScreen(),
          },
          onGenerateRoute: (settings) {
            if (settings.name == '/edit-contact') {
              final args = settings.arguments;
              final contact = args is Contact ? args : null;
              return MaterialPageRoute(
                builder: (context) => EditContactScreen(contact: contact),
                settings: settings,
              );
            }
            if (settings.name == '/chat') {
              final args = settings.arguments;
              if (args is Contact) {
                return MaterialPageRoute(
                  builder: (context) => ChatScreen(contact: args),
                  settings: settings,
                );
              }
            }
            return null;
          },
        );
      },
    );
  }
}
