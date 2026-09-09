import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../theme/app_theme.dart';
import '../models/user_role.dart';
import '../services/app_session.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../utils/validators.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _badgeIdController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  UserRole? _selectedRole;
  bool _roleError = false;
  bool _isSubmitting = false;
  String? _emailBackendError;
  String? _phoneBackendError;
  String? _passwordBackendError;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _badgeIdController.dispose();
    super.dispose();
  }

  void _submit() async {
    setState(() {
      _emailBackendError = null;
      _phoneBackendError = null;
      _passwordBackendError = null;
    });
    final formValid = _formKey.currentState?.validate() ?? false;
    setState(() => _roleError = _selectedRole == null);

    if (!formValid || _selectedRole == null) {
      if (_selectedRole == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Please choose an account type — User or Emergency Responder.')),
        );
      }
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await AuthService.register(
        fullName: _fullNameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        phone: _phoneController.text.trim(),
        role: _selectedRole!,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      final message = e.message;
      setState(() {
        if (message.toLowerCase().contains('phone')) {
          _phoneBackendError = message;
        } else if (message.toLowerCase().contains('password')) {
          _passwordBackendError = message;
        } else {
          _emailBackendError = message;
        }
      });
      _formKey.currentState?.validate();
      return;
    } on ApiConnectionException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (_selectedRole == UserRole.emergencyResponder) {
      AppSession.instance.badgeId = _badgeIdController.text.trim();
      if (!mounted) return;
      // Responders go through phone verification before landing on the
      // dashboard — which itself gates on responderStatus until approved.
      Navigator.pushNamed(context, '/verify-phone',
          arguments: _selectedRole!.homeRoute);
      return;
    }

    await _proceedAfterAuth(_selectedRole!.homeRoute);
  }

  Future<void> _proceedAfterAuth(String targetRoute) async {
    if (!mounted) return;
    final permission = await Geolocator.checkPermission();
    final needsPrompt = permission == LocationPermission.denied;
    if (!mounted) return;
    if (needsPrompt) {
      Navigator.pushReplacementNamed(context, '/location-permission',
          arguments: targetRoute);
    } else {
      Navigator.pushReplacementNamed(context, targetRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Row(
                    children: [
                      Icon(Icons.arrow_back,
                          size: 18, color: AppColors.textSecondary),
                      SizedBox(width: 6),
                      Text(
                        'Back to Login',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Create Safety Account',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  'Protect yourself and stay connected with trusted contacts.',
                  style: TextStyle(
                      fontSize: 13.5,
                      color: AppColors.textSecondary,
                      height: 1.4),
                ),
                const SizedBox(height: 24),
                _buildField(
                  'FULL NAME',
                  _fullNameController,
                  hint: 'Enter your full name',
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Full name is required'
                      : null,
                ),
                _buildField(
                  'EMAIL ADDRESS',
                  _emailController,
                  hint: 'you@example.com',
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) => emailValidator(value) ?? _emailBackendError,
                  onChanged: (_) {
                    if (_emailBackendError != null) {
                      setState(() => _emailBackendError = null);
                    }
                  },
                ),
                _buildField(
                  'PHONE NUMBER',
                  _phoneController,
                  hint: '+1 (000) 000-0000',
                  keyboardType: TextInputType.phone,
                  validator: (value) => phoneValidator(value) ?? _phoneBackendError,
                  onChanged: (_) {
                    if (_phoneBackendError != null) {
                      setState(() => _phoneBackendError = null);
                    }
                  },
                ),
                _buildPasswordField(
                  'PASSWORD',
                  _passwordController,
                  _obscurePassword,
                  () => setState(() => _obscurePassword = !_obscurePassword),
                  hint: 'Minimum 8 characters',
                  onChanged: (_) {
                    if (_passwordBackendError != null) {
                      setState(() => _passwordBackendError = null);
                    }
                  },
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password is required';
                    if (v.length < 8) {
                      return 'Password must be at least 8 characters.';
                    }
                    return _passwordBackendError;
                  },
                ),
                _buildPasswordField(
                  'CONFIRM PASSWORD',
                  _confirmPasswordController,
                  _obscureConfirm,
                  () => setState(() => _obscureConfirm = !_obscureConfirm),
                  hint: 'Repeat password',
                  validator: (v) {
                    if (v == null || v.isEmpty)
                      return 'Please confirm your password';
                    if (v != _passwordController.text)
                      return 'Passwords do not match';
                    return null;
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  'ACCOUNT TYPE',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.4),
                ),
                const SizedBox(height: 8),
                _RoleTile(
                  icon: Icons.person_outline,
                  title: 'User',
                  subtitle: 'Start safety sessions and alert trusted contacts.',
                  selected: _selectedRole == UserRole.user,
                  onTap: () => setState(() {
                    _selectedRole = UserRole.user;
                    _roleError = false;
                  }),
                ),
                const SizedBox(height: 10),
                _RoleTile(
                  icon: Icons.local_hospital_outlined,
                  title: 'Emergency Responder',
                  subtitle:
                      'Monitor active sessions and respond to SOS alerts.',
                  selected: _selectedRole == UserRole.emergencyResponder,
                  onTap: () => setState(() {
                    _selectedRole = UserRole.emergencyResponder;
                    _roleError = false;
                  }),
                ),
                if (_roleError) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Please select an account type to continue',
                    style: TextStyle(
                        color: AppColors.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ],
                if (_selectedRole == UserRole.emergencyResponder) ...[
                  const SizedBox(height: 16),
                  _buildField(
                    'BADGE / OFFICER ID',
                    _badgeIdController,
                    hint: 'e.g. PP-4471',
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Badge ID is required for responder accounts'
                        : null,
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                        color: AppColors.dangerLight,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      'Responder accounts require phone verification and manual review before you can access real cases.',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Create Account'),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account? ',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13.5),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Text(
                          'Log In',
                          style: TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller, {
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.4),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: InputDecoration(hintText: hint),
            validator: validator,
            onChanged: onChanged,
            autovalidateMode: AutovalidateMode.onUserInteraction,
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordField(
    String label,
    TextEditingController controller,
    bool obscure,
    VoidCallback onToggle, {
    String? hint,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.4),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            obscureText: obscure,
            decoration: InputDecoration(
              hintText: hint,
              suffixIcon: IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: AppColors.textMuted,
                ),
                onPressed: onToggle,
              ),
            ),
            validator: validator,
            onChanged: onChanged,
            autovalidateMode: AutovalidateMode.onUserInteraction,
          ),
        ],
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _RoleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.navy.withValues(alpha: 0.06)
              : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.navy : AppColors.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 22,
                color: selected ? AppColors.navy : AppColors.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                        fontSize: 11.5, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? AppColors.navy : AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
