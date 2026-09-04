import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../models/incident.dart';
import '../services/app_session.dart';
import '../widgets/case_status_widgets.dart';

class CaseDetailScreen extends StatefulWidget {
  const CaseDetailScreen({super.key});

  @override
  State<CaseDetailScreen> createState() => _CaseDetailScreenState();
}

class _CaseDetailScreenState extends State<CaseDetailScreen> {
  Incident? _findIncident(BuildContext context) {
    final id = ModalRoute.of(context)?.settings.arguments as String?;
    if (id == null) return null;
    for (final incident in AppSession.instance.activeIncidents) {
      if (incident.id == id) return incident;
    }
    return null;
  }

  Future<void> _callPerson(Incident incident) async {
    final digits = incident.phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: digits);
    try {
      final launched = await launchUrl(uri);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not open the dialer for ${incident.phone}')));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not open the dialer for ${incident.phone}')));
    }
  }

  void _takeCase(Incident incident) {
    AppSession.instance
        .setIncidentStatus(incident.id, IncidentStatus.inProgress);
    setState(() {});
  }

  void _cancelCase(Incident incident) {
    AppSession.instance.setIncidentStatus(incident.id, IncidentStatus.newCase);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final incident = _findIncident(context);

    if (incident == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
            backgroundColor: AppColors.navyDark,
            foregroundColor: Colors.white,
            title: const Text('Case Details')),
        body: Center(
            child: Text('This case is no longer available.',
                style: TextStyle(color: AppColors.textSecondary))),
      );
    }

    final inProgress = incident.status == IncidentStatus.inProgress;
    final resolved = incident.status == IncidentStatus.resolved;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navyDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Case Details',
            style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                      radius: 26,
                      backgroundColor: AppColors.navy.withValues(alpha: 0.1),
                      child: Icon(Icons.person, color: AppColors.navy)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(incident.personName,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800)),
                        Text(
                            incident.phone.isEmpty
                                ? 'No phone on file'
                                : incident.phone,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  CaseStatusBadge(status: incident.status, filled: true),
                ],
              ),
              const SizedBox(height: 20),
              _DetailRow(
                  icon: Icons.access_time,
                  label: 'Emergency Time',
                  value: formatClockTime(incident.startedAt)),
              const SizedBox(height: 12),
              _DetailRow(
                  icon: Icons.place_outlined,
                  label: 'Location',
                  value: incident.destination),
              if (incident.locationIsStale) ...[
                const SizedBox(height: 6),
                const Text(
                    '⚠ Last known location — live signal was unavailable',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFFE59A2E))),
              ],
              const SizedBox(height: 20),
              if (inProgress) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 180,
                    child: FlutterMap(
                      options: MapOptions(
                          initialCenter: incident.location, initialZoom: 15.0),
                      children: [
                        TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.safetyu.app'),
                        MarkerLayer(markers: [
                          Marker(
                              point: incident.location,
                              child: Icon(Icons.location_on,
                                  color: AppColors.danger, size: 36))
                        ]),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _cancelCase(incident),
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 46)),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _callPerson(incident),
                        icon: const Icon(Icons.call, size: 16),
                        label: const Text('Call'),
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 46),
                            foregroundColor: AppColors.navy),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () async {
                      final result = await Navigator.pushNamed(
                          context, '/update-case',
                          arguments: incident.id);
                      if (result == true && mounted) setState(() {});
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26))),
                    child: const Text('Update Status',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ] else if (resolved) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: AppColors.success),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          incident.resolvedAt != null
                              ? 'Resolved at ${formatClockTime(incident.resolvedAt!)}'
                              : 'This case has been resolved.',
                          style: TextStyle(
                              fontSize: 13,
                              color: AppColors.success,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text('View on Map'),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => _takeCase(incident),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26))),
                    child: const Text('Take Case',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Back To Cases',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.navy),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 11.5, color: AppColors.textSecondary)),
              Text(value,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ],
          ),
        ),
      ],
    );
  }
}
