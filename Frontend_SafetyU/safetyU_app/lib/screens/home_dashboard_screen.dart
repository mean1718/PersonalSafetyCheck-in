import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../services/app_session.dart';
import '../models/contact_response_state.dart';

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  int _navIndex = 0;

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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.navy,
                    child: Text(
                      AppSession.instance.initials,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700),
                    ),
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
              _ContactResponsesPanel(),
              const Spacer(),
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

/// Shown under the quick actions once a session has actually alerted one
/// or more trusted contacts. Since a person can select more than one
/// contact, this makes it visible right on Home who's been notified and
/// whether they've responded yet — including if a contact's window timed
/// out with no response, so the person immediately knows to expect the
/// next contact (or Emergency Responders) to pick it up instead.
class _ContactResponsesPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSession.instance,
      builder: (context, _) {
        final responses = AppSession.instance.currentAlertResponses;
        if (responses.isEmpty) {
          return const SizedBox.shrink();
        }
        return Container(
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
                  Icon(Icons.groups_outlined, size: 18, color: AppColors.navy),
                  const SizedBox(width: 8),
                  Text(
                    'Your Alert Status',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Who was notified and who has responded so far.',
                style:
                    TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              ...responses.map((r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            r.contactName,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary),
                          ),
                        ),
                        _StatusChip(status: r.status),
                      ],
                    ),
                  )),
            ],
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
