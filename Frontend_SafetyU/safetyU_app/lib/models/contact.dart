enum ContactStatus { pending, friend }

class Contact {
  final String id;
  final String fullName;
  final String phone;
  final String email;
  final String relationship;
  final bool isMainContact;
  final bool isAvailable;
  final ContactStatus status;
  final String? avatarUrl;

  /// Whether a person has ever been explicitly placed into the Main or
  /// Other tier from the Notify Contacts screen. Contacts that haven't
  /// (new ones, or anyone added before this flag existed) render in the
  /// "Unassigned" group above Main/Other until tagged — isMainContact's
  /// value doesn't matter until this is true.
  final bool tierAssigned;

  const Contact({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.relationship,
    this.isMainContact = false,
    this.isAvailable = true,
    this.status = ContactStatus.pending,
    this.avatarUrl,
    this.tierAssigned = false,
  });

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return '';
  }

  Contact copyWith({
    String? id,
    String? fullName,
    String? phone,
    String? email,
    String? relationship,
    bool? isMainContact,
    bool? isAvailable,
    ContactStatus? status,
    String? avatarUrl,
    bool? tierAssigned,
  }) {
    return Contact(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      relationship: relationship ?? this.relationship,
      isMainContact: isMainContact ?? this.isMainContact,
      isAvailable: isAvailable ?? this.isAvailable,
      status: status ?? this.status,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      tierAssigned: tierAssigned ?? this.tierAssigned,
    );
  }
}
