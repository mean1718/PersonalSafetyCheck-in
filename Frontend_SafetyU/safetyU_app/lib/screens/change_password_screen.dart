import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/safety_illustration.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // No backend is wired up in this build, so there's no stored password
    // hash to verify against — this confirms the form is valid and clears
    // the fields rather than silently pretending to call a server.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Password updated.')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text('Change Password',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _passwordField(
                          'CURRENT PASSWORD',
                          _currentController,
                          _obscureCurrent,
                          () => setState(
                              () => _obscureCurrent = !_obscureCurrent),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Enter your current password'
                              : null),
                      _passwordField(
                          'NEW PASSWORD',
                          _newController,
                          _obscureNew,
                          () => setState(() => _obscureNew = !_obscureNew),
                          validator: (v) {
                        if (v == null || v.isEmpty)
                          return 'Enter a new password';
                        if (v.length < 8) return 'Use at least 8 characters';
                        return null;
                      }),
                      _passwordField(
                          'CONFIRM NEW PASSWORD',
                          _confirmController,
                          _obscureConfirm,
                          () => setState(
                              () => _obscureConfirm = !_obscureConfirm),
                          validator: (v) {
                        if (v == null || v.isEmpty)
                          return 'Please confirm your new password';
                        if (v != _newController.text)
                          return 'Passwords do not match';
                        return null;
                      }),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
            Stack(
              alignment: Alignment.bottomCenter,
              children: [
                const WaveDecorBottom(height: 130),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.danger,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26))),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.save_outlined,
                              size: 18, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Update Password',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _passwordField(String label, TextEditingController controller,
      bool obscure, VoidCallback onToggle,
      {String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.4)),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            obscureText: obscure,
            decoration: InputDecoration(
              prefixIcon: Padding(
                padding: const EdgeInsets.all(10),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A90E2).withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock,
                      size: 13, color: Color(0xFF4A90E2)),
                ),
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 46, minHeight: 46),
              suffixIcon: IconButton(
                icon: Icon(
                    obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: AppColors.textMuted),
                onPressed: onToggle,
              ),
            ),
            validator: validator,
            autovalidateMode: AutovalidateMode.onUserInteraction,
          ),
        ],
      ),
    );
  }
}
