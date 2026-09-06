/// Shared field validators. Centralized so every screen that collects a
/// name/phone/email (Sign Up, Personal Info, Add Contact, Edit Contact)
/// enforces exactly the same rules.

/// Requires a real-looking domain suffix — an alphabetic top-level domain
/// of at least 2 characters (".com", ".org", ".io", ".co.uk", etc.) — not
/// just any string containing "@" and a dot. Rejects things like
/// "name@host" (no TLD) or "name@host.c" (TLD too short).
final RegExp kEmailPattern = RegExp(
  r'^[\w.+-]+@[\w-]+(\.[\w-]+)*\.[a-zA-Z]{2,}$',
);

bool isValidEmail(String value) => kEmailPattern.hasMatch(value.trim());

String onlyDigits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

bool isValidPhone(String value) => onlyDigits(value).length >= 7;

/// Standard "please enter a valid email" validator for a Form field.
String? emailValidator(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Email is required';
  if (!isValidEmail(text)) {
    return 'Enter a real email address (e.g. name@example.com)';
  }
  return null;
}

/// Standard "please enter a valid phone number" validator for a Form field.
String? phoneValidator(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Phone number is required';
  if (!isValidPhone(text)) return 'Enter a valid phone number';
  return null;
}
