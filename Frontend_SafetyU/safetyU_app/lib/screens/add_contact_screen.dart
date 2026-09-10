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
      setState(() { _isSubmitting = false; _phoneBackendError = error.message; });
      _formKey.currentState?.validate();
      return;
    } on ApiConnectionException catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon:
                          Icon(Icons.arrow_back, color: AppColors.textPrimary),
                    ),
                    Text(
                      'Add Contact',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildField(
                  'FULL NAME',
                  _nameController,
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
                  hint: '+855 12 345 678',
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    final err = phoneValidator(v) ?? _phoneBackendError;
                    if (err != null) return err;
                    if (AppSession.instance.isContactPhoneTaken(v!.trim())) {
                      return 'This phone number is already used by another contact';
                    }
                    return null;
                  },
                  onChanged: (_) { if (_phoneBackendError != null) setState(() => _phoneBackendError = null); },
                ),
                _buildField(
                  'EMAIL ADDRESS',
                  _emailController,
                  hint: 'name@example.com',
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    final text = v?.trim() ?? '';
                    if (text.isEmpty) return null;
                    final err = emailValidator(v);
                    if (err != null) return err;
                    if (AppSession.instance.isContactEmailTaken(v!.trim())) {
                      return 'This email is already used by another contact';
                    }
                    return null;
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('RELATIONSHIP', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.4)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _relationship,
                        decoration: InputDecoration(
                          hintText: 'Select relationship',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                        ),
                        items: const ['Parent', 'Sibling', 'Friend', 'Partner', 'Other'].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                        onChanged: (value) => setState(() => _relationship = value),
                        validator: (value) => value == null ? 'Please select a relationship.' : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
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
                    child: _isSubmitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text(
                      'Send Request',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600)),
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
            decoration: InputDecoration(
              hintText: hint,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border)),
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
