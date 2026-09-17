import 'api_client.dart';

/// POST /api/chat, GET /api/chat/:userId — real, backend-delivered 1:1
/// messages. Replaces the local-only AppSession chat log, which never
/// left the sending device — a "Need Help"/"I'm Safe" message sent that
/// way was invisible to the trusted contact it was supposedly sent to.
class ChatService {
  static Future<void> send(
    String receiverUserId,
    String text, {
    String kind = 'text',
    // Links this message's auto-generated safety_alert Notification (for
    // kind: 'helpRequest') to a real, active CheckIn, so the trusted
    // contact opening THIS alert can fetch a real live location for it —
    // without this, that Notification has no session behind it at all.
    String? checkInId,
  }) async {
    await ApiClient.post('/chat', {
      'receiverId': receiverUserId,
      'text': text,
      'kind': kind,
      if (checkInId != null) 'checkInId': checkInId,
    });
  }

  /// Every message between the signed-in account and [otherUserId],
  /// oldest first.
  static Future<List<Map<String, dynamic>>> conversation(
      String otherUserId) async {
    final data = await ApiClient.get('/chat/$otherUserId');
    return (data['messages'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
  }

  /// { senderUserId: unreadCount } — powers the badge on each friend's
  /// message icon. Opening that conversation (see [conversation]) is what
  /// clears it, since the backend marks those messages read on fetch.
  static Future<Map<String, int>> unreadCounts() async {
    final data = await ApiClient.get('/chat/unread/counts');
    final raw = data['counts'] as Map<String, dynamic>? ?? {};
    return raw.map((key, value) => MapEntry(key, (value as num).toInt()));
  }
}
