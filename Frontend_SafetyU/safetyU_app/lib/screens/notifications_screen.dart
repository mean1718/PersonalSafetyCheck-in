import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/app_notification.dart';
import '../services/app_session.dart';
import '../services/notification_service.dart';
import '../services/trusted_contact_service.dart';
import '../models/contact.dart';
import '../models/help_request.dart';
import 'alert_detail_screen.dart';
import 'incoming_trust_request_card.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _backendNotifications = [];
  List<Map<String, dynamic>> _trustRequests = [];

 @override
void initState() {
  super.initState();

  // Do NOT mark backend emergency notifications as read here.
  //
  // A responder must explicitly Take Case before the
  // emergency notification becomes read.

  WidgetsBinding.instance.addPostFrameCallback((_) {
    AppSession.instance.markAllNotificationsRead();
  });

  _loadBackendNotifications();
  _loadTrustRequests();
}

  Future<void> _loadBackendNotifications() async {
  try {
    final notifications =
        await NotificationService.fetchAll();

    // ---------------------------------------------------------
    // DEDUPLICATE EMERGENCY ALERTS
    //
    // Other notification types are kept normally.
    // Emergency alerts are grouped by Emergency._id.
    // ---------------------------------------------------------

    final List<Map<String, dynamic>>
        result = [];

    final Map<String, Map<String, dynamic>>
        emergencyById = {};

    for (final notification
        in notifications) {
      if (notification['type']?.toString() !=
          'emergency_alert') {
        result.add(notification);
        continue;
      }

      final emergencyValue =
          notification['emergency'];

      final emergencyId =
          emergencyValue
                  is Map<String, dynamic>
              ? emergencyValue['_id']
                    ?.toString()
              : emergencyValue?.toString();

      // If an emergency notification has no emergency ID,
      // keep it rather than silently deleting it.
      if (emergencyId == null ||
          emergencyId.isEmpty) {
        result.add(notification);
        continue;
      }

      final existing =
          emergencyById[emergencyId];

      if (existing == null) {
        emergencyById[emergencyId] =
            notification;
        continue;
      }

      // Prefer unread.
      final existingUnread =
          existing['isRead'] != true;

      final currentUnread =
          notification['isRead'] != true;

      if (!existingUnread &&
          currentUnread) {
        emergencyById[emergencyId] =
            notification;
        continue;
      }

      // Otherwise prefer newest.
      final existingTime =
          DateTime.tryParse(
                existing['createdAt']
                        ?.toString() ??
                    '',
              ) ??
              DateTime.fromMillisecondsSinceEpoch(
                0,
              );

      final currentTime =
          DateTime.tryParse(
                notification['createdAt']
                        ?.toString() ??
                    '',
              ) ??
              DateTime.fromMillisecondsSinceEpoch(
                0,
              );

      if (currentTime
          .isAfter(existingTime)) {
        emergencyById[emergencyId] =
            notification;
      }
    }

    result.addAll(
      emergencyById.values,
    );

    // Newest first.
    result.sort((a, b) {
      final aTime =
          DateTime.tryParse(
                a['createdAt']
                        ?.toString() ??
                    '',
              ) ??
              DateTime.fromMillisecondsSinceEpoch(
                0,
              );

      final bTime =
          DateTime.tryParse(
                b['createdAt']
                        ?.toString() ??
                    '',
              ) ??
              DateTime.fromMillisecondsSinceEpoch(
                0,
              );

      return bTime.compareTo(aTime);
    });

    if (!mounted) {
      return;
    }

    setState(() {
      _backendNotifications = result;
    });

    // IMPORTANT:
    //
    // Do NOT mark notifications read here.
    //
    // Emergency notifications become read only when
    // the responder actually takes the case.
  } catch (e) {
    debugPrint(
      'Failed to load backend notifications: $e',
    );
  }
}

  Future<void> _loadTrustRequests() async {
    try {
      final requests = await TrustedContactService.receivedTrustRequests();
      AppSession.instance.setPendingTrustRequestCount(requests.length);
      if (mounted) setState(() => _trustRequests = requests);
    } catch (_) {}
  }

  Future<void> _respondToTrustRequest(String id, bool accept) async {
    try {
      await TrustedContactService.respondToTrustRequest(id, accept: accept);
      await _loadTrustRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(accept
                  ? 'Trust request accepted.'
                  : 'Trust request rejected.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update the Trust request.')),
        );
      }
    }
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

  void _openAlertDetail(Map<String, dynamic> notification) {
    final sender = notification['sender'] as Map<String, dynamic>?;
    final checkIn = notification['checkIn'] as Map<String, dynamic>?;
    final owner = Contact(
      id: sender?['_id']?.toString() ?? '',
      fullName: sender?['name']?.toString() ?? 'A trusted friend',
      phone: sender?['phone']?.toString() ?? '',
      email: '',
      relationship: 'Trusted Contact',
      status: ContactStatus.friend,
    );
    final request = HelpRequest(
      requesterName: owner.fullName,
      requesterPhone: owner.phone,
      destination: notification['message']?.toString() ?? 'their destination',
      location: null,
      distanceKm: null,
      requestedAt:
          DateTime.tryParse(notification['createdAt']?.toString() ?? '') ??
              DateTime.now(),
      checkInId: checkIn?['_id']?.toString(),
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AlertDetailScreen(
          contact: owner,
          request: request,
          notificationId: notification['_id']?.toString(),
        ),
      ),
    ).then((_) => _loadBackendNotifications());
  }

  String _relativeTime(String? iso) {
    final at = DateTime.tryParse(iso ?? '');
    if (at == null) return '';
    final diff = DateTime.now().difference(at);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
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
    // These two lists come from different places and must never hide one
    // another: `notifications` is this device's local activity log (e.g.
    // "panha can help" shown to the session owner), while
    // `_backendNotifications` is this account's real, per-user alerts from
    // the server (e.g. "Dan started a safety session" shown to panha).
    // Previously whichever list was non-empty first won, which meant a
    // signed-in contact with zero local activity but a real pending alert
    // would silently see nothing once *any* local entry existed.
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
        child: (notifications.isEmpty &&
                _backendNotifications.isEmpty &&
                _trustRequests.isEmpty)
            ? const _EmptyNotifications()
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_trustRequests.isNotEmpty) ...[
                    Text('Friend requests',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 10),
                    for (final request in _trustRequests) ...[
                      IncomingTrustRequestCard(
                        request: request,
                        onConfirm: () => _respondToTrustRequest(
                            request['_id'].toString(), true),
                        onReject: () => _respondToTrustRequest(
                            request['_id'].toString(), false),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 8),
                  ],
                  if (_backendNotifications.isNotEmpty) ...[
                    Text('Your alerts',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 10),
                    for (final notification in _backendNotifications) ...[
                      InkWell(
                        onTap: () async {
                          final id = notification['_id']?.toString();
                          if (id != null) {
                            await NotificationService.markRead(id);
                          }
                          await _loadBackendNotifications();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.border)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    notification['title']?.toString() ??
                                        'SafetyU Alert',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary)),
                                const SizedBox(height: 6),
                                Text(notification['message']?.toString() ?? '',
                                    style: TextStyle(
                                        color: AppColors.textSecondary)),
                                const SizedBox(height: 6),
                                Text(
                                  _relativeTime(
                                      notification['createdAt']?.toString()),
                                  style: TextStyle(
                                      fontSize: 11, color: AppColors.textMuted),
                                ),
                                if ((notification['checkIn']
                                        as Map<String, dynamic>?)?['status'] ==
                                    'completed') ...[
                                  const SizedBox(height: 8),
                                  Row(children: [
                                    Icon(Icons.check_circle,
                                        size: 15, color: AppColors.success),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${(notification['sender'] as Map<String, dynamic>?)?['name'] ?? 'They'} confirmed they\'re safe now.',
                                      style: TextStyle(
                                          color: AppColors.textSecondary),
                                    ),
                                  ]),
                                ] else if (notification['type'] ==
                                        'safety_alert' &&
                                    notification['responseStatus'] ==
                                        'pending') ...[
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: () =>
                                          _openAlertDetail(notification),
                                      icon: const Icon(
                                          Icons.location_on_outlined,
                                          size: 17),
                                      label: const Text('View Location'),
                                    ),
                                  ),
                                ] else if (notification['type'] ==
                                    'safety_alert') ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    notification['responseStatus'] == 'can_help'
                                        ? 'You responded: I can help'
                                        : "You responded: I can't help",
                                    style: TextStyle(
                                        color: AppColors.textSecondary),
                                  ),
                                ],
                              ]),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 8),
                  ],
                  if (notifications.isNotEmpty) ...[
                    Text('Activity',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 10),
                    for (final n in notifications) ...[
                      // These notifications live on the *alerter's* own
                      // device — they're updates about what a trusted
                      // contact did ("accepted your request", "can
                      // help"), not an alert for that contact to respond
                      // to. So these tiles are informational only;
                      // nothing to tap.
                      Container(
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
                      const SizedBox(height: 10),
                    ],
                  ],
                ],
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
