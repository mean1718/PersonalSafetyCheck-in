import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/incident.dart';
import '../services/app_session.dart';
import '../widgets/responder_bottom_nav.dart';
import '../widgets/case_status_widgets.dart';

class CasesScreen extends StatefulWidget {
  const CasesScreen({super.key});

  @override
  State<CasesScreen> createState() => _CasesScreenState();
}

class _CasesScreenState extends State<CasesScreen> {
  IncidentStatus? _filter; // null = All

  void _onNavTap(int index) {
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/emergency-home');
        break;
      case 2:
        Navigator.pushReplacementNamed(context, '/reports');
        break;
      case 3:
        Navigator.pushReplacementNamed(context, '/profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = AppSession.instance.activeIncidents;
    final filtered =
        _filter == null ? all : all.where((i) => i.status == _filter).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navyDark,
        elevation: 0,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: const Text('Cases',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  _FilterChip(
                      label: 'All',
                      selected: _filter == null,
                      onTap: () => setState(() => _filter = null)),
                  const SizedBox(width: 8),
                  _FilterChip(
                      label: 'New',
                      color: AppColors.danger,
                      selected: _filter == IncidentStatus.newCase,
                      onTap: () =>
                          setState(() => _filter = IncidentStatus.newCase)),
                  const SizedBox(width: 8),
                  _FilterChip(
                      label: 'In Progress',
                      color: const Color(0xFFE59A2E),
                      selected: _filter == IncidentStatus.inProgress,
                      onTap: () =>
                          setState(() => _filter = IncidentStatus.inProgress)),
                  const SizedBox(width: 8),
                  _FilterChip(
                      label: 'Resolved',
                      color: AppColors.success,
                      selected: _filter == IncidentStatus.resolved,
                      onTap: () =>
                          setState(() => _filter = IncidentStatus.resolved)),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 32),
                        child: Text('No cases here yet.',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 13)),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final incident = filtered[index];
                        return GestureDetector(
                          onTap: () => Navigator.pushNamed(
                              context, '/case-detail',
                              arguments: incident.id),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border(
                                  left: BorderSide(
                                      color: caseStatusColor(incident.status),
                                      width: 4)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          'Case #${incident.id.substring(incident.id.length - 3)}',
                                          style: const TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 2),
                                      Text(incident.personName,
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textSecondary)),
                                      const SizedBox(height: 2),
                                      Text(formatElapsed(incident.startedAt),
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textMuted)),
                                    ],
                                  ),
                                ),
                                CaseStatusBadge(
                                    status: incident.status, filled: true),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar:
          ResponderBottomNav(currentIndex: 1, onTap: _onNavTap),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;

  const _FilterChip(
      {required this.label,
      required this.selected,
      required this.onTap,
      this.color});

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppColors.navy;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? chipColor.withValues(alpha: 0.12) : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? chipColor : AppColors.border),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: selected ? chipColor : AppColors.textSecondary)),
      ),
    );
  }
}
