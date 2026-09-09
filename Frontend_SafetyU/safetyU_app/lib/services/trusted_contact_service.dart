import 'api_client.dart';

/// Mirrors trusted contacts to the backend's TrustedContact collection.
///
/// IMPORTANT LIMITATION — read before changing this file: the backend only
/// supports ONE active "primary" and ONE active "secondary" contact per
/// account (see backend_SafetyU/src/controllers/trustedContactController.js
/// — adding a second contact at a priority that's already taken is
/// rejected with a 400). The Flutter app supports unlimited contacts plus
/// a friend-request flow the backend has no concept of at all. So:
///   - Every contact the person adds still lives fully in AppSession,
///     exactly as before — nothing about the local experience changes.
///   - Only whichever contact is currently tagged Main ("primary" on the
///     backend) and the one after it ("secondary") are mirrored to the
///     server, since that's genuinely all it can store. Everyone else
///     stays local-only.
/// This is called from the screens that assign/remove a contact's tier
/// (select_contacts_screen.dart) or delete a contact (trusted_contacts_
/// screen.dart), always fire-and-forget: a failed sync (backend offline,
/// not logged in via the backend, etc.) never blocks or breaks the local
/// UI, which is the whole point of keeping AppSession as the source of
/// truth.
class TrustedContactService {
  static Future<List<Map<String, dynamic>>> fetchAll() async {
    final data = await ApiClient.get('/trusted-contacts');
    final list = data['contacts'] as List<dynamic>? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  /// Replaces whichever backend contact currently holds [priority]
  /// ("primary" or "secondary") with the given details.
  static Future<void> upsertPriorityContact({
    required String priority,
    required String name,
    required String phone,
    required String relationship,
  }) async {
    final existing = await fetchAll();
    for (final c in existing) {
      if (c['priority'] == priority) {
        final id = c['_id']?.toString();
        if (id != null) {
          await ApiClient.delete('/trusted-contacts/$id');
        }
      }
    }
    await ApiClient.post('/trusted-contacts', {
      'name': name,
      'phone': phone,
      'relationship': relationship.isEmpty ? 'Contact' : relationship,
      'priority': priority,
    });
  }

  /// Removes whichever backend contact matches [phone] (any priority) —
  /// used when a contact is deleted from the app.
  static Future<void> removeByPhone(String phone) async {
    final existing = await fetchAll();
    for (final c in existing) {
      if (c['phone'] == phone) {
        final id = c['_id']?.toString();
        if (id != null) {
          await ApiClient.delete('/trusted-contacts/$id');
        }
      }
    }
  }
}
