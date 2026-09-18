import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/user_role.dart';
import '../services/app_session.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import 'package:geolocator/geolocator.dart';

class EmergencyPinSetupScreen extends StatefulWidget {
  const EmergencyPinSetupScreen({super.key});

  @override
  State<EmergencyPinSetupScreen> createState() =>
      _EmergencyPinSetupScreenState();
}

class _EmergencyPinSetupScreenState
    extends State<EmergencyPinSetupScreen> {
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  bool _isSubmitting = false;
  String? _error;

  Map<String, String> get _draft {
    final args = ModalRoute.of(context)?.settings.arguments;

    if (args is Map) {
      return {
        'fullName': args['fullName']?.toString() ?? '',
        'email': args['email']?.toString() ?? '',
        'password': args['password']?.toString() ?? '',
        'phone': args['phone']?.toString() ?? '',
      };
    }

    return const {};
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  bool get _isExistingUser {
  final args = ModalRoute.of(context)?.settings.arguments;

  return args is Map &&
      args['isExistingUser'] == true;
}
  Future<void> _createAccount() async {
  final pin = _pinController.text.trim();
  final confirmPin = _confirmPinController.text.trim();

  setState(() => _error = null);

  // ----------------------------------------
  // Validate PIN
  // ----------------------------------------

  if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
    setState(
      () => _error =
          'Emergency PIN must be exactly 4 digits.',
    );
    return;
  }

  if (pin != confirmPin) {
    setState(
      () => _error =
          'Emergency PINs do not match.',
    );
    return;
  }

  setState(() => _isSubmitting = true);

  try {
    // =======================================================
    // EXISTING USER WITHOUT PIN
    // =======================================================

    if (_isExistingUser) {
      await AuthService.createEmergencyPin(
        newPin: pin,
        confirmPin: confirmPin,
      );

      if (!mounted) return;

      setState(() => _isSubmitting = false);

      Navigator.pushReplacementNamed(
        context,
        UserRole.user.homeRoute,
      );

      return;
    }

    // =======================================================
    // NEW USER
    // =======================================================

    final draft = _draft;

    await AuthService.register(
      fullName: draft['fullName'] ?? '',
      email: draft['email'] ?? '',
      password: draft['password'] ?? '',
      phone: draft['phone'] ?? '',
      role: UserRole.user,
      emergencyPin: pin,
    );
  } on ApiException catch (e) {
    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
      _error = e.message;
    });

    return;
  } on ApiConnectionException catch (e) {
    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
      _error = e.message;
    });

    return;
  }

  if (!mounted) return;

  setState(() => _isSubmitting = false);

  await _proceedAfterAuth(UserRole.user.homeRoute);
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
                  24,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: _isSubmitting
                          ? null
                          : () => Navigator.pop(context),
                      child: Row(
                        children: [
                          Icon(
                            Icons.arrow_back,
                            size: 18,
                            color:
                                AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Back',
                            style: TextStyle(
                              fontSize: 13,
                              color:
                                  AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.navy,
                          borderRadius:
                              BorderRadius.circular(18),
                        ),
                        child: Icon(
                          Icons.lock_outline,
                          size: 30,
                          color: AppColors.danger,
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    Center(
                      child: Text(
                        'Create Emergency PIN',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color:
                              AppColors.textPrimary,
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    Center(
                      child: Text(
                        'This PIN protects your Emergency Assistant.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              AppColors.textSecondary,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius:
                            BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.border,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            color: AppColors.navy,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Your Emergency PIN is used to confirm that you intentionally want to send an emergency alert.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color:
                                    AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 26),

                    Text(
                      'CREATE PIN',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color:
                            AppColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),

                    const SizedBox(height: 8),

                    TextField(
                      controller: _pinController,
                      keyboardType:
                          TextInputType.number,
                      maxLength: 4,
                      obscureText: true,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 12,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '••••',
                        hintStyle: TextStyle(
                          color:
                              AppColors.textMuted,
                          letterSpacing: 10,
                        ),
                        filled: true,
                        fillColor: AppColors.card,
                        prefixIcon: Icon(
                          Icons.lock_outline,
                          color:
                              AppColors.textMuted,
                        ),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color:
                                AppColors.border,
                          ),
                        ),
                        focusedBorder:
                            OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(14),
                          borderSide:
                              BorderSide(
                            color:
                                AppColors.navy,
                            width: 1.6,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    Text(
                      'CONFIRM PIN',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color:
                            AppColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),

                    const SizedBox(height: 8),

                    TextField(
                      controller:
                          _confirmPinController,
                      keyboardType:
                          TextInputType.number,
                      maxLength: 4,
                      obscureText: true,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 12,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '••••',
                        hintStyle: TextStyle(
                          color:
                              AppColors.textMuted,
                          letterSpacing: 10,
                        ),
                        filled: true,
                        fillColor: AppColors.card,
                        prefixIcon: Icon(
                          Icons.verified_user_outlined,
                          color:
                              AppColors.textMuted,
                        ),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color:
                                AppColors.border,
                          ),
                        ),
                        focusedBorder:
                            OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(14),
                          borderSide:
                              BorderSide(
                            color:
                                AppColors.navy,
                            width: 1.6,
                          ),
                        ),
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding:
                            const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color:
                              AppColors.dangerLight,
                          borderRadius:
                              BorderRadius.circular(12),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                FontWeight.w600,
                            color:
                                AppColors.danger,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    Text(
                      "When you need emergency help, you'll enter this PIN once to confirm that you want to send an emergency alert.",
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color:
                            AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding:
                  const EdgeInsets.fromLTRB(
                24,
                8,
                24,
                20,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSubmitting
                      ? null
                      : _createAccount,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
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
                            Text('Create Account'),
                            SizedBox(width: 8),
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
    );
  }
}