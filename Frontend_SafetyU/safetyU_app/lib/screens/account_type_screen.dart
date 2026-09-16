import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../theme/app_theme.dart';
import '../models/user_role.dart';
import '../services/app_session.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../widgets/safety_illustration.dart';

/// Reached right after the signup form is filled in and validated.
///
/// User:
///   Account Type → Create Emergency PIN → Confirm PIN → Account Created
///
/// Emergency Responder:
///   Account Type → Officer ID → Register → Phone Verification
class AccountTypeScreen extends StatefulWidget {
  const AccountTypeScreen({super.key});

  @override
  State<AccountTypeScreen> createState() => _AccountTypeScreenState();
}

class _AccountTypeScreenState extends State<AccountTypeScreen> {
  static const Color _accent = Color(0xFF3E6DF6);

  UserRole? _selectedRole = UserRole.user;

  final _badgeIdController = TextEditingController();

  bool _isSubmitting = false;
  String? _badgeError;

  Map<String, String> get _draft {
    final args = ModalRoute.of(context)?.settings.arguments;

    return args is Map<String, String> ? args : const {};
  }

  @override
  void dispose() {
    _badgeIdController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    // ------------------------------------------------------------
    // MAKE SURE AN ACCOUNT TYPE IS SELECTED
    // ------------------------------------------------------------

    if (_selectedRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Choose User or Emergency Responder to continue.',
          ),
        ),
      );
      return;
    }

    // ------------------------------------------------------------
    // RESPONDER MUST HAVE OFFICER ID
    // ------------------------------------------------------------

    if (_selectedRole == UserRole.emergencyResponder &&
        _badgeIdController.text.trim().isEmpty) {
      setState(() {
        _badgeError =
            'Officer ID is required for responder accounts';
      });
      return;
    }

    // ------------------------------------------------------------
    // USER
    //
    // Do NOT register the user yet.
    //
    // First create the Emergency PIN, then the PIN setup screen
    // will call AuthService.register() with the PIN.
    // ------------------------------------------------------------

    if (_selectedRole == UserRole.user) {
      final draft = _draft;

      Navigator.pushNamed(
        context,
        '/create-emergency-pin',
        arguments: {
          'fullName': draft['fullName'] ?? '',
          'email': draft['email'] ?? '',
          'password': draft['password'] ?? '',
          'phone': draft['phone'] ?? '',
        },
      );

      return;
    }

    // ------------------------------------------------------------
    // EMERGENCY RESPONDER
    //
    // Responder does NOT create an Emergency PIN.
    // ------------------------------------------------------------

    final draft = _draft;

    setState(() {
      _isSubmitting = true;
    });

    try {
      await AuthService.register(
        fullName: draft['fullName'] ?? '',
        email: draft['email'] ?? '',
        password: draft['password'] ?? '',
        phone: draft['phone'] ?? '',
        role: UserRole.emergencyResponder,
        officerId: _badgeIdController.text
            .trim()
            .toUpperCase(),
      );
    } on ApiException catch (e) {
      if (!mounted) return;

      setState(() {
        _isSubmitting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
        ),
      );

      return;
    } on ApiConnectionException catch (e) {
      if (!mounted) return;

      setState(() {
        _isSubmitting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
        ),
      );

      return;
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSubmitting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to create the account. Please try again.',
          ),
        ),
      );

      return;
    }

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
    });

    // Save the responder Officer ID locally for the responder session.
    AppSession.instance.badgeId =
        _badgeIdController.text.trim().toUpperCase();

    // ------------------------------------------------------------
    // RESPONDER → PHONE VERIFICATION
    //
    // Do NOT call _proceedAfterAuth() here.
    // Phone verification should control the next step.
    // ------------------------------------------------------------

    Navigator.pushNamed(
      context,
      '/verify-phone',
      arguments: UserRole.emergencyResponder.homeRoute,
    );
  }

  Future<void> _proceedAfterAuth(String targetRoute) async {
    if (!mounted) return;

    final permission = await Geolocator.checkPermission();

    final needsPrompt =
        permission == LocationPermission.denied;

    if (!mounted) return;

    if (needsPrompt) {
      Navigator.pushReplacementNamed(
        context,
        '/location-permission',
        arguments: targetRoute,
      );
    } else {
      Navigator.pushReplacementNamed(
        context,
        targetRoute,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  24,
                  16,
                  24,
                  8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ------------------------------------------------
                    // BACK
                    // ------------------------------------------------

                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Row(
                        children: [
                          Icon(
                            Icons.arrow_back,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Back',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ------------------------------------------------
                    // LOGO
                    // ------------------------------------------------

                    Center(
                      child: Column(
                        children: [
                          Image.asset(
                            'assets/images/safetyu_logo.png',
                            width: 52,
                            height: 52,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'SafetyU',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 22),

                    // ------------------------------------------------
                    // TITLE
                    // ------------------------------------------------

                    Text(
                      'Choose Account Type',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      "One more step — tell us how you'll use SafetyU.",
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ------------------------------------------------
                    // ILLUSTRATION
                    // ------------------------------------------------

                    Image.asset(
                      'assets/images/account_type_illustration.png',
                      height: 190,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),

                    const SizedBox(height: 20),

                    // ------------------------------------------------
                    // USER
                    // ------------------------------------------------

                    _RoleTile(
                      icon: Icons.person_outline,
                      title: 'User',
                      subtitle:
                          'Start safety sessions and alert trusted contacts.',
                      selected:
                          _selectedRole == UserRole.user,
                      accent: _accent,
                      onTap: () {
                        setState(() {
                          _selectedRole = UserRole.user;
                          _badgeError = null;
                        });
                      },
                    ),

                    const SizedBox(height: 12),

                    // ------------------------------------------------
                    // EMERGENCY RESPONDER
                    // ------------------------------------------------

                    _RoleTile(
                      icon: Icons.local_hospital_outlined,
                      title: 'Emergency Responder',
                      subtitle:
                          'Monitor active sessions and respond to SOS alerts.',
                      selected: _selectedRole ==
                          UserRole.emergencyResponder,
                      accent: _accent,
                      onTap: () {
                        setState(() {
                          _selectedRole =
                              UserRole.emergencyResponder;
                          _badgeError = null;
                        });
                      },
                    ),

                    // ------------------------------------------------
                    // RESPONDER OFFICER ID
                    // ------------------------------------------------

                    if (_selectedRole ==
                        UserRole.emergencyResponder) ...[
                      const SizedBox(height: 18),

                      Text(
                        'BADGE / OFFICER ID',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.4,
                        ),
                      ),

                      const SizedBox(height: 8),

                      TextField(
                        controller: _badgeIdController,
                        textCapitalization:
                            TextCapitalization.characters,
                        onChanged: (_) {
                          if (_badgeError != null) {
                            setState(() {
                              _badgeError = null;
                            });
                          }
                        },
                        decoration: InputDecoration(
                          hintText: 'e.g. PP-4471',
                          errorText: _badgeError,
                          prefixIcon: Icon(
                            Icons.badge_outlined,
                            size: 19,
                            color: AppColors.textMuted,
                          ),
                          filled: true,
                          fillColor: AppColors.card,
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: AppColors.border,
                            ),
                          ),
                          focusedBorder:
                              OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: AppColors.navy,
                              width: 1.6,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.dangerLight,
                          borderRadius:
                              BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Responder accounts require phone verification and manual review before you can access real cases.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // --------------------------------------------------------
            // BOTTOM CONFIRM BUTTON
            // --------------------------------------------------------

            SizedBox(
              height: 100,
              width: double.infinity,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Positioned.fill(
                    child: BottomWaveBand(
                      height: 100,
                    ),
                  ),

                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            _isSubmitting ? null : _confirm,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Text('Confirm'),
                                  SizedBox(width: 6),
                                  Icon(
                                    Icons.arrow_forward,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                ],
                              ),
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

// ============================================================================
// ROLE TILE
// ============================================================================

class _RoleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _RoleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.06)
              : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? accent
                : AppColors.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: selected
                    ? accent
                    : AppColors.background,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 20,
                color: selected
                    ? Colors.white
                    : AppColors.textMuted,
              ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 2),

                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),

            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected
                  ? accent
                  : AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}