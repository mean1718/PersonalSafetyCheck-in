import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/avatar_colors.dart';
import '../models/contact.dart';
import '../models/chat_message.dart';
import '../services/app_session.dart';
import '../services/chat_service.dart';

/// Opened by tapping a contact's avatar/name in Trusted Contacts.
/// A real, backend-delivered 1:1 thread with that contact — messages sent
/// here actually reach their account, and theirs actually reach yours.
class ChatScreen extends StatefulWidget {
  final Contact contact;
  const ChatScreen({super.key, required this.contact});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<ChatMessage> _messages = [];
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadConversation(initial: true);
    // Lightweight polling so a reply shows up without needing to leave and
    // reopen the screen — there's no push/socket layer in this build yet.
    _pollTimer =
        Timer.periodic(const Duration(seconds: 4), (_) => _loadConversation());
  }

  ChatMessageKind _kindFromBackend(String? kind) {
    switch (kind) {
      case 'safeCheckIn':
        return ChatMessageKind.safeCheckIn;
      case 'helpRequest':
        return ChatMessageKind.helpRequest;
      default:
        return ChatMessageKind.text;
    }
  }

  String _kindToBackend(ChatMessageKind kind) {
    switch (kind) {
      case ChatMessageKind.safeCheckIn:
        return 'safeCheckIn';
      case ChatMessageKind.helpRequest:
        return 'helpRequest';
      case ChatMessageKind.text:
        return 'text';
    }
  }

  Future<void> _loadConversation({bool initial = false}) async {
    try {
      final raw = await ChatService.conversation(widget.contact.id);
      final myId = AppSession.instance.backendUserId;
      final messages = raw.map((m) {
        // Server timestamps are UTC — .toLocal() is what makes the time
        // shown match the person's own clock instead of running however
        // many hours ahead/behind the server's timezone.
        final sentAt = (DateTime.tryParse(m['createdAt']?.toString() ?? '') ??
                DateTime.now())
            .toLocal();
        return ChatMessage(
          id: m['_id']?.toString() ?? '',
          text: m['text']?.toString() ?? '',
          isMe: m['sender']?.toString() == myId,
          sentAt: sentAt,
          kind: _kindFromBackend(m['kind']?.toString()),
        );
      }).toList();
      if (mounted) {
        setState(() {
          _messages = messages;
          _loading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      debugPrint('Chat load skipped: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(
      {String? presetText, ChatMessageKind kind = ChatMessageKind.text}) async {
    final text = presetText ?? _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    // Optimistic local echo so sending feels instant, reconciled against
    // the server's own copy on the next poll.
    setState(() {
      _messages = [
        ..._messages,
        ChatMessage(
          id: 'local-${DateTime.now().microsecondsSinceEpoch}',
          text: text,
          isMe: true,
          sentAt: DateTime.now(),
          kind: kind,
        ),
      ];
    });
    _scrollToBottom();
    try {
      await ChatService.send(widget.contact.id, text,
          kind: _kindToBackend(kind));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Message didn't send. Try again.")),
        );
      }
    }
    _loadConversation();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contact = widget.contact;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: avatarBackgroundFor(contact.id),
              child: Text(
                contact.initials,
                style: TextStyle(
                  color: avatarForegroundFor(contact.id),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    contact.fullName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    contact.isAvailable ? 'Available' : 'Not available',
                    style: TextStyle(
                      fontSize: 11,
                      color: contact.isAvailable
                          ? AppColors.success
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? _EmptyChat(contactName: contact.fullName)
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            return _MessageBubble(message: _messages[index]);
                          },
                        ),
            ),
            _ChatInputBar(
              controller: _controller,
              onSend: () => _send(),
              onSendHelp: () => _send(
                presetText: 'Need Help',
                kind: ChatMessageKind.helpRequest,
              ),
              onSendSafe: () => _send(
                presetText: 'Safe',
                kind: ChatMessageKind.safeCheckIn,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  final String contactName;
  const _EmptyChat({required this.contactName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 36, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              'No messages yet',
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              'Say hello to $contactName, or send a quick "Safe" or "Need Help" check-in.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    final alignment = isMe ? Alignment.centerRight : Alignment.centerLeft;
    final crossAxis = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    Widget bubble;
    if (message.kind == ChatMessageKind.safeCheckIn) {
      bubble = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 15, color: AppColors.success),
            const SizedBox(width: 6),
            Text(
              'Safe',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.success),
            ),
          ],
        ),
      );
    } else if (message.kind == ChatMessageKind.helpRequest) {
      bubble = Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.dangerLight,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 15, color: AppColors.danger),
                const SizedBox(width: 6),
                Text(
                  'Needs help',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.danger),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              message.text,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.35,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      );
    } else {
      bubble = Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? AppColors.navy : AppColors.card,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: isMe ? null : Border.all(color: AppColors.border),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.35,
            color: isMe ? Colors.white : AppColors.textPrimary,
          ),
        ),
      );
    }

    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: crossAxis,
          children: [
            bubble,
            const SizedBox(height: 4),
            Text(
              message.timeLabel,
              style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onSendHelp;
  final VoidCallback onSendSafe;

  const _ChatInputBar({
    required this.controller,
    required this.onSend,
    required this.onSendHelp,
    required this.onSendSafe,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onSendHelp,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline,
                              size: 16, color: AppColors.danger),
                          const SizedBox(width: 4),
                          Text('Need Help',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.danger)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: onSendSafe,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 16, color: AppColors.success),
                          const SizedBox(width: 4),
                          Text('Safe',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.success)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: InputDecoration(
                      hintText: 'Message...',
                      filled: true,
                      fillColor: AppColors.background,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onSend,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.navy,
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.send, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
