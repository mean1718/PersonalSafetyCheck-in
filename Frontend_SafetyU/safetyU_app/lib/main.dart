import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'models/contact.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
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
import 'screens/verify_phone_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/cases_screen.dart';
import 'screens/case_detail_screen.dart';
import 'screens/update_case_screen.dart';
import 'screens/case_resolved_screen.dart'; 

void main() {
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
          routes: {
            '/': (context) => const SplashScreen(),
            '/login': (context) => const LoginScreen(),
            '/signup': (context) => const SignUpScreen(),
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
            '/verify-phone': (context) => const VerifyPhoneScreen(),
            '/cases': (context) => const CasesScreen(),
            '/case-detail': (context) => const CaseDetailScreen(),
            '/update-case': (context) => const UpdateCaseScreen(),
            '/case-resolved': (context) => const CaseResolvedScreen(),
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
