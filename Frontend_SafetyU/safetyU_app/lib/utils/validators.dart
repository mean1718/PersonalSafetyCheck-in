/// Shared field validators. Centralized so every screen that collects a
/// name, phone, or email enforces the same rules.

String normalizeEmail(String value) => value.trim().toLowerCase();

const Set<String> kCommonGenericTlds = {
  'com', 'org', 'net', 'edu', 'gov', 'mil', 'info', 'biz', 'io',
  'co', 'app', 'dev', 'me', 'pro', 'tech', 'online', 'site', 'store',
  'cloud', 'ai', 'xyz', 'name', 'mobi', 'museum', 'travel',
};

bool isValidEmail(String value) {
  final email = normalizeEmail(value);
  if (email.isEmpty || email.length > 254 || email.split('@').length != 2) {
    return false;
  }
  final parts = email.split('@');
  final localPart = parts[0];
  final domain = parts[1];
  if (localPart.isEmpty ||
      localPart.startsWith('.') ||
      localPart.endsWith('.') ||
      localPart.contains('..') ||
      domain.contains('..')) {
    return false;
  }
  if (!RegExp(r"^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+$").hasMatch(localPart)) {
    return false;
  }
  final labels = domain.split('.');
  if (labels.length < 2 || labels.any((label) => label.isEmpty)) return false;
  final labelPattern = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');
  if (labels.any((label) => !labelPattern.hasMatch(label))) return false;
  final tld = labels.last;
  return tld.length == 2 || kCommonGenericTlds.contains(tld);
}

String onlyDigits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

bool isValidPhone(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'[\s().-]'), '');
  if (!RegExp(r'^\+?[0-9]{7,15}$').hasMatch(normalized)) return false;
  final digits = normalized.replaceFirst(RegExp(r'^\+'), '');
  if (RegExp(r'^(\d)\1+$').hasMatch(digits)) return false;
  var ascending = true;
  var descending = true;
  for (var index = 1; index < digits.length; index++) {
    final previous = int.parse(digits[index - 1]);
    final current = int.parse(digits[index]);
    ascending &= current == (previous + 1) % 10;
    descending &= current == (previous + 9) % 10;
  }
  return !ascending && !descending;
}

String? emailValidator(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Email is required.';
  if (!isValidEmail(text)) return 'Please enter a valid email address.';
  return null;
}

String? phoneValidator(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Phone number is required.';
  if (!isValidPhone(text)) return 'Please enter a valid phone number.';
  return null;
}
