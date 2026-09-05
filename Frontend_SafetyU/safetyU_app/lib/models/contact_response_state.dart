/// Real-time status of one trusted contact's response to the alert sent
/// out during the current safety session. [pending] until that contact
/// either responds (via the respond flow) or their stage's timer runs out.
enum ContactResponseStatus { pending, canHelp, cantHelp, timedOut }

/// Tracks one notified contact for the *current* session's alert, so the
/// Home screen can show — in real time — who was notified and whether
/// they've responded yet. This is single-device data: it only reflects
/// actions actually taken on this same app instance.
class ContactResponseState {
  final String contactId;
  final String contactName;
  ContactResponseStatus status;
  final DateTime notifiedAt;

  ContactResponseState({
    required this.contactId,
    required this.contactName,
    required this.status,
    required this.notifiedAt,
  });
}
