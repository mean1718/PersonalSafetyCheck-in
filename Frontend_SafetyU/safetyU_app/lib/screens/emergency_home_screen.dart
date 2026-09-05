import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_theme.dart';
import '../models/incident.dart';
import '../models/verification_status.dart';
import '../services/app_session.dart';
import '../services/alert_sound.dart';
import '../widgets/responder_bottom_nav.dart';

/// Officer Dashboard — landing screen for the Emergency Responder role.
/// Shows a live "new emergency" banner, a mini map, real case counts, and
/// recent activity, all computed from AppSession.activeIncidents rather
/// than fabricated example data.
class EmergencyHomeScreen extends StatefulWidget {
  const EmergencyHomeScreen({super.key});

  @override
  State<EmergencyHomeScreen> createState() => _EmergencyHomeScreenState();
}

class _EmergencyHomeScreenState extends State<EmergencyHomeScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionSub;
  LatLng? _myPosition;
  int _lastKnownIncidentCount = 0;

  @override
  void initState() {
    super.initState();
    _lastKnownIncidentCount = AppSession.instance.activeIncidents.length;
    _initLocationTracking();
    AppSession.instance.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    AppSession.instance.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    final count = AppSession.instance.activeIncidents.length;
    if (count > _lastKnownIncidentCount) {
      // A brand-new emergency case just came in — alert the officer for real.
      AlertSoundService.playAlert(times: 4);
    }
    _lastKnownIncidentCount = count;
    if (mounted) setState(() {});
  }

  Future<void> _initLocationTracking() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      setState(() => _myPosition = LatLng(pos.latitude, pos.longitude));
    } catch (_) {}

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 15),
    ).listen((pos) {
      if (!mounted) return;
      setState(() => _myPosition = LatLng(pos.latitude, pos.longitude));
    });
  }

  void _logout() {
    AppSession.instance.signOut();
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  void _onNavTap(int index) {
    switch (index) {
      case 1:
        Navigator.pushNamed(context, '/cases');
        break;
      case 2:
        Navigator.pushNamed(context, '/reports');
        break;
      case 3:
        Navigator.pushNamed(context, '/profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AppSession.instance.responderStatus != VerificationStatus.verified) {
      return _PendingVerificationView(
        onSimulateApproval: () => setState(() =>
            AppSession.instance.responderStatus = VerificationStatus.verified),
        onLogout: _logout,
      );
    }

    final incidents = AppSession.instance.activeIncidents;
    final newCount =
        incidents.where((i) => i.status == IncidentStatus.newCase).length;
    final inProgressCount =
        incidents.where((i) => i.status == IncidentStatus.inProgress).length;
    final resolvedCount =
        incidents.where((i) => i.status == IncidentStatus.resolved).length;
    final newestIncident =
        incidents.where((i) => i.status == IncidentStatus.newCase).isNotEmpty
            ? incidents.firstWhere((i) => i.status == IncidentStatus.newCase)
            : null;

    final recentlyResolved = incidents
        .where((i) => i.status == IncidentStatus.resolved)
        .toList()
      ..sort((a, b) =>
          (b.resolvedAt ?? b.startedAt).compareTo(a.resolvedAt ?? a.startedAt));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                        color: AppColors.navy,
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.local_police,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Incoming Officer',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textSecondary)),
                        Text(
                          AppSession.instance.fullName.isEmpty
                              ? 'Officer'
                              : AppSession.instance.fullName,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pushNamed(context, '/notifications'),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: AppColors.card,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.border)),
                      child: Icon(Icons.notifications_none,
                          color: AppColors.textPrimary, size: 20),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _logout,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: AppColors.card,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.border)),
                      child: Icon(Icons.logout,
                          color: AppColors.textPrimary, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (newestIncident != null)
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/case-detail',
                      arguments: newestIncident.id),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.dangerLight,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFFC9C0)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: AppColors.danger),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('New Emergency',
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.danger)),
                              Text('${newestIncident.personName} needs help',
                                  style: TextStyle(
                                      fontSize: 12, color: AppColors.danger)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: AppColors.danger),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 160,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                        initialCenter:
                            _myPosition ?? const LatLng(11.5696, 104.9210),
                        initialZoom: 13.0),
                    children: [
                      TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.safetyu.app'),
                      MarkerLayer(
                        markers: [
                          if (_myPosition != null)
                            Marker(
                                point: _myPosition!,
                                child: const Icon(Icons.my_location,
                                    color: Colors.blueAccent, size: 26)),
                          for (final incident in incidents.where(
                              (i) => i.status != IncidentStatus.resolved))
                            Marker(
                                point: incident.location,
                                child: Icon(Icons.location_on,
                                    color: AppColors.danger, size: 30)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text("Today's Overview",
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                      child: _StatPill(
                          count: newCount,
                          label: 'New',
                          color: AppColors.danger)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _StatPill(
                          count: inProgressCount,
                          label: 'In Progress',
                          color: const Color(0xFFE59A2E))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _StatPill(
                          count: resolvedCount,
                          label: 'Resolved',
                          color: AppColors.success)),
                ],
              ),
              const SizedBox(height: 22),
              Text('Recent Activity',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 10),
              if (recentlyResolved.isEmpty)
                Text('No resolved cases yet.',
                    style: TextStyle(
                        fontSize: 12.5, color: AppColors.textSecondary))
              else
                ...recentlyResolved.take(3).map(
                      (incident) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                  color:
                                      AppColors.success.withValues(alpha: 0.12),
                                  shape: BoxShape.circle),
                              child: Icon(Icons.check,
                                  color: AppColors.success, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Case #${incident.id.substring(incident.id.length - 3)} marked as resolved',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
      bottomNavigationBar:
          ResponderBottomNav(currentIndex: 0, onTap: _onNavTap),
    );
  }
}

class _StatPill extends StatelessWidget {
  final int count;
  final String label;
  final Color color;

  const _StatPill(
      {required this.count, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text('$count',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _PendingVerificationView extends StatelessWidget {
  final VoidCallback onSimulateApproval;
  final VoidCallback onLogout;

  const _PendingVerificationView(
      {required this.onSimulateApproval, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.08),
                    shape: BoxShape.circle),
                child:
                    Icon(Icons.hourglass_top, color: AppColors.navy, size: 38),
              ),
              const SizedBox(height: 22),
              Text('Your account is pending verification',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 10),
              Text(
                'Badge ID "${AppSession.instance.badgeId.isEmpty ? '—' : AppSession.instance.badgeId}" is under review. '
                'SafetyU cannot verify an officer\'s identity on its own — this requires a real department directory check on a backend, '
                'which this build does not have. You\'ll get access to real cases once an administrator approves your account.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.5),
              ),
              const SizedBox(height: 28),
              OutlinedButton(
                onPressed: onSimulateApproval,
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48)),
                child: const Text('(Demo only) Simulate Approval',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 10),
              TextButton(
                  onPressed: onLogout,
                  child: Text('Log Out',
                      style: TextStyle(color: AppColors.textSecondary))),
            ],
          ),
        ),
      ),
    );
  }
}
