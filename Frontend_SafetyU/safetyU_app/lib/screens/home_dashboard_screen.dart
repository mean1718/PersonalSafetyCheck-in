import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../services/app_session.dart';
import '../services/check_in_service.dart';
import '../services/notification_service.dart';
import '../services/trusted_contact_service.dart';
import '../services/alert_sound.dart';
import '../models/contact_response_state.dart';
import '../models/contact.dart';
import '../models/help_request.dart';
import '../widgets/paywall_dialogs.dart';
import 'alert_detail_screen.dart';
import 'dart:io';
import 'dart:math' as math;

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
  final Set<String> _seenAlertIds = {};

  // "X is safe now" cards — shown once the owner confirms Safe, then
  // auto-dismissed 2 minutes after the person has actually seen it here,
  // rather than disappearing the instant it resolves or lingering forever.
  List<Map<String, dynamic>> _resolvedAlerts = [];
  final Set<String> _resolvedAlertsWithDismissTimerStarted = {};

  // Without this, this screen only ever loads incoming alerts once, in
  // initState. So if Dan is just sitting on Home when Theara taps "I'm
  // Safe", nothing here ever re-fetches — his "You were notified" card
  // sits there forever even though the session ended, because nothing
  // told this screen to go check again. Poll while Home is visible so
  // it picks up her Safe confirmation (and any new alert) on its own.
  Timer? _incomingAlertsPollTimer;

  @override
  void initState() {
    super.initState();
    _loadAlertStatus();
    _loadIncomingAlerts();
    _loadResolvedAlerts();
    _loadPendingTrustRequestCount();
    _incomingAlertsPollTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      _loadIncomingAlerts();
      _loadResolvedAlerts();
    });
  }

  @override
  void dispose() {
    _incomingAlertsPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _openPlans() async {
    // AppSession.upgradeToPro()/purchaseExtraSlots() both call
    // notifyListeners(), and the status card below is wrapped in an
    // AnimatedBuilder listening to AppSession.instance, so a successful
    // purchase here refreshes the card's "FREE"/"PRO" state (and swaps the
    // inline plan carousel for the Pro summary row) the moment the dialog
    // closes — no extra setState needed.
    await showPlansDialog(context);
  }

  Future<void> _loadResolvedAlerts() async {
    try {
      final resolved = await NotificationService.recentlyResolvedSafetyAlerts();
      if (!mounted) return;
      // Only ever ADD newly-seen alerts here — never replace the whole
      // list with whatever the backend reports right now. Each alert
      // gets marked read a few lines below, which means the very next
      // poll (this runs every 6s) would no longer include it, and a
      // blanket setState(() => _resolvedAlerts = resolved) would wipe it
      // off screen almost immediately instead of the intended 30s. Also
      // what let this ever show live at all — since only a brand-new
      // login started with an empty, freshly-unread list.
      for (final alert in resolved) {
        final id = alert['notificationId']?.toString();
        if (id == null || _resolvedAlertsWithDismissTimerStarted.contains(id)) {
          continue;
        }
        _resolvedAlertsWithDismissTimerStarted.add(id);
        setState(() => _resolvedAlerts = [..._resolvedAlerts, alert]);
        // Mark it read right away, not just after the window — this is
        // what stops it from showing again on a future login. Waiting
        // until dismissal would leave it "unread" (and so re-fetchable) if
        // the person logs out before the timer finishes.
        NotificationService.markRead(id).catchError((e) {
          debugPrint('Mark resolved-alert read skipped: $e');
        });
        Future.delayed(const Duration(seconds: 30), () {
          if (!mounted) return;
          setState(() {
            _resolvedAlerts = _resolvedAlerts
                .where((a) => a['notificationId'] != id)
                .toList();
          });
        });
      }
    } catch (_) {
      // Offline / not reachable — leave whatever was last loaded in place.
    }
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
      // The badge should clear once the person has actually looked at
      // Notifications, then climb again only for genuinely new alerts —
      // "pending" alone doesn't capture that, since it stays true forever
      // until someone responds. "isRead" is what tracks whether they've
      // actually seen it.
      final unreadPending = pending.where((a) => a['isRead'] != true).length;
      AppSession.instance.setBackendPendingAlertCount(unreadPending);
      // Sound only for alerts we haven't already shown/played for — this
      // screen isn't polling continuously, but it does reload after
      // viewing a detail, so without this a resolved-then-reopened alert
      // list would replay the sound for the same alert again.
      final newOnes = pending.where((a) =>
          !_seenAlertIds.contains(a['notificationId']?.toString() ?? ''));
      if (newOnes.isNotEmpty) {
        AlertSoundService.playAlert(times: 3);
      }
      _seenAlertIds
          .addAll(pending.map((a) => a['notificationId']?.toString() ?? ''));
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
              AnimatedBuilder(
                animation: AppSession.instance,
                builder: (context, _) {
                  final isPro = AppSession.instance.isProActive;
                  return _ProtectedStatusCard(
                    isPro: isPro,
                    onTap: _openPlans,
                  );
                },
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
                      icon: Icons.play_arrow,
                      label: 'Start Safety\nSession',
                      background: AppColors.navy,
                      badgeIconColor: AppColors.navy,
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
                      badgeIconColor: AppColors.danger,
                      textColor: AppColors.danger,
                      onTap: () {
                        Navigator.pushNamed(context, '/emergency-sos');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_resolvedAlerts.isNotEmpty) ...[
                _ResolvedSafeAlertsPanel(alerts: _resolvedAlerts),
                const SizedBox(height: 20),
              ],
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

/// The "YOU ARE Protected" hero card on Home. For free-plan users, this now
/// embeds the swipeable Free / Pro / Pay-Per-Contact plan carousel directly
/// ([PlanPromoInlineCard]) instead of showing a single pulsing "Upgrade to
/// Pro" chip and relying on a separate timed popup — the nudge just lives
/// here permanently instead of interrupting the person 30s after they land
/// on Home. Pro users still get the gold-accented card and a plain "Pro"
/// features row, since there's nothing left to upsell them on.
class _ProtectedStatusCard extends StatefulWidget {
  final bool isPro;
  final VoidCallback onTap;

  const _ProtectedStatusCard({
    required this.isPro,
    required this.onTap,
  });

  @override
  State<_ProtectedStatusCard> createState() => _ProtectedStatusCardState();
}

class _ProtectedStatusCardState extends State<_ProtectedStatusCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // IMPORTANT:
    // Free users use the existing promo card directly.
    // There is NO extra navy/dark-blue container around it anymore.
    if (!widget.isPro) {
      return PlanPromoInlineCard(onSeeAllPlans: widget.onTap);
    }

    return _buildProCard();
  }

  Widget _buildProCard() {
    const accent = Color(0xFFFFC857);
    const gradient = [Color(0xFF30244E), Color(0xFF141935)];

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final glow = 0.10 + (0.07 * (0.5 + 0.5 * _wave(t)));
        final sweep = -1.5 + (t * 3.0);

        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(22),
            splashColor: accent.withValues(alpha: 0.12),
            child: Ink(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: accent.withValues(alpha: 0.12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: glow),
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: FractionallySizedBox(
                          widthFactor: .55,
                          alignment: Alignment(sweep, 0),
                          child: Transform.rotate(
                            angle: -.18,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    Colors.white.withValues(alpha: .055),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: -65,
                      right: -35,
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              accent.withValues(alpha: .17),
                              accent.withValues(alpha: .03),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: _buildProContent(accent),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProContent(Color accent) {
    return Row(
      children: [
        Transform.scale(
          scale: 1.0 + (0.025 * (0.5 + 0.5 * _wave(_controller.value))),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: .10),
              border: Border.all(color: accent.withValues(alpha: .32)),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: .13),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Icon(
              Icons.workspace_premium_rounded,
              color: accent,
              size: 25,
            ),
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'YOU ARE PROTECTED',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .72),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.05,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'PRO',
                      style: TextStyle(
                        color: accent,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .6,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              const Text(
                'Premium protection active',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Unlimited contacts · all premium features',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .62),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .08),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.arrow_forward_ios_rounded,
            color: Colors.white70,
            size: 14,
          ),
        ),
      ],
    );
  }

  double _wave(double value) {
    return math.sin(value * 6.283185307179586);
  }
}

class _QuickActionCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color badgeIconColor;
  final Color textColor;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.background,
    required this.badgeIconColor,
    required this.textColor,
    required this.onTap,
  });

  @override
  State<_QuickActionCard> createState() => _QuickActionCardState();
}

