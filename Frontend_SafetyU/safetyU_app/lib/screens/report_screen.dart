import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../models/incident.dart';
import '../services/app_session.dart';
import '../widgets/responder_bottom_nav.dart';
import '../widgets/case_status_widgets.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  Future<void> _shareReport(List<dynamic> resolved) async {
    final buffer = StringBuffer('SafetyU — Resolved Cases Report\n\n');
    for (final incident in resolved) {
      buffer.writeln(
          'Case #${incident.id.toString().substring(incident.id.toString().length - 3)} — ${incident.personName}');
      buffer.writeln('  Location: ${incident.destination}');
      if (incident.resolvedAt != null)
        buffer.writeln('  Resolved: ${formatClockTime(incident.resolvedAt)}');
      buffer.writeln();
    }
    await Share.share(buffer.toString(),
        subject: 'SafetyU Resolved Cases Report');
  }

  void _onNavTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/emergency-home');
        break;
      case 1:
        Navigator.pushReplacementNamed(context, '/cases');
        break;
      case 3:
        Navigator.pushReplacementNamed(context, '/profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolved = AppSession.instance.activeIncidents
        .where((i) => i.status == IncidentStatus.resolved)
        .toList()
      ..sort((a, b) =>
          (b.resolvedAt ?? b.startedAt).compareTo(a.resolvedAt ?? a.startedAt));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navyDark,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Report',
            style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        actions: [
          if (resolved.isNotEmpty)
            IconButton(
                icon: const Icon(Icons.ios_share, color: Colors.white),
                onPressed: () => _shareReport(resolved)),
        ],
      ),
      body: SafeArea(
        top: false,
        child: resolved.isEmpty
            ? Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'No resolved cases yet. Once you resolve a case, a summary will show up here and you can share a report.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: resolved.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final incident = resolved[index];
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border)),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.12),
                              shape: BoxShape.circle),
                          child: Icon(Icons.check,
                              color: AppColors.success, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  'Case #${incident.id.substring(incident.id.length - 3)} — ${incident.personName}',
                                  style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700)),
                              Text(incident.destination,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary)),
                              if (incident.resolvedAt != null)
                                Text(
                                    'Resolved ${formatClockTime(incident.resolvedAt!)}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      bottomNavigationBar: ResponderBottomNav(
          currentIndex: 2, onTap: (i) => _onNavTap(context, i)),
    );
  }
}
