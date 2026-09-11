import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/app_notification.dart';
import '../services/app_session.dart';
import '../services/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _backendNotifications = [];

  @override
  void initState() {
    super.initState();
    // Mark everything read once the person actually opens the list, so
    // the badge count on Home reflects only genuinely unseen alerts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppSession.instance.markAllNotificationsRead();
    });
    _loadBackendNotifications();
  }

  Future<void> _loadBackendNotifications() async {
    try {
      final notifications = await NotificationService.fetchAll();
      if (mounted) setState(() => _backendNotifications = notifications);
    } catch (_) {}
  }

  Future<void> _respondToSafetyAlert(
      Map<String, dynamic> notification, String responseStatus) async {
    final id = notification['_id']?.toString();
    if (id == null) return;
    try {
      await NotificationService.respondToSafetyAlert(id, responseStatus);
      await _loadBackendNotifications();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(responseStatus == 'can_help'
              ? 'Your response was sent.'
              : "Your response was sent."),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to send your response.')),
        );
      }
    }
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
            ? (_backendNotifications.isEmpty
                ? const _EmptyNotifications()
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _backendNotifications.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final notification = _backendNotifications[index];
                      return InkWell(
                        onTap: () async {
                          final id = notification['_id']?.toString();
                          if (id != null) await NotificationService.markRead(id);
                          await _loadBackendNotifications();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(notification['title']?.toString() ?? 'SafetyU Alert', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                            const SizedBox(height: 6),
                            Text(notification['message']?.toString() ?? '', style: TextStyle(color: AppColors.textSecondary)),
                            if (notification['type'] == 'safety_alert' &&
                                notification['responseStatus'] == 'pending') ...[
                              const SizedBox(height: 12),
                              Row(children: [
                                Expanded(child: OutlinedButton(
                                  onPressed: () => _respondToSafetyAlert(notification, 'cannot_help'),
                                  child: const Text("I can't help"),
                                )),
                                const SizedBox(width: 8),
                                Expanded(child: ElevatedButton(
                                  onPressed: () => _respondToSafetyAlert(notification, 'can_help'),
                                  child: const Text('I can help'),
                                )),
                              ]),
                            ] else if (notification['type'] == 'safety_alert') ...[
                              const SizedBox(height: 8),
                              Text(
                                notification['responseStatus'] == 'can_help'
                                    ? 'You responded: I can help'
                                    : "You responded: I can't help",
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            ],
                          ]),
                        ),
                      );
                    },
                  ))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: notifications.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final n = notifications[index];
                  // These notifications live on the *alerter's* own device —
                  // they're updates about what a trusted contact did
                  // ("accepted your request", "can help"), not an alert for
                  // that contact to respond to. Opening AlertDetailScreen
                  // here would show the alerter the screen meant for the
                  // *contact* to decide whether they can help — backwards.
                  // So these tiles are informational only; nothing to tap.
                  return Container(
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
                  );
                },
              ),
      ),
    );
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
