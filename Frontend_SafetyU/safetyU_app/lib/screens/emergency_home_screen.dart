import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../models/app_notification.dart';
import '../models/incident.dart';
import '../models/verification_status.dart';
import '../services/app_session.dart';

/// Dashboard for the Emergency Responder role: real escalated sessions
/// (see AppSession.activeIncidents) plotted on a real map, with call,
/// respond, and nearby-police-station lookup actions.
///
/// Since this is a single-device demo with no backend, incidents only
/// appear here once a User-role session actually escalates to "Emergency"
/// within this same app instance — there's no live multi-device feed.
class EmergencyHomeScreen extends StatefulWidget {
  const EmergencyHomeScreen({super.key});

  @override
  State<EmergencyHomeScreen> createState() => _EmergencyHomeScreenState();
}

class _EmergencyHomeScreenState extends State<EmergencyHomeScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionSub;
  LatLng? _myPosition;
  Timer? _clockTimer;

  final Map<String, String> _policeLookupResult = {};
  final Set<String> _policeLookupLoading = {};

  @override
  void initState() {
    super.initState();
    _initLocationTracking();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _clockTimer?.cancel();
    super.dispose();
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
          accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen((pos) {
      if (!mounted) return;
      setState(() => _myPosition = LatLng(pos.latitude, pos.longitude));
    });
  }

  String _elapsedLabel(DateTime startedAt) {
    final diff = DateTime.now().difference(startedAt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    final hours = diff.inMinutes ~/ 60;
    return '$hours h ${diff.inMinutes % 60} min ago';
  }

  double? _distanceKm(Incident incident) {
    final mine = _myPosition;
    if (mine == null) return null;
    final meters = Geolocator.distanceBetween(mine.latitude, mine.longitude,
        incident.location.latitude, incident.location.longitude);
    return meters / 1000;
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

  /// Real query against OpenStreetMap's free Overpass API for
  /// amenity=police nodes within 5km of the incident, picks the nearest.
  Future<void> _findNearestPolice(Incident incident) async {
    setState(() => _policeLookupLoading.add(incident.id));

    try {
      final lat = incident.location.latitude;
      final lng = incident.location.longitude;
      final query =
          '[out:json][timeout:10];node["amenity"="police"](around:5000,$lat,$lng);out body 5;';
      final url = Uri.parse(
          'https://overpass-api.de/api/interpreter?data=${Uri.encodeComponent(query)}');

      final response = await http.get(url).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200)
        throw Exception('status ${response.statusCode}');

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = (data['elements'] as List?) ?? [];

      if (elements.isEmpty) {
        setState(() => _policeLookupResult[incident.id] =
            'No police station found within 5 km.');
        return;
      }

      String? bestName;
      double bestDistance = double.infinity;
      for (final el in elements) {
        final tags = el['tags'] as Map<String, dynamic>?;
        final name = tags?['name'] as String? ?? 'Police Station';
        final elLat = (el['lat'] as num?)?.toDouble();
        final elLng = (el['lon'] as num?)?.toDouble();
        if (elLat == null || elLng == null) continue;
        final dist = Geolocator.distanceBetween(lat, lng, elLat, elLng);
        if (dist < bestDistance) {
          bestDistance = dist;
          bestName = name;
        }
      }

      if (bestName == null) {
        setState(() => _policeLookupResult[incident.id] =
            'No police station found within 5 km.');
      } else {
        setState(() => _policeLookupResult[incident.id] =
            '$bestName — ${(bestDistance / 1000).toStringAsFixed(1)} km away');
      }
    } catch (e) {
      setState(() => _policeLookupResult[incident.id] =
          'Lookup failed — check your internet connection.');
    } finally {
      if (mounted) setState(() => _policeLookupLoading.remove(incident.id));
    }
  }

  void _markResponded(Incident incident) {
    AppSession.instance.resolveIncident(incident.id);
    AppSession.instance.addNotification(
      title: AppSession.instance.fullName.isEmpty
          ? 'Responder'
          : AppSession.instance.fullName,
      body:
          'Responding to ${incident.personName}\'s safety code near ${incident.destination}.',
      kind: NotificationKind.emergency,
    );
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Marked ${incident.personName} as responded to.')));
  }

  void _logout() {
    AppSession.instance.signOut();
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    if (AppSession.instance.responderStatus != VerificationStatus.verified) {
      return _PendingVerificationView(
          onSimulateApproval: () => setState(() => AppSession
              .instance.responderStatus = VerificationStatus.verified),
          onLogout: _logout);
    }

    final activeIncidents =
        AppSession.instance.activeIncidents.where((i) => !i.responded).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        automaticallyImplyLeading: false,
        title: Text('Responder Dashboard',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        actions: [
          IconButton(
              onPressed: _logout,
              icon: Icon(Icons.logout, color: AppColors.textPrimary),
              tooltip: 'Log out'),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Signed in as ${AppSession.instance.fullName.isEmpty ? 'Responder' : AppSession.instance.fullName}',
                      style: TextStyle(
                          fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                  ),
                  Text('${activeIncidents.length} active',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.danger)),
                ],
              ),
            ),
            Container(
              height: 190,
              margin: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                      initialCenter:
                          _myPosition ?? const LatLng(11.5696, 104.9210),
                      initialZoom: 13.5),
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
                                  color: Colors.blueAccent, size: 28)),
                        for (final incident in activeIncidents)
                          Marker(
                              point: incident.location,
                              child: Icon(Icons.location_on,
                                  color: AppColors.danger, size: 34)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: activeIncidents.isEmpty
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'No active sessions right now. Escalated safety sessions from users on this device will show up here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: activeIncidents.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final incident = activeIncidents[index];
                        final distance = _distanceKm(incident);
                        final policeResult = _policeLookupResult[incident.id];
                        final policeLoading =
                            _policeLookupLoading.contains(incident.id);

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: AppColors.border.withValues(alpha: 0.6)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                      child: Text(incident.personName,
                                          style: const TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w700))),
                                  Text(_elapsedLabel(incident.startedAt),
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: AppColors.textMuted)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('Heading to ${incident.destination}',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.textSecondary)),
                              if (incident.locationIsStale)
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Text(
                                      '⚠ Last known location — live signal was unavailable',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFFE59A2E))),
                                ),
                              if (distance != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                    '${distance.toStringAsFixed(1)} km from you',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textMuted)),
                              ],
                              const SizedBox(height: 8),
                              if (policeResult != null)
                                Text('🚓 $policeResult',
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.navy,
                                        fontWeight: FontWeight.w600))
                              else
                                GestureDetector(
                                  onTap: policeLoading
                                      ? null
                                      : () => _findNearestPolice(incident),
                                  child: Text(
                                    policeLoading
                                        ? 'Finding nearest police station…'
                                        : 'Find nearest police station',
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.navy,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline),
                                  ),
                                ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _callPerson(incident),
                                      icon: const Icon(Icons.call, size: 16),
                                      label: const Text('Call'),
                                      style: OutlinedButton.styleFrom(
                                          minimumSize: const Size(0, 40),
                                          foregroundColor: AppColors.navy),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () => _markResponded(incident),
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.navy,
                                          minimumSize: const Size(0, 40)),
                                      child: const Text('Mark Responded'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
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