class _QuickActionCardState extends State<_QuickActionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDanger = widget.badgeIconColor == AppColors.danger;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 150,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDanger
                  ? [
                      widget.background,
                      widget.background.withValues(alpha: 0.88),
                    ]
                  : [
                      widget.background,
                      AppColors.navyDark,
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(19),
            border: Border.all(
              color: isDanger
                  ? AppColors.danger.withValues(alpha: 0.13)
                  : Colors.white.withValues(alpha: 0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: widget.badgeIconColor.withValues(
                  alpha: _pressed ? 0.16 : 0.08,
                ),
                blurRadius: _pressed ? 18 : 12,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.icon,
                      color: widget.badgeIconColor,
                      size: 22,
                    ),
                  ),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.42),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: widget.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  height: 1.16,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Text(
                    'Open',
                    style: TextStyle(
                      color: widget.textColor.withValues(alpha: 0.58),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: _pressed ? 34 : 32,
                    height: _pressed ? 34 : 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: widget.textColor,
                      size: 17,
                    ),
                  ),
                ],
              ),
            ],
          ),
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
class _ResolvedSafeAlertsPanel extends StatelessWidget {
  final List<Map<String, dynamic>> alerts;
  const _ResolvedSafeAlertsPanel({required this.alerts});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < alerts.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.check_circle, size: 18, color: AppColors.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${alerts[i]['ownerName'] ?? 'They'} is safe now',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.success),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.location_on_outlined, size: 17),
              label: const Text('View Location'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
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
        final isSafe = AppSession.instance.currentSessionMarkedSafe;
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
              border: Border.all(
                  color: isSafe ? AppColors.success : AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (isSafe ? AppColors.success : AppColors.navy)
                            .withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                          isSafe
                              ? Icons.verified_user_outlined
                              : Icons.groups_outlined,
                          size: 16,
                          color: isSafe ? AppColors.success : AppColors.navy),
                    ),
                    const SizedBox(width: 10),
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
                        color: isSafe
                            ? AppColors.success.withValues(alpha: 0.12)
                            : respondedCount == 0
                                ? AppColors.background
                                : AppColors.navy.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isSafe
                            ? 'Safe'
                            : respondedCount == 0
                                ? 'Not Responded'
                                : '$respondedCount/${responses.length} responded',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isSafe
                                ? AppColors.success
                                : respondedCount == 0
                                    ? AppColors.textSecondary
                                    : AppColors.navy),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isSafe
                      ? "You confirmed you're safe. Here's who was notified during that session."
                      : 'Who was notified and who has responded so far.',
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
