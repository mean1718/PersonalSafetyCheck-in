import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../theme/app_theme.dart';
import '../models/contact.dart';
import '../models/help_request.dart';
import '../models/app_notification.dart';
import '../services/app_session.dart';

enum AlertResponseOutcome { canHelp, cantHelp, lateResponse }

/// The outcome screen after a trusted contact responds — "Can Help",
/// "Can't Help", or a "Late response" if the window already closed.
class AlertResponseResultScreen extends StatelessWidget {
  final Contact contact;
  final HelpRequest request;
  final AlertResponseOutcome outcome;

  const AlertResponseResultScreen({
    super.key,
    required this.contact,
    required this.request,
    required this.outcome,
  });

  void _markRequesterSafe(BuildContext context) {
    AppSession.instance.addNotification(
      title: request.requesterName,
      body: 'You marked ${request.requesterName} as safe.',
      kind: NotificationKind.trustedContact,
    );
    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${request.requesterName} is marked safe.')),
    );
  }

  void _viewLiveLocation(BuildContext context) {
    final location = request.location;
    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No live location shared yet.')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: 320,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: FlutterMap(
            options: MapOptions(initialCenter: location, initialZoom: 15),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.safetyu.app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: location,
                    child: Icon(Icons.location_on,
                        color: AppColors.danger, size: 38),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _backToHome(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    switch (outcome) {
      case AlertResponseOutcome.canHelp:
        return _CanHelpScaffold(
          request: request,
          onViewLiveLocation: () => _viewLiveLocation(context),
          onMarkSafe: () => _markRequesterSafe(context),
        );

      case AlertResponseOutcome.cantHelp:
        return _ResultScaffold(
          title: "Can't Help",
          icon: Icons.close,
          iconColor: AppColors.danger,
          subtitle:
              "Thanks for responding.\nDon't worry, another contact will help.",
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => _backToHome(context),
              child: const Text('Back To Home'),
            ),
          ),
        );

      case AlertResponseOutcome.lateResponse:
        return _ResultScaffold(
          title: 'Late response',
          icon: Icons.schedule,
          iconColor: AppColors.textMuted,
          subtitle:
              "Thanks for responding.\nDon't worry, another contact will help.",
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => _backToHome(context),
              child: const Text('Back To Home'),
            ),
          ),
        );
    }
  }
}

/// Dedicated, more polished layout for the "Can Help" success state — the
/// main destination of the whole respond flow, so it gets the most care.
class _CanHelpScaffold extends StatelessWidget {
  final HelpRequest request;
  final VoidCallback onViewLiveLocation;
  final VoidCallback onMarkSafe;

  const _CanHelpScaffold({
    required this.request,
    required this.onViewLiveLocation,
    required this.onMarkSafe,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.success.withValues(alpha: 0.22),
                      AppColors.success.withValues(alpha: 0.06),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.success.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 32),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                "You're Helping!",
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                '${request.requesterName} has been notified that you\'re on the way. Thanks for responding.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textSecondary,
                    height: 1.45),
              ),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.navy.withValues(alpha: 0.1),
                      child: Text(
                        request.requesterName.isNotEmpty
                            ? request.requesterName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                            color: AppColors.navy, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            request.requesterName,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Near ${request.destination}',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton.icon(
                  onPressed: onViewLiveLocation,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: AppColors.navy.withValues(alpha: 0.3)),
                  ),
                  icon: Icon(Icons.location_on, color: AppColors.navy),
                  label: Text('View Live Location',
                      style: TextStyle(
                          color: AppColors.navy, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: onMarkSafe,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success),
                  // Explicit about *who* this marks safe — this confirms
                  // the requester's safety, not the responder's own.
                  child: Text('Mark ${request.requesterName} as Safe'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultScaffold extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final String subtitle;
  final Widget child;

  const _ResultScaffold({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 40),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textSecondary,
                    height: 1.4),
              ),
              const Spacer(),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
