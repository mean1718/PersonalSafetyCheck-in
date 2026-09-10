import 'api_client.dart';

/// Protected API wrapper for the current user's private trusted contacts.
class TrustedContactService {
  static Future<void> sendTrustRequest({
    required String phone,
    required String relationship,
  }) async {
    await ApiClient.post('/trust-requests', {
      'phone': phone,
      'relationship': relationship,
    });
  }

  static Future<List<Map<String, dynamic>>> receivedTrustRequests() async {
    final data = await ApiClient.get('/trust-requests/received');
    return (data['requests'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  }

  static Future<void> respondToTrustRequest(String id, {required bool accept}) =>
      ApiClient.post('/trust-requests/$id/${accept ? 'accept' : 'reject'}', {});

  static Future<List<Map<String, dynamic>>> fetchAll() async {
    final data = await ApiClient.get('/trusted-contacts');
    return (data['contacts'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> create({
    required String name,
    required String phone,
    required String email,
    required String relationship,
    required String priority,
    required bool isAvailable,
  }) async {
    final data = await ApiClient.post('/trusted-contacts', {
      'name': name,
      'phone': phone,
      'email': email,
      'relationship': relationship,
      'priority': priority,
      'availability': isAvailable ? 'available' : 'unavailable',
    });
    return data['contact'] as Map<String, dynamic>;
  }

  // Compatibility bridge for the existing Add Contact screen. New contacts
  // begin as secondary; the edit/tier flow can promote them to main later.
  static Future<void> createContact({
    required String name,
    required String phone,
    required String email,
    required String relationship,
    required bool isAvailable,
  }) async {
    await create(
      name: name,
      phone: phone,
      email: email,
      relationship: relationship,
      priority: 'secondary',
      isAvailable: isAvailable,
    );
  }

  static Future<Map<String, dynamic>> update(String id, {
    required String name,
    required String phone,
    required String email,
    required String relationship,
    required String priority,
    required bool isAvailable,
  }) async {
    final data = await ApiClient.put('/trusted-contacts/$id', {
      'name': name,
      'phone': phone,
      'email': email,
      'relationship': relationship,
      'priority': priority,
      'availability': isAvailable ? 'available' : 'unavailable',
    });
    return data['contact'] as Map<String, dynamic>;
  }

  /// Compatibility method used by the existing Main/Other tier selector.
  /// It updates this contact when it has already been saved, or creates it
  /// once when it is first assigned a tier.
  static Future<void> upsertPriorityContact({
    required String priority,
    required String name,
    required String phone,
    required String email,
    required String relationship,
    required bool isAvailable,
  }) async {
    Map<String, dynamic>? existing;
    for (final contact in await fetchAll()) {
      if (contact['phone'] == phone) {
        existing = contact;
        break;
      }
    }
    if (existing?['_id'] != null) {
      await update(
        existing!['_id'].toString(),
        name: name,
        phone: phone,
        email: email,
        relationship: relationship,
        priority: priority,
        isAvailable: isAvailable,
      );
      return;
    }
    await create(
      name: name,
      phone: phone,
      email: email,
      relationship: relationship,
      priority: priority,
      isAvailable: isAvailable,
    );
  }

  static Future<void> remove(String id) => ApiClient.delete('/trusted-contacts/$id');

  static Future<void> removeByPhone(String phone) async {
    for (final contact in await fetchAll()) {
      if (contact['phone'] == phone && contact['_id'] != null) {
        await remove(contact['_id'].toString());
      }
    }
  }
}
