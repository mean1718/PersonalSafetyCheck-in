import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/contact.dart';
import '../services/app_session.dart';
import '../utils/validators.dart';

/// "Edit Contact" — same card-based look as Add Contact. Priority tier
/// (Main vs Other) is no longer picked here; like Add Contact, that's
/// handled from the Notify Contacts screen instead, where the free-plan
/// limits are actually visible. Editing keeps whatever tier this contact
/// already had.
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

  @override
  void initState() {
    super.initState();
    final c = widget.contact;
    _nameController = TextEditingController(text: c?.fullName ?? '');
    _phoneController = TextEditingController(text: c?.phone ?? '');
    _emailController = TextEditingController(text: c?.email ?? '');
    _relationshipController =
        TextEditingController(text: c?.relationship ?? '');
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
      // Priority tier isn't editable here anymore — keep whatever this
      // contact already had (Add Contact starts new contacts as "Other").
      isMainContact: widget.contact?.isMainContact ?? false,
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
                        'Edit Contact',
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Update this contact's details below.",
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
                        icon: Icons.phone_outlined,
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
                        icon: Icons.mail_outline,
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
                        icon: Icons.people_alt_outlined,
                        hint: 'e.g. Sister, Roommate, Friend',
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Relationship is required'
                            : null,
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
                            onPressed: _saveContact,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.navy,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(25)),
                            ),
                            child: const Text(
                              'Save Edit',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700),
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
            autovalidateMode: AutovalidateMode.onUserInteraction,
          ),
        ],
      ),
    );
  }
}
