import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../theme/app_theme.dart';
import '../services/app_session.dart';

/// A friendly pre-prompt shown before the real OS location dialog, so the
/// person understands why SafetyU needs their location before the system
/// permission sheet interrupts them.
///
/// Reached right after login/signup with the eventual destination route
/// passed as the route argument (a plain String). Both "Allow" buttons
/// trigger the real Geolocator permission request — Android/iOS don't
/// expose a separate "ask once" API distinct from "while using the app",
/// so both lead to the same system dialog.
class LocationPermissionScreen extends StatefulWidget {
  const LocationPermissionScreen({super.key});

  @override
  State<LocationPermissionScreen> createState() =>
      _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen> {
  bool _requesting = false;

  String get _destinationRoute {
    final args = ModalRoute.of(context)?.settings.arguments;
    return args is String ? args : '/home';
  }

  Future<void> _requestPermission() async {
    if (_requesting) return;
    setState(() => _requesting = true);

    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Location services are off. Turn them on in system settings for the best experience.')),
      );
    }

    try {
      await Geolocator.requestPermission();
    } catch (_) {
      // Ignore — screens that need location handle denial gracefully.
    }

    AppSession.instance.locationPermissionDeclined = false;
    _goToDestination();
  }

  void _declinePermission() {
    AppSession.instance.locationPermissionDeclined = true;
    _goToDestination();
  }

  void _goToDestination() {
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, _destinationRoute);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: AppColors.background,
                child: const Center(
                  child: _LocationIllustration(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
              child: Column(
                children: [
                  Text(
                    'Allow SafetyU to use your location?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Your location is shared with your trusted contacts only during an active safety session — never all the time.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.45),
                  ),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _requestPermission,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26)),
                      ),
                      child: _requesting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4, color: Colors.white),
                            )
                          : const Text(
                              'Allow While Using the App',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _requesting ? null : _requestPermission,
                    child: Text('Allow Once',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                  ),
                  TextButton(
                    onPressed: _requesting ? null : _declinePermission,
                    child: Text("Don't Allow",
                        style: TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
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

class _LocationIllustration extends StatelessWidget {
  const _LocationIllustration();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: AppColors.navy.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.location_on, color: AppColors.navy, size: 56),
        ),
      ],
    );
  }
}
