import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/contact.dart';
import '../services/app_session.dart';
import '../utils/validators.dart';

/// "Add Contact" — sends a friend request. There's no backend to actually
/// deliver it, so the new contact is saved as [ContactStatus.pending] and
/// only becomes a real friend once confirmed from the Friends screen — they
/// can't be notified or escalated to until then.
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
  final _relationshipController = TextEditingController();
  bool _isMainContact = true;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _relationshipController.dispose();
    super.dispose();
  }

  void _sendRequest() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please fill in all required contact details.')),
      );
      return;
    }

    final contact = Contact(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fullName: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      email: _emailController.text.trim(),
      relationship: _relationshipController.text.trim(),
      isMainContact: _isMainContact,
      status: ContactStatus.pending,
    );

    Navigator.pop(context, contact);
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
                    if (text.isEmpty) return 'Name is required';
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
                    final err = phoneValidator(v);
                    if (err != null) return err;
                    if (AppSession.instance.isContactPhoneTaken(v!.trim())) {
                      return 'This phone number is already used by another contact';
                    }
                    return null;
                  },
                ),
                _buildField(
                  'EMAIL ADDRESS',
                  _emailController,
                  hint: 'name@example.com',
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    final err = emailValidator(v);
                    if (err != null) return err;
                    if (AppSession.instance.isContactEmailTaken(v!.trim())) {
                      return 'This email is already used by another contact';
                    }
                    return null;
                  },
                ),
                _buildField(
                  'RELATIONSHIP',
                  _relationshipController,
                  hint: 'e.g. Sister, Roommate, Friend',
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Relationship is required'
                      : null,
                ),
                const SizedBox(height: 8),
                Text(
                  'CONTACT PRIORITY TIER',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.4),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _PriorityOption(
                        label: 'Main Contact',
                        sublabel: 'Notified first',
                        selected: _isMainContact,
                        onTap: () => setState(() => _isMainContact = true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PriorityOption(
                        label: 'Other Contact',
                        sublabel: 'Backup notification',
                        selected: !_isMainContact,
                        onTap: () => setState(() => _isMainContact = false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _sendRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25)),
                    ),
                    child: const Text(
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
            autovalidateMode: AutovalidateMode.onUserInteraction,
          ),
        ],
      ),
    );
  }
}

class _PriorityOption extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool selected;
  final VoidCallback onTap;

  const _PriorityOption({
    required this.label,
    required this.sublabel,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.navy.withValues(alpha: 0.06)
              : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? AppColors.navy : AppColors.border,
              width: selected ? 1.6 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: selected ? AppColors.navy : AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(sublabel,
                  style:
                      TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}
