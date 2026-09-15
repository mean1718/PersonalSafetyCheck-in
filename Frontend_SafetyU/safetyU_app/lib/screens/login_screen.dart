import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../theme/app_theme.dart';
import '../widgets/safety_illustration.dart';
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
      final normalized = message.toLowerCase();
      if (normalized.contains('incorrect email or password') ||
          normalized.contains('invalid credentials') ||
          normalized.contains('invalid password')) {
        _passwordBackendError = 'Incorrect password.';
      } else if (normalized.contains('email')) {
        _emailBackendError = message;
      } else {
        _passwordBackendError = 'Incorrect password.';
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
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.arrow_back,
                            color: AppColors.textPrimary),
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Image.asset(
                          'assets/images/safetyu_logo.png',
                          width: 140,
                          height: 140,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Welcome Back',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Log in to your account',
                        style: TextStyle(
                            fontSize: 13.5, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      Image.asset(
                        'assets/images/login_illustration.png',
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                      const SizedBox(height: 20),
                      const _FieldLabel('Email Address'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          hintText: 'you@example.com',
                          prefixIcon: Icon(Icons.mail_outline,
                              size: 19, color: AppColors.textMuted),
                        ),
                        validator: _validateEmail,
                        onChanged: (_) {
                          if (_emailBackendError != null) {
                            setState(() => _emailBackendError = null);
                          }
                        },
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                      ),
                      if (_emailBackendError != null) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () => Navigator.pushNamed(context, '/signup'),
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textSecondary),
                              children: [
                                const TextSpan(
                                    text: "Don't have an account yet? "),
                                TextSpan(
                                  text: 'Sign Up',
                                  style: TextStyle(
                                      color: AppColors.danger,
                                      fontWeight: FontWeight.w700,
                                      decoration: TextDecoration.underline),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      const _FieldLabel('Password'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          hintText: '••••••••',
                          prefixIcon: Icon(Icons.lock_outline,
                              size: 19, color: AppColors.textMuted),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: AppColors.textMuted,
                              size: 20,
                            ),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
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
                              selected:
                                  _selectedRole == UserRole.emergencyResponder,
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
                    ],
                  ),
                ),
              ),
            ),
            SkylineBottomBar(
              height: 160,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Log In'),
                              SizedBox(width: 6),
                              Icon(Icons.arrow_forward,
                                  size: 18, color: Colors.white),
                            ],
                          ),
                  ),
                  const SizedBox(height: 14),
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
          ],
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

  // Matches the reference's small blue corner badge on the selected tile —
  // distinct from the navy used for buttons/borders, just for this dot.
  static const Color _selectedBadge = Color(0xFF3E6DF6);

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
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: double.infinity,
            // A fixed height (not just vertical padding) is what actually
            // keeps these two the same size — "User" is one line and
            // "Emergency Responder" wraps to two, so sizing purely off
            // content made this box taller than the other one.
            height: 92,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.navy.withValues(alpha: 0.06)
                  : AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? _selectedBadge : AppColors.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
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
          if (selected)
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: _selectedBadge,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.card, width: 2),
                ),
                child: const Icon(Icons.check, size: 11, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
