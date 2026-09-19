import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/contact.dart';

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
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Icon(Icons.arrow_back,
                                size: 20, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE3F0FF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.edit_note_rounded,
                                color: Color(0xFF2F6FED), size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Edit Contact',
                                  style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary),
                                ),
                                Text(
                                  "Update this contact's details below.",
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _buildField(
                        'NICKNAME',
                        _nameController,
                        icon: Icons.person_outline,
                        iconBg: const Color(0xFFE3F0FF),
                        iconColor: const Color(0xFF2F6FED),
                        hint: 'e.g. Sophea Chan',
                        validator: (v) => (v?.trim().isEmpty ?? true)
                            ? 'Name is required'
                            : null,
                      ),
                      // Phone and email belong to this friend's real
                      // SafetyU account, not to your local copy of them —
                      // editing them here would just be renaming a
                      // different person, the same way changing someone's
                      // number in Messenger doesn't change their real
                      // number. So only the nickname and how you relate to
                      // them are yours to change; these two stay read-only,
                      // shown as-is from their account.
                      _buildReadOnlyField(
                        'PHONE NUMBER',
                        _phoneController.text,
                        icon: Icons.phone_outlined,
                        iconBg: const Color(0xFFE1F7EA),
                        iconColor: const Color(0xFF0F9B7E),
                      ),
                      _buildReadOnlyField(
                        'EMAIL ADDRESS',
                        _emailController.text,
                        icon: Icons.mail_outline,
                        iconBg: const Color(0xFFEEE8FF),
                        iconColor: const Color(0xFF7C5CFC),
                      ),
                      _buildField(
                        'RELATIONSHIP',
                        _relationshipController,
                        icon: Icons.people_alt_outlined,
                        iconBg: const Color(0xFFFFF3D6),
                        iconColor: const Color(0xFFE0A500),
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
                              backgroundColor: AppColors.primaryButton,
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

  Widget _buildCard(
      {required IconData icon,
      required Widget child,
      Color? iconBg,
      Color? iconColor}) {
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
              color: iconBg ?? AppColors.background,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 19, color: iconColor ?? AppColors.navy),
          ),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }

  /// A field the person can look at but not change — used for phone/email,
  /// which belong to the friend's own account, not this local nickname.
  Widget _buildReadOnlyField(
    String label,
    String value, {
    required IconData icon,
    Color? iconBg,
    Color? iconColor,
  }) {
    return _buildCard(
      icon: icon,
      iconBg: iconBg,
      iconColor: iconColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.4),
              ),
              const SizedBox(width: 6),
              Icon(Icons.lock_outline,
                  size: 11, color: AppColors.textSecondary),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value.isEmpty ? '—' : value,
            style: TextStyle(fontSize: 15, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller, {
    required IconData icon,
    Color? iconBg,
    Color? iconColor,
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return _buildCard(
      icon: icon,
      iconBg: iconBg,
      iconColor: iconColor,
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
