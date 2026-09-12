import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/safety_illustration.dart';

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
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
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
    super.dispose();
  }

  void _submit() async {
    setState(() {
      _emailBackendError = null;
      _phoneBackendError = null;
      _passwordBackendError = null;
    });
    final formValid = _formKey.currentState?.validate() ?? false;
    if (!formValid) return;

    // Registration itself (and the account-type choice it needs) now
    // happens on the next screen — this form's job is just collecting and
    // validating these fields.
    Navigator.pushNamed(context, '/account-type', arguments: {
      'fullName': _fullNameController.text.trim(),
      'email': _emailController.text.trim(),
      'phone': _phoneController.text.trim(),
      'password': _passwordController.text,
    });
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
                      const SizedBox(height: 16),
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
                        icon: Icons.person_outline,
                        hint: 'Enter your full name',
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Full name is required'
                            : null,
                      ),
                      _buildField(
                        'EMAIL ADDRESS',
                        _emailController,
                        icon: Icons.mail_outline,
                        hint: 'you@example.com',
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) =>
                            emailValidator(value) ?? _emailBackendError,
                        onChanged: (_) {
                          if (_emailBackendError != null) {
                            setState(() => _emailBackendError = null);
                          }
                        },
                      ),
                      _buildField(
                        'PHONE NUMBER',
                        _phoneController,
                        icon: Icons.phone_outlined,
                        hint: '+1 (000) 000-0000',
                        keyboardType: TextInputType.phone,
                        validator: (value) =>
                            phoneValidator(value) ?? _phoneBackendError,
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
                        () => setState(
                            () => _obscurePassword = !_obscurePassword),
                        icon: Icons.lock_outline,
                        hint: 'Minimum 8 characters',
                        onChanged: (_) {
                          if (_passwordBackendError != null) {
                            setState(() => _passwordBackendError = null);
                          }
                        },
                        validator: (v) {
                          if (v == null || v.isEmpty)
                            return 'Password is required';
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
                        () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                        icon: Icons.lock_outline,
                        hint: 'Repeat password',
                        validator: (v) {
                          if (v == null || v.isEmpty)
                            return 'Please confirm your password';
                          if (v != _passwordController.text)
                            return 'Passwords do not match';
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
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
                              Text('Continue'),
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
          ],
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
    IconData? icon,
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
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: icon == null
                  ? null
                  : Icon(icon, size: 19, color: AppColors.textMuted),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppColors.navy, width: 1.6),
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

  Widget _buildPasswordField(
    String label,
    TextEditingController controller,
    bool obscure,
    VoidCallback onToggle, {
    String? hint,
    IconData? icon,
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
              prefixIcon: icon == null
                  ? null
                  : Icon(icon, size: 19, color: AppColors.textMuted),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppColors.navy, width: 1.6),
              ),
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
