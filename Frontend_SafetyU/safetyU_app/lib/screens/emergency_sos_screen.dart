import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../models/contact.dart';
import '../models/app_notification.dart';
import '../models/incident.dart';
import '../services/app_session.dart';
import '../services/alert_sound.dart';

/// Immediate SOS screen reachable from the Home dashboard's
/// "Emergency Assistant" action — for when someone needs help right now,
/// outside of a scheduled safety session.
class EmergencySosScreen extends StatefulWidget {
  const EmergencySosScreen({super.key});

  @override
  State<EmergencySosScreen> createState() => _EmergencySosScreenState();
}

class _EmergencySosScreenState extends State<EmergencySosScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionSub;
  LatLng? _currentPosition;
  String? _locationStatusMessage;
  bool _sosSent = false;

  @override
  void initState() {
    super.initState();
    _initLocationTracking();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _initLocationTracking() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _setLocationStatus(
          'Turn on location services so we can share your real position.');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _setLocationStatus(
            'Location permission denied — we can\'t share your position.');
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _setLocationStatus(
          'Location permission permanently denied. Enable it in system settings.');
      return;
    }

    try {
      final Position initial = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      setState(() {
        _currentPosition = LatLng(initial.latitude, initial.longitude);
        _locationStatusMessage = null;
      });
      _mapController.move(_currentPosition!, 16.0);
    } catch (_) {
      _setLocationStatus('Could not get your current location.');
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((position) {
      if (!mounted) return;
      setState(() =>
          _currentPosition = LatLng(position.latitude, position.longitude));
    });
  }

  void _setLocationStatus(String message) {
    if (!mounted) return;
    setState(() => _locationStatusMessage = message);
  }

  Future<void> _callContact(Contact contact) async {
    final digits = contact.phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: digits);
    try {
      final launched = await launchUrl(uri);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not open the dialer for ${contact.phone}')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not open the dialer for ${contact.phone}')),
      );
    }
  }

  Future<void> _messageContact(Contact contact) async {
    final pos = _currentPosition;
    final locationLine = pos != null
        ? 'My location: https://maps.google.com/?q=${pos.latitude},${pos.longitude}'
        : 'Still getting my location.';
    final digits = contact.phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(
      scheme: 'sms',
      path: digits,
      queryParameters: {'body': 'I need help right now. $locationLine'},
    );
    try {
      final launched = await launchUrl(uri);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open messages app.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open messages app.')),
      );
    }
  }

  Future<void> _sendSos() async {
    AlertSoundService.playAlert(times: 5);
    final pos = _currentPosition;
    final contacts = AppSession.instance.contacts;

    final locationLine = pos != null
        ? 'https://maps.google.com/?q=${pos.latitude},${pos.longitude}'
        : 'Location unavailable right now — please call me.';

    final recipientsLine = contacts.isEmpty
        ? ''
        : 'Alerting: ${contacts.map((c) => c.fullName).join(', ')}';

    await Share.share(
      'EMERGENCY — I need help right now.\n$locationLine\n$recipientsLine',
      subject:
          'SOS from ${AppSession.instance.fullName.isEmpty ? 'SafetyU' : AppSession.instance.fullName}',
    );

    if (contacts.isEmpty) {
      AppSession.instance.addNotification(
        title: 'SafetyU System',
        body:
            'No trusted contact available — escalated to Emergency Responders.',
        kind: NotificationKind.escalation,
      );
    } else {
      AppSession.instance.addNotification(
        title: contacts.first.fullName,
        body: 'Alerted with your SOS and live location.',
        kind: NotificationKind.trustedContact,
      );
    }

    // A manual SOS is always urgent enough to register as a real case for
    // Emergency Responders, same as an escalated session timeout would.
    if (pos != null) {
      AppSession.instance.addIncident(
        Incident(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          personName: AppSession.instance.fullName.isEmpty
              ? 'SafetyU User'
              : AppSession.instance.fullName,
          phone: AppSession.instance.phone,
          destination: 'Manual SOS — current location',
          location: pos,
          startedAt: DateTime.now(),
        ),
      );
    }

    if (!mounted) return;
    setState(() => _sosSent = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('SOS alert shared with your real-time location.'),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contacts = AppSession.instance.contacts;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text(
          'Emergency Assistant',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_locationStatusMessage != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppColors.dangerLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _locationStatusMessage!,
                    style: TextStyle(
                        color: AppColors.danger,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 200,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter:
                          _currentPosition ?? const LatLng(11.5696, 104.9210),
                      initialZoom: 15.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.safetyu.app',
                      ),
                      if (_currentPosition != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _currentPosition!,
                              child: const Icon(Icons.my_location,
                                  color: Colors.blueAccent, size: 32),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton(
                  onPressed: _sendSos,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6554),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(32)),
                  ),
                  child: Text(
                    _sosSent
                        ? 'SOS Sent — Send Again'
                        : 'Send SOS to Trusted Contacts',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Quick Reach',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 12),
              if (contacts.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'You haven\'t added any trusted contacts yet.',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () =>
                            Navigator.pushNamed(context, '/contacts'),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                        child: Text('Add a contact now',
                            style: TextStyle(
                                color: AppColors.navy,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                )
              else
                ...contacts.map(
                  (c) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppColors.border.withValues(alpha: 0.6)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor:
                              AppColors.navy.withValues(alpha: 0.1),
                          child: Text(c.initials,
                              style: TextStyle(
                                  color: AppColors.navy,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.fullName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5)),
                              Text(c.phone,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _messageContact(c),
                          icon: Icon(Icons.message_outlined,
                              color: AppColors.navy),
                        ),
                        IconButton(
                          onPressed: () => _callContact(c),
                          icon: Icon(Icons.call, color: AppColors.danger),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
