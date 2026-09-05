import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/app_notification.dart';
import '../models/contact.dart';
import '../services/app_session.dart';
import 'alert_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Mark everything read once the person actually opens the list, so
    // the badge count on Home reflects only genuinely unseen alerts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppSession.instance.markAllNotificationsRead();
    });
  }

  Color _tagColor(NotificationKind kind) {
    switch (kind) {
      case NotificationKind.trustedContact:
        return AppColors.navy;
      case NotificationKind.escalation:
        return const Color(0xFFE59A2E);
      case NotificationKind.emergency:
        return AppColors.danger;
    }
  }

  Color _tagBg(NotificationKind kind) {
    switch (kind) {
      case NotificationKind.trustedContact:
        return AppColors.navy.withValues(alpha: 0.08);
      case NotificationKind.escalation:
        return const Color(0xFFFCF1DE);
      case NotificationKind.emergency:
        return AppColors.dangerLight;
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifications = AppSession.instance.notifications;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Notifications',
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary),
        ),
        actions: [
          if (notifications.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() => AppSession.instance.clearNotifications());
              },
              child: Text('Clear all',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12.5)),
            ),
        ],
      ),
      body: SafeArea(
        child: notifications.isEmpty
            ? const _EmptyNotifications()
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: notifications.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final n = notifications[index];
                  final matchedContact =
                      n.kind == NotificationKind.trustedContact
                          ? _findContactByName(n.title)
                          : null;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: matchedContact == null
                        ? null
                        : () {
                            final request = AppSession.instance
                                .buildHelpRequestFor(matchedContact);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AlertDetailScreen(
                                  contact: matchedContact,
                                  request: request,
                                ),
                              ),
                            );
                          },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  n.title,
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _tagBg(n.kind),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  n.kind.tagLabel,
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: _tagColor(n.kind)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            n.body,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textSecondary,
                                height: 1.35),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            n.relativeTime,
                            style: TextStyle(
                                fontSize: 11, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  /// Best-effort match from a notification's title back to a real trusted
  /// contact, so tapping a "your contact was alerted" notification can open
  /// the same respond flow that contact would see. Returns null (no tap
  /// action) when nothing matches rather than guessing.
  Contact? _findContactByName(String name) {
    final contacts = AppSession.instance.contacts;
    for (final c in contacts) {
      if (c.fullName == name) return c;
    }
    return null;
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none,
                size: 40, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              'No notifications yet',
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              "You'll see updates here when a safety session escalates or your trusted contacts respond.",
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
