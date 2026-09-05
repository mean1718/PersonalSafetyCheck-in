import 'package:flutter/material.dart';
import '../models/incident.dart';
import '../theme/app_theme.dart';

/// Color used to represent an [IncidentStatus] across the Cases / Case
/// Details / Report screens, so New/In Progress/Resolved always look the
/// same wherever they show up.
Color caseStatusColor(IncidentStatus status) {
  switch (status) {
    case IncidentStatus.newCase:
      return AppColors.danger;
    case IncidentStatus.inProgress:
      return const Color(0xFFE59A2E);
    case IncidentStatus.resolved:
      return AppColors.success;
  }
}

/// Small pill/label showing a case's status in its status color, used on
/// case list rows and detail headers.
class CaseStatusBadge extends StatelessWidget {
  final IncidentStatus status;
  final bool filled;

  const CaseStatusBadge({super.key, required this.status, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final color = caseStatusColor(status);
    if (!filled) {
      return Text(
        status.label.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.4,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

/// "10:24 AM" style clock formatting shared by case screens.
String formatClockTime(DateTime t) {
  final h24 = t.hour;
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  final m = t.minute.toString().padLeft(2, '0');
  final period = h24 >= 12 ? 'PM' : 'AM';
  return '$h12:$m $period';
}

/// "3 min ago" / "2 h ago" style relative time shared by case screens.
String formatElapsed(DateTime since) {
  final diff = DateTime.now().difference(since);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}
