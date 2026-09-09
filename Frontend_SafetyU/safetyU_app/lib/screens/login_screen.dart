import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../theme/app_theme.dart';
import '../models/user_role.dart';
import '../services/app_session.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../utils/validators.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  UserRole? _selectedRole;
  bool _roleError = false;
  bool _isSubmitting = false;
  String? _emailBackendError;
  String? _passwordBackendError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Email is required.';
    if (!isValidEmail(text)) return 'Please enter a valid email address.';
    if (_emailBackendError != null) return _emailBackendError;
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required.';
    if (_passwordBackendError != null) return _passwordBackendError;
    return null;
  }

  void _showBackendFieldError(String message) {
    setState(() {
      if (message.toLowerCase().contains('email')) {
        _emailBackendError = message;
      } else {
        _passwordBackendError = message;
      }
    });
    _formKey.currentState?.validate();
  }

  void _submit() async {
    setState(() {
      _emailBackendError = null;
      _passwordBackendError = null;
    });
    final formValid = _formKey.currentState?.validate() ?? false;
    setState(() => _roleError = _selectedRole == null);

    if (!formValid || _selectedRole == null) {
      if (_selectedRole == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Please choose how you want to sign in — User or Emergency Responder.')),
        );
      }
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() => _isSubmitting = true);
    try {
      await AuthService.login(
        email: email,
        password: password,
        role: _selectedRole!,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showBackendFieldError(e.message);
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
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.navy,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(Icons.shield,
                            color: AppColors.danger, size: 28),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'SafetyU',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Welcome Back',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 24),
                const _FieldLabel('Email Address'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration:
                      const InputDecoration(hintText: 'you@example.com'),
                  validator: _validateEmail,
                  onChanged: (_) {
                    if (_emailBackendError != null) {
                      setState(() => _emailBackendError = null);
                    }
                  },
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                ),
                const SizedBox(height: 18),
                const _FieldLabel('Password'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: AppColors.textMuted,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: _validatePassword,
                  onChanged: (_) {
                    if (_passwordBackendError != null) {
                      setState(() => _passwordBackendError = null);
                    }
                  },
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {},
                    child: Text(
                      'Forgot Password?',
                      style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const _FieldLabel('Sign In As'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _RoleOption(
                        icon: Icons.person_outline,
                        label: 'User',
                        selected: _selectedRole == UserRole.user,
                        onTap: () => setState(() {
                          _selectedRole = UserRole.user;
                          _roleError = false;
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _RoleOption(
                        icon: Icons.local_hospital_outlined,
                        label: 'Emergency\nResponder',
                        selected: _selectedRole == UserRole.emergencyResponder,
                        onTap: () => setState(() {
                          _selectedRole = UserRole.emergencyResponder;
                          _roleError = false;
                        }),
                      ),
                    ),
                  ],
                ),
                if (_roleError) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Please select a role to continue',
                    style: TextStyle(
                        color: AppColors.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
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
                      : const Text('Log In'),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account? ",
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13.5),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pushNamed(context, '/signup'),
                        child: Text(
                          'Sign Up',
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
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _RoleOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RoleOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
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
        child: Column(
          children: [
            Icon(icon,
                size: 22,
                color: selected ? AppColors.navy : AppColors.textMuted),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.navy : AppColors.textSecondary,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
