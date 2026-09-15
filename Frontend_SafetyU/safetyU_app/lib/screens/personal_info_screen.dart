import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../services/app_session.dart';
import '../utils/validators.dart';

class PersonalInfoScreen extends StatefulWidget {
  const PersonalInfoScreen({super.key});

  @override
  State<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends State<PersonalInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: AppSession.instance.fullName);
    _emailController = TextEditingController(text: AppSession.instance.email);
    _phoneController = TextEditingController(text: AppSession.instance.phone);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    AppSession.instance.signIn(
      fullName: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      role: AppSession.instance.role,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Personal info updated.')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.instance.isDark;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text('Personal Info',
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
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _field(
                        'Full Name',
                        _nameController,
                        icon: Icons.person,
                        color: const Color(0xFF4A90E2),
                        validator: (v) {
                          final text = v?.trim() ?? '';
                          if (text.isEmpty) return 'Name is required';
                          if (AppSession.instance
                              .isOwnNameTakenByContact(text)) {
                            return 'This name is already used by one of your saved contacts';
                          }
                          return null;
                        },
                      ),
                      _field(
                        'Email Address',
                        _emailController,
                        icon: Icons.mail,
                        color: const Color(0xFF9B6EE0),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          final err = emailValidator(v);
                          if (err != null) return err;
                          if (AppSession.instance
                              .isOwnEmailTakenByContact(v!.trim())) {
                            return 'This email is already used by one of your saved contacts';
                          }
                          return null;
                        },
                      ),
                      _field(
                        'Phone Number',
                        _phoneController,
                        icon: Icons.phone,
                        color: const Color(0xFF2FAE60),
                        keyboardType: TextInputType.phone,
                        validator: (v) {
                          final err = phoneValidator(v);
                          if (err != null) return err;
                          if (AppSession.instance
                              .isOwnPhoneTakenByContact(v!.trim())) {
                            return 'This phone number is already used by one of your saved contacts';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      const _PersonalInfoIllustration(),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isDark ? Colors.transparent : AppColors.danger,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26)),
                    elevation: 0,
                  ),
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      gradient: isDark
                          ? const LinearGradient(
                              colors: [Color(0xFF6C63F7), Color(0xFF8C7BF0)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            )
                          : null,
                    ),
                    child: Container(
                      alignment: Alignment.center,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.save_outlined,
                              size: 18, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Save Changes',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    required IconData icon,
    required Color color,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, size: 13, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            validator: validator,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: InputDecoration(
              prefixIcon: Padding(
                padding: const EdgeInsets.all(10),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 13, color: AppColors.textSecondary),
                ),
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 46, minHeight: 46),
            ),
          ),
        ],
      ),
    );
  }
}

/// A simplified, flat-shape approximation of the reference illustration
/// (ID card, shield-with-heart, leaves, small hearts) — built from plain
/// Flutter icons/shapes rather than a traced asset, so it automatically
/// follows light/dark mode like the rest of the screen.
class _PersonalInfoIllustration extends StatelessWidget {
  const _PersonalInfoIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Soft wavy backdrop.
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                color: AppColors.navy.withValues(alpha: 0.06),
              ),
            ),
          ),
          // Decorative leaves, bottom-left and bottom-right.
          Positioned(
            left: 14,
            bottom: 14,
            child: Icon(Icons.eco,
                size: 30,
                color: const Color(0xFF4A90E2).withValues(alpha: 0.35)),
          ),
          Positioned(
            right: 18,
            bottom: 24,
            child: Icon(Icons.eco,
                size: 26,
                color: const Color(0xFF2FAE60).withValues(alpha: 0.35)),
          ),
          // ID card.
          Positioned(
            left: 40,
            child: Container(
              width: 140,
              height: 90,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 6),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4A90E2).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person,
                        size: 16, color: Color(0xFF4A90E2)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            height: 6,
                            margin: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                                color: AppColors.border,
                                borderRadius: BorderRadius.circular(3))),
                        Container(
                            height: 6,
                            width: 40,
                            margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(
                                color: AppColors.border,
                                borderRadius: BorderRadius.circular(3))),
                        Container(
                            height: 6,
                            width: 55,
                            margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(
                                color: AppColors.border,
                                borderRadius: BorderRadius.circular(3))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Shield with heart.
          Positioned(
            right: 60,
            child: SizedBox(
              width: 76,
              height: 88,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.shield, size: 76, color: const Color(0xFF4A90E2)),
                  const Icon(Icons.favorite, size: 26, color: Colors.white),
                ],
              ),
            ),
          ),
          // Small floating heart accent, upper right.
          Positioned(
            top: 6,
            right: 46,
            child: Icon(Icons.favorite, size: 20, color: AppColors.danger),
          ),
        ],
      ),
    );
  }
}