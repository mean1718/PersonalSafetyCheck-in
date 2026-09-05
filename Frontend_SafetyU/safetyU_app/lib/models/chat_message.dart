/// The kind of chat message. [safeCheckIn] renders as a small pill-shaped
/// "Safe" bubble instead of a normal text bubble — a one-tap way to check
/// in with a trusted contact without typing. [helpRequest] renders as an
/// alert-tinted bubble and is sent automatically when a session actually
/// escalates to that contact, so the chat reflects the real alert instead
/// of staying empty.
enum ChatMessageKind { text, safeCheckIn, helpRequest }

/// A single real chat message between the signed-in person and one of
/// their trusted contacts. SafetyU has no backend in this build, so
/// threads live only in this device's [AppSession] — there is no delivery
/// receipt and no way to know the other person actually saw it, the same
/// honest limitation noted throughout the rest of the app's messaging.
class ChatMessage {
  final String id;
  final String text;
  final bool isMe;
  final DateTime sentAt;
  final ChatMessageKind kind;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.isMe,
    required this.sentAt,
    this.kind = ChatMessageKind.text,
  });

  String get timeLabel {
    final hour24 = sentAt.hour;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final minute = sentAt.minute.toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $period';
  }
}
