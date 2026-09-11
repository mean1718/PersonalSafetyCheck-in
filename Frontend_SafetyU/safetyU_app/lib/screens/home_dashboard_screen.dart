import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../services/app_session.dart';
import '../services/check_in_service.dart';
import '../services/notification_service.dart';
import '../services/trusted_contact_service.dart';
import '../models/contact_response_state.dart';
import '../models/contact.dart';
import '../models/help_request.dart';
import 'alert_detail_screen.dart';
import 'dart:io';

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  int _navIndex = 0;
  bool _loadingAlertStatus = false;

  // Alerts where *this* signed-in person is the one who got notified —
  // i.e. they're someone else's trusted contact. Separate from
  // _ContactResponsesPanel below, which is the opposite direction: alerts
  // *this* person sent out as the session owner.
  bool _loadingIncomingAlerts = false;
  List<Map<String, dynamic>> _incomingAlerts = [];

  @override
  void initState() {
    super.initState();
    _loadAlertStatus();
    _loadIncomingAlerts();
    _loadPendingTrustRequestCount();
  }

  Future<void> _loadPendingTrustRequestCount() async {
    try {
      final requests = await TrustedContactService.receivedTrustRequests();
      AppSession.instance.setPendingTrustRequestCount(requests.length);
    } catch (_) {
      // Offline / not reachable — leave whatever count is already shown.
    }
  }

  Future<void> _loadAlertStatus() async {
    final checkInId = AppSession.instance.activeCheckInId;
    if (checkInId == null || _loadingAlertStatus) return;
    _loadingAlertStatus = true;
    try {
      final contacts = await CheckInService.alertStatus(checkInId);
      if (mounted)
        AppSession.instance.replaceAlertResponsesFromBackend(contacts);
    } catch (_) {
      // The local state remains available while an offline backend reconnects.
    } finally {
      _loadingAlertStatus = false;
    }
  }

  Future<void> _loadIncomingAlerts() async {
    if (_loadingIncomingAlerts) return;
    _loadingIncomingAlerts = true;
    try {
      final alerts = await NotificationService.pendingSafetyAlerts();
      // Someone who already answered doesn't need to keep seeing this
      // card once their response has gone through.
      final pending = alerts
          .where((a) =>
              (a['responseStatus']?.toString() ?? 'pending') == 'pending')
          .toList();
      AppSession.instance.setBackendPendingAlertCount(pending.length);
      if (mounted) setState(() => _incomingAlerts = pending);
    } catch (e) {
      // TODO(debug): remove once incoming alerts are confirmed reliable —
      // this used to fail completely silently, which made "no alert" and
      // "request failed" indistinguishable from the UI.
      debugPrint('SafetyU: failed to load incoming alerts -> $e');
    } finally {
      _loadingIncomingAlerts = false;
    }
  }

  void _openAlertDetail(Map<String, dynamic> alert) {
    final owner = Contact(
      id: alert['ownerUserId']?.toString() ?? '',
      fullName: alert['ownerName']?.toString() ?? 'A trusted friend',
      phone: alert['ownerPhone']?.toString() ?? '',
      email: '',
      relationship: 'Trusted Contact',
      status: ContactStatus.friend,
    );
    final request = HelpRequest(
      requesterName: owner.fullName,
      requesterPhone: owner.phone,
      destination: alert['message']?.toString() ?? 'their destination',
      location: null,
      distanceKm: null,
      requestedAt: DateTime.tryParse(alert['notifiedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
    final thisId = alert['notificationId']?.toString();
    // Repeated test/duplicate alerts from the same person pile up fast.
    // Responding to one is clearly meant to cover all of them, not make
    // her tap through each one individually.
    final siblingIds = _incomingAlerts
        .where((a) =>
            a['ownerUserId']?.toString() == owner.id &&
            a['notificationId']?.toString() != thisId)
        .map((a) => a['notificationId']?.toString())
        .whereType<String>()
        .toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AlertDetailScreen(
          contact: owner,
          request: request,
          notificationId: thisId,
          siblingNotificationIds: siblingIds,
        ),
      ),
    ).then((_) {
      // She may have responded from there — drop it from the pending list
      // and pick up anything new.
      _loadIncomingAlerts();
    });
  }

  void _onNavTap(int index) {
    if (index == _navIndex) return;
    switch (index) {
      case 1:
        Navigator.pushReplacementNamed(context, '/contacts');
        break;
      case 2:
        Navigator.pushReplacementNamed(context, '/history');
        break;
      case 3:
        Navigator.pushReplacementNamed(context, '/profile');
        break;
    }
  }

  void _logout() {
    AppSession.instance.signOut();
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.navy,
                    backgroundImage: AppSession.instance.profilePhotoPath !=
                            null
                        ? FileImage(File(AppSession.instance.profilePhotoPath!))
                        : null,
                    child: AppSession.instance.profilePhotoPath == null
                        ? Text(
                            AppSession.instance.initials,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Welcome back',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textSecondary)),
                        Text(
                          AppSession.instance.fullName.isEmpty
                              ? 'Member'
                              : AppSession.instance.fullName,
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pushNamed(context, '/notifications'),
                    child: AnimatedBuilder(
                      animation: AppSession.instance,
                      builder: (context, _) {
                        final unread =
                            AppSession.instance.unreadNotificationCount;
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.card,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Icon(Icons.notifications_none,
                                    color: AppColors.textPrimary, size: 20),
                              ),
                              if (unread > 0)
                                Positioned(
                                  top: -4,
                                  right: -4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 2),
                                    constraints: const BoxConstraints(
                                        minWidth: 18, minHeight: 18),
                                    decoration: BoxDecoration(
                                      color: AppColors.danger,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: AppColors.background,
                                          width: 2),
                                    ),
                                    child: Text(
                                      unread > 9 ? '9+' : '$unread',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        height: 1.15,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  GestureDetector(
                    onTap: _logout,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Icon(Icons.logout,
                          color: AppColors.textPrimary, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                height: 160,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.navy, AppColors.navyDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.all(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('You are protected',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800)),
                          SizedBox(height: 6),
                          Text('No active safety session',
                              style: TextStyle(
                                  color: Colors.white60, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.shield,
                          color: Colors.white, size: 22),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('Quick Actions',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.play_circle_fill,
                      label: 'Start Safety\nSession',
                      background: AppColors.navy,
                      iconColor: Colors.white,
                      textColor: Colors.white,
                      onTap: () {
                        Navigator.pushNamed(context, '/session-setup');
                      },
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.warning_amber,
                      label: 'Emergency\nAssistant',
                      background: AppColors.dangerLight,
                      iconColor: AppColors.danger,
                      textColor: AppColors.danger,
                      onTap: () {
                        Navigator.pushNamed(context, '/emergency-sos');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_incomingAlerts.isNotEmpty) ...[
                _IncomingAlertsPanel(
                  alerts: _incomingAlerts,
                  onOpenDetail: _openAlertDetail,
                ),
                const SizedBox(height: 20),
              ],
              _ContactResponsesPanel(onRefresh: _loadAlertStatus),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      bottomNavigationBar:
          AppBottomNav(currentIndex: _navIndex, onTap: _onNavTap),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color iconColor;
  final Color textColor;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.background,
    required this.iconColor,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 120,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 26),
            const Spacer(),
            Text(label,
                style: TextStyle(
                    color: textColor,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.25)),
          ],
        ),
      ),
    );
  }
}

/// Shown on Home when *this* person is a trusted contact who's been
/// notified by someone else's safety session — the counterpart to
/// [_ContactResponsesPanel] below, which is the owner's own view of who
/// they alerted. This is where the trust/contact side actually confirms
/// ("Confirm" = Can Help) instead of passively seeing a "Waiting…" chip
/// meant for the person who started the session.
class _IncomingAlertsPanel extends StatelessWidget {
  final List<Map<String, dynamic>> alerts;
  final void Function(Map<String, dynamic> alert) onOpenDetail;

  const _IncomingAlertsPanel(
      {required this.alerts, required this.onOpenDetail});

  String _relativeTime(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.dangerLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_active,
                  size: 18, color: AppColors.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  alerts.length == 1
                      ? 'You were notified'
                      : 'You were notified (${alerts.length})',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.danger),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'A trusted friend started a safety session and needs to know you got this.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < alerts.length && i < 3; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.border),
            _IncomingAlertRow(
              alert: alerts[i],
              relativeTime: _relativeTime(
                DateTime.tryParse(alerts[i]['notifiedAt']?.toString() ?? '') ??
                    DateTime.now(),
              ),
              onTap: () => onOpenDetail(alerts[i]),
            ),
          ],
          if (alerts.length > 3) ...[
            const SizedBox(height: 6),
            Text(
              '+${alerts.length - 3} more — confirming one clears the rest from the same person.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _IncomingAlertRow extends StatelessWidget {
  final Map<String, dynamic> alert;
  final String relativeTime;
  final VoidCallback onTap;

  const _IncomingAlertRow({
    required this.alert,
    required this.relativeTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ownerName = alert['ownerName']?.toString() ?? 'A trusted friend';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ownerName,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text('Notified $relativeTime',
                        style: TextStyle(
                            fontSize: 10.5, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onTap,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text("Can't Help"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text('Confirm'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shown under the quick actions once a session has actually alerted one
/// or more trusted contacts. Since a person can select more than one
/// contact, this makes it visible right on Home who's been notified and
/// whether they've responded yet — including if a contact's window timed
/// out with no response, so the person immediately knows to expect the
/// next contact (or Emergency Responders) to pick it up instead.
class _ContactResponsesPanel extends StatelessWidget {
  final Future<void> Function() onRefresh;
  const _ContactResponsesPanel({required this.onRefresh});
  String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty) return parts[0][0].toUpperCase();
    return '?';
  }

  String _relativeTime(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSession.instance,
      builder: (context, _) {
        final responses = AppSession.instance.currentAlertResponses;
        if (responses.isEmpty) {
          return const SizedBox.shrink();
        }
        final respondedCount = responses
            .where((r) => r.status != ContactResponseStatus.pending)
            .length;
        return GestureDetector(
          onTap: onRefresh,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.groups_outlined,
                        size: 18, color: AppColors.navy),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your Alert Status',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.navy.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$respondedCount/${responses.length} responded',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Who was notified and who has responded so far.',
                  style:
                      TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                for (int i = 0; i < responses.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: AppColors.border),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor:
                              AppColors.navy.withValues(alpha: 0.1),
                          child: Text(
                            _initials(responses[i].contactName),
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.navy),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                responses[i].contactName,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Notified ${_relativeTime(responses[i].notifiedAt)}',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusChip(status: responses[i].status),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  final ContactResponseStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final Color color;
    late final IconData icon;

    switch (status) {
      case ContactResponseStatus.pending:
        label = 'Waiting…';
        color = const Color(0xFFE59A2E);
        icon = Icons.hourglass_top;
        break;
      case ContactResponseStatus.canHelp:
        label = 'Can Help';
        color = AppColors.success;
        icon = Icons.check_circle;
        break;
      case ContactResponseStatus.cantHelp:
        label = "Can't Help";
        color = AppColors.danger;
        icon = Icons.cancel;
        break;
      case ContactResponseStatus.timedOut:
        label = 'No response';
        color = AppColors.textMuted;
        icon = Icons.timer_off;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}
