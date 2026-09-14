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
      // Once the owner has genuinely confirmed Safe, this no longer
      // belongs on the "needs a response" list — it converts to the
      // separate "X is safe now" card instead (see
      // recentlyResolvedSafetyAlerts below), rather than staying stuck
      // asking for a response to something that's already resolved.
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
        'isRead': n['isRead'] == true,
      });
    }
    return merged;
  }

  /// Alerts whose session the owner has since marked Safe — used for the
  // calm "X is safe now" card on Home, shown for a short while after
  // resolution rather than just vanishing the moment it's no longer
  // actionable.
  static Future<List<Map<String, dynamic>>>
      recentlyResolvedSafetyAlerts() async {
    final all = await fetchAll();
    final resolved = <Map<String, dynamic>>[];
    for (final n in all) {
      if (n['type'] != 'safety_alert') continue;
      final checkIn = n['checkIn'] as Map<String, dynamic>?;
      if (checkIn?['status'] != 'completed') continue;
      // Already shown once before (marked read) — this is what stops the
      // same "is safe now" card from reappearing on every future login.
      if (n['isRead'] == true) continue;
      final sender = n['sender'] as Map<String, dynamic>?;
      resolved.add({
        'notificationId': n['_id']?.toString(),
        'ownerUserId': sender?['_id']?.toString(),
        'ownerName': sender?['name']?.toString() ?? 'A trusted contact',
        'notifiedAt': n['createdAt']?.toString(),
      });
    }
    return resolved;
  }
}
