import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/contact.dart';
import '../services/app_session.dart';
import '../utils/validators.dart';
import '../widgets/safety_illustration.dart';

class EditContactScreen extends StatefulWidget {
  final Contact? contact;
  const EditContactScreen({super.key, this.contact});

  @override
  State<EditContactScreen> createState() => _EditContactScreenState();
}

class _EditContactScreenState extends State<EditContactScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _relationshipController;
  late bool _isMainContact;

  @override
  void initState() {
    super.initState();
    final c = widget.contact;
    _nameController = TextEditingController(text: c?.fullName ?? '');
    _phoneController = TextEditingController(text: c?.phone ?? '');
    _emailController = TextEditingController(text: c?.email ?? '');
    _relationshipController =
        TextEditingController(text: c?.relationship ?? '');
    _isMainContact = c?.isMainContact ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _relationshipController.dispose();
    super.dispose();
  }

  void _saveContact() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please fill in all required contact details.')),
      );
      return;
    }

    final updatedContact = Contact(
      id: widget.contact?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      fullName: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      email: _emailController.text.trim(),
      relationship: _relationshipController.text.trim(),
      isMainContact: _isMainContact,
      isAvailable: widget.contact?.isAvailable ?? true,
      // Editing never changes whether this contact has confirmed the
      // friend request — brand new contacts (no widget.contact) still
      // start out pending, same as Add Contact.
      status: widget.contact?.status ?? ContactStatus.pending,
    );

    // Returns the newly updated/created contact to TrustedContactsScreen
    Navigator.pop(context, updatedContact);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.contact != null;

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
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(Icons.arrow_back,
                                color: AppColors.textPrimary),
                          ),
                          Text(
                            isEditing ? 'Edit Contact' : 'Add Contact',
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
                          if (AppSession.instance.isContactNameTaken(text,
                              excludingId: widget.contact?.id)) {
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
                          if (AppSession.instance.isContactPhoneTaken(v!.trim(),
                              excludingId: widget.contact?.id)) {
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
                          if (AppSession.instance.isContactEmailTaken(v!.trim(),
                              excludingId: widget.contact?.id)) {
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
                              onTap: () =>
                                  setState(() => _isMainContact = true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _PriorityOption(
                              label: 'Other Contact',
                              sublabel: 'Backup notification',
                              selected: !_isMainContact,
                              onTap: () =>
                                  setState(() => _isMainContact = false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
            SkylineBottomBar(
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saveContact,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25)),
                  ),
                  child: Text(
                    isEditing ? 'Save Edit' : 'Add Contact',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                  ),
                ),
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
