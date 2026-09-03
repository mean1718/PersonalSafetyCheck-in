import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../models/session_record.dart';
import '../services/app_session.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final int _navIndex = 2;
  SessionOutcome? _filter; // null = All

  void _onNavTap(int index) {
    if (index == _navIndex) return;
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/home');
        break;
      case 1:
        Navigator.pushReplacementNamed(context, '/contacts');
        break;
      case 3:
        Navigator.pushReplacementNamed(context, '/profile');
        break;
    }
  }

  Color _statusColor(SessionOutcome o) {
    switch (o) {
      case SessionOutcome.safe:
        return AppColors.success;
      case SessionOutcome.delayed:
        return const Color(0xFFE59A2E);
      case SessionOutcome.sos:
        return AppColors.danger;
    }
  }

  String _dateHeading(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(date.year, date.month, date.day);
    if (that == today) return 'Today';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatClock(DateTime t) {
    final h24 = t.hour;
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final period = h24 >= 12 ? 'PM' : 'AM';
    return '$h12:$m $period';
  }

  @override
  Widget build(BuildContext context) {
    final allHistory = AppSession.instance.sessionHistory;
    final filtered = _filter == null
        ? allHistory
        : allHistory.where((r) => r.outcome == _filter).toList();

    final safeCount =
        allHistory.where((r) => r.outcome == SessionOutcome.safe).length;
    final delayCount =
        allHistory.where((r) => r.outcome == SessionOutcome.delayed).length;
    final sosCount =
        allHistory.where((r) => r.outcome == SessionOutcome.sos).length;

    // Group by date (most recent first — sessionHistory is already inserted newest-first).
    final Map<String, List<SessionRecord>> grouped = {};
    for (final record in filtered) {
      final key = _dateHeading(record.startedAt);
      grouped.putIfAbsent(key, () => []).add(record);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        automaticallyImplyLeading: false,
        title: const Text('History',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Text(
                'Your safety session history',
                style:
                    TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  _FilterChip(
                      label: 'All',
                      selected: _filter == null,
                      onTap: () => setState(() => _filter = null)),
                  const SizedBox(width: 8),
                  _FilterChip(
                      label: 'Safe',
                      color: AppColors.success,
                      selected: _filter == SessionOutcome.safe,
                      onTap: () =>
                          setState(() => _filter = SessionOutcome.safe)),
                  const SizedBox(width: 8),
                  _FilterChip(
                      label: 'Delay',
                      color: const Color(0xFFE59A2E),
                      selected: _filter == SessionOutcome.delayed,
                      onTap: () =>
                          setState(() => _filter = SessionOutcome.delayed)),
                  const SizedBox(width: 8),
                  _FilterChip(
                      label: 'SOS',
                      color: AppColors.danger,
                      selected: _filter == SessionOutcome.sos,
                      onTap: () =>
                          setState(() => _filter = SessionOutcome.sos)),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No safety sessions logged yet.',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      children: grouped.entries.expand((entry) {
                        return [
                          Padding(
                            padding: const EdgeInsets.only(top: 12, bottom: 8),
                            child: Text(entry.key,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textMuted)),
                          ),
                          ...entry.value.map(
                            (record) => Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: record.outcome == SessionOutcome.sos
                                    ? AppColors.dangerLight
                                        .withValues(alpha: 0.5)
                                    : AppColors.card,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    margin: const EdgeInsets.only(right: 10),
                                    decoration: BoxDecoration(
                                        color: _statusColor(record.outcome),
                                        shape: BoxShape.circle),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(record.destination,
                                            style: const TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${_formatClock(record.startedAt)} — ${record.endedAt != null ? _formatClock(record.endedAt!) : "ongoing"}',
                                          style: TextStyle(
                                              fontSize: 11.5,
                                              color: AppColors.textSecondary),
                                        ),
                                        if (record.hadDelay)
                                          const Padding(
                                            padding: EdgeInsets.only(top: 2),
                                            child: Text(
                                                'Delayed during session',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFFE59A2E))),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _statusColor(record.outcome)
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      record.outcome.label,
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: _statusColor(record.outcome)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ];
                      }).toList(),
                    ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _SummaryStat(
                      count: safeCount,
                      label: 'Safe Sessions',
                      color: AppColors.success),
                  _SummaryStat(
                      count: delayCount,
                      label: 'Delays',
                      color: const Color(0xFFE59A2E)),
                  _SummaryStat(
                      count: sosCount,
                      label: 'SOS Triggered',
                      color: AppColors.danger),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar:
          AppBottomNav(currentIndex: _navIndex, onTap: _onNavTap),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? chipColor.withValues(alpha: 0.12) : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? chipColor : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? chipColor : AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final int count;
  final String label;
  final Color color;

  const _SummaryStat(
      {required this.count, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$count',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
      ],
    );
  }
}
