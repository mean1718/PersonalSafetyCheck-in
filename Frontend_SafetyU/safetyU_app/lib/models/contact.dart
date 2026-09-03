class Contact {
  final String id;
  final String fullName;
  final String phone;
  final String email;
  final String relationship;
  final bool isMainContact;
  final bool isAvailable;
  final String? avatarUrl;

  const Contact({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.relationship,
    this.isMainContact = false,
    this.isAvailable = true,
    this.avatarUrl,
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
    String? avatarUrl,
  }) {
    return Contact(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      relationship: relationship ?? this.relationship,
      isMainContact: isMainContact ?? this.isMainContact,
      isAvailable: isAvailable ?? this.isAvailable,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}