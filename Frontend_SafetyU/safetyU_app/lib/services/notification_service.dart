import 'api_client.dart';

class NotificationService {
  static Future<List<Map<String, dynamic>>> fetchAll() async {
    final data = await ApiClient.get('/notifications');
    return (data['notifications'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> activeSafetyAlerts() async {
    final data = await ApiClient.get('/notifications/alerts');
    return (data['alerts'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
  }

  static Future<void> markRead(String id) =>
      ApiClient.put('/notifications/$id/read', {});

  static Future<void> respondToSafetyAlert(String id, String responseStatus) =>
      ApiClient.put(
          '/notifications/$id/response', {'responseStatus': responseStatus});

  /// GET /notifications/alerts only returns a safety alert while its
  /// session's checkIn.status is still "active"/"emergency" — it silently
  /// disappears the moment the owner completes their session, even if the
  /// receiver never actually answered. GET /notifications has no such
  /// filter (that's what the bell screen uses), so this merges anything
  /// from there that's still an unanswered safety_alert and isn't already
  /// present, normalized into the same shape /notifications/alerts uses.
  static Future<List<Map<String, dynamic>>> pendingSafetyAlerts() async {
    final results = await Future.wait([activeSafetyAlerts(), fetchAll()]);
    final active = results[0];
    final all = results[1];
    final seenIds = active.map((a) => a['notificationId']?.toString()).toSet();
    final merged = [...active];
    for (final n in all) {
      if (n['type'] != 'safety_alert') continue;
      if ((n['responseStatus']?.toString() ?? 'pending') != 'pending') continue;
      final checkIn = n['checkIn'] as Map<String, dynamic>?;
      final checkInStatus = checkIn?['status']?.toString();
      // The owner marked themselves safe (or it otherwise resolved) —
      // this no longer belongs on the "needs a response" list even
      // though nobody ever tapped Can Help / Can't Help.
      if (checkInStatus == 'completed') continue;
      final id = n['_id']?.toString();
      if (id == null || seenIds.contains(id)) continue;
      final sender = n['sender'] as Map<String, dynamic>?;
      merged.add({
        'notificationId': id,
        'sessionId': checkIn?['_id']?.toString(),
        'ownerUserId': sender?['_id']?.toString(),
        'ownerName': sender?['name']?.toString() ?? 'A trusted contact',
        'ownerPhone': sender?['phone']?.toString() ?? '',
        'message': n['message']?.toString() ?? '',
        'notifiedAt': n['createdAt']?.toString(),
        'responseStatus': n['responseStatus']?.toString() ?? 'pending',
      });
    }
    return merged;
  }
}
