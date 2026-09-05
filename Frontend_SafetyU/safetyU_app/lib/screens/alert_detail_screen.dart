import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../theme/app_theme.dart';
import '../models/contact.dart';
import '../models/help_request.dart';
import '../models/contact_response_state.dart';
import '../services/app_session.dart';
import 'alert_response_result_screen.dart';

/// "Alert detail" — what a trusted contact sees when they open a safety
/// session alert. They decide right here whether they can help — there's
/// no separate "Can you Help?" middle screen anymore.
class AlertDetailScreen extends StatelessWidget {
  final Contact contact;
  final HelpRequest request;

  const AlertDetailScreen({
    super.key,
    required this.contact,
    required this.request,
  });

  String _formatClock(DateTime t) {
    final hour24 = t.hour;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $period';
  }

  void _respond(BuildContext context, AlertResponseOutcome outcome) {
    AppSession.instance.recordContactOutcome(
      contact.id,
      outcome == AlertResponseOutcome.canHelp
          ? ContactResponseStatus.canHelp
          : ContactResponseStatus.cantHelp,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AlertResponseResultScreen(
          contact: contact,
          request: request,
          outcome: outcome,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = request.location;
    final distanceLabel = request.distanceKm != null
        ? '${request.distanceKm!.toStringAsFixed(1)} km'
        : 'Unavailable';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Alert detail',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
            Text(
              'View and respond to this alert',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 180,
                        width: double.infinity,
                        child: location != null
                            ? FlutterMap(
                                options: MapOptions(
                                  initialCenter: location,
                                  initialZoom: 14.5,
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
                              )
                            : Container(
                                color: AppColors.card,
                                alignment: Alignment.center,
                                child: Text(
                                  'Location unavailable',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.textSecondary),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Contact identity card — the person's own profile
                    // avatar/initials, not a generic mascot.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor:
                                AppColors.navy.withValues(alpha: 0.1),
                            child: Text(
                              request.requesterName.isNotEmpty
                                  ? request.requesterName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                  color: AppColors.navy,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      request.requesterName,
                                      style: TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.textPrimary),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.success
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        'Online',
                                        style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.success),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.place_outlined,
                                        size: 13, color: AppColors.textMuted),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'Destination: ${request.destination}',
                                        style: TextStyle(
                                            fontSize: 12.5,
                                            color: AppColors.textSecondary),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(Icons.schedule,
                                        size: 13, color: AppColors.textMuted),
                                    const SizedBox(width: 4),
                                    Text(
                                      _formatClock(request.requestedAt),
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: AppColors.textMuted),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Distance + alert time — Route was dropped since this
                    // app has no real routing data to show honestly.
                    Row(
                      children: [
                        Expanded(
                          child: _InfoTile(
                            icon: Icons.social_distance,
                            label: 'Distance',
                            value: distanceLabel,
                            color: AppColors.success,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _InfoTile(
                            icon: Icons.access_time,
                            label: 'Alert Time',
                            value: _formatClock(request.requestedAt),
                            color: AppColors.navy,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.shield_outlined,
                              size: 18, color: AppColors.success),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${request.requesterName} has triggered an alert. Please check the location and respond if needed.',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textPrimary,
                                  height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: OutlinedButton(
                        onPressed: () =>
                            _respond(context, AlertResponseOutcome.cantHelp),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppColors.danger),
                        ),
                        child: Text("I Can't Help",
                            style: TextStyle(color: AppColors.danger)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: () =>
                            _respond(context, AlertResponseOutcome.canHelp),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                        ),
                        child: Text('Respond to ${request.requesterName}'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}
