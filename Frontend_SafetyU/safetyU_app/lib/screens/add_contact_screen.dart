import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/app_session.dart';
import '../utils/validators.dart';
import '../services/trusted_contact_service.dart';
import '../services/api_client.dart';

/// "Add Contact" — sends a friend request. There's no backend to actually
/// deliver it, so the new contact is saved as [ContactStatus.pending] and
/// only becomes a real friend once confirmed from the Friends screen — they
/// can't be notified or escalated to until then.
///
/// Priority tier (Main vs Other) is no longer chosen here — every new
/// contact starts as an "Other" contact, and the person picks who's Main
/// from the Notify Contacts screen instead, where the free-plan limits are
/// actually visible.
class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  String? _relationship;
  bool _isSubmitting = false;
  String? _phoneBackendError;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    setState(() => _phoneBackendError = null);
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await TrustedContactService.sendTrustRequest(
        phone: _phoneController.text.trim(),
        relationship: _relationship!,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _phoneBackendError = error.message;
      });
      _formKey.currentState?.validate();
      return;
    } on ApiConnectionException catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Trust request sent.')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Row(
                          children: [
                            Icon(Icons.arrow_back,
                                size: 20, color: AppColors.textPrimary),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Add Contact',
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Enter the details below to add a new contact.',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 20),
                      _buildField(
                        'FULL NAME',
                        _nameController,
                        icon: Icons.person_outline,
                        hint: 'e.g. Sophea Chan',
                        validator: (v) {
                          final text = v?.trim() ?? '';
                          if (text.isEmpty) return null;
                          if (AppSession.instance.isContactNameTaken(text)) {
                            return 'This name is already used by another contact';
                          }
                          return null;
                        },
                      ),
                      _buildField(
                        'PHONE NUMBER',
                        _phoneController,
                        icon: Icons.phone_outlined,
                        hint: '+855 12 345 678',
                        keyboardType: TextInputType.phone,
                        validator: (v) {
                          final err = phoneValidator(v) ?? _phoneBackendError;
                          if (err != null) return err;
                          if (AppSession.instance
                              .isContactPhoneTaken(v!.trim())) {
                            return 'This phone number is already used by another contact';
                          }
                          return null;
                        },
                        onChanged: (_) {
                          if (_phoneBackendError != null)
                            setState(() => _phoneBackendError = null);
                        },
                      ),
                      _buildField(
                        'EMAIL ADDRESS',
                        _emailController,
                        icon: Icons.mail_outline,
                        hint: 'name@example.com',
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          final text = v?.trim() ?? '';
                          if (text.isEmpty) return null;
                          final err = emailValidator(v);
                          if (err != null) return err;
                          if (AppSession.instance
                              .isContactEmailTaken(v!.trim())) {
                            return 'This email is already used by another contact';
                          }
                          return null;
                        },
                      ),
                      _buildCard(
                        icon: Icons.people_alt_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('RELATIONSHIP',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textSecondary,
                                    letterSpacing: 0.4)),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _relationship,
                              decoration: InputDecoration(
                                hintText: 'Select relationship',
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                border: InputBorder.none,
                              ),
                              items: const [
                                'Parent',
                                'Sibling',
                                'Friend',
                                'Partner',
                                'Other'
                              ]
                                  .map((value) => DropdownMenuItem(
                                      value: value, child: Text(value)))
                                  .toList(),
                              onChanged: (value) =>
                                  setState(() => _relationship = value),
                              validator: (value) => value == null
                                  ? 'Please select a relationship.'
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 150,
              width: double.infinity,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/add_contact_background.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _sendRequest,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.navy,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(25)),
                            ),
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
                                      Icon(Icons.send,
                                          size: 18, color: Colors.white),
                                      SizedBox(width: 8),
                                      Text(
                                        'Send Request',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('Cancel',
                              style: TextStyle(
                                  color: AppColors.danger,
                                  fontWeight: FontWeight.w600)),
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

  Widget _buildCard({required IconData icon, required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.background,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 19, color: AppColors.navy),
          ),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller, {
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
  }) {
    return _buildCard(
      icon: icon,
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
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
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
