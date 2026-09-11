import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../services/live_location_service.dart';
import '../services/directions_service.dart';

/// "Where are my trusted contacts right now" — a live map with every
/// contact who currently has location sharing turned on, distance from
/// the signed-in person, and a real road route drawn to whichever one is
/// selected.
class LiveLocationMapScreen extends StatefulWidget {
  /// If set (the TrustedContact._id, same id used across the app's
  /// Contact model), opens straight into routing to this contact instead
  /// of showing the picker list first.
  final String? focusContactId;

  const LiveLocationMapScreen({super.key, this.focusContactId});

  @override
  State<LiveLocationMapScreen> createState() => _LiveLocationMapScreenState();
}

class _LiveLocationMapScreenState extends State<LiveLocationMapScreen> {
  final MapController _mapController = MapController();
  Timer? _refreshTimer;

  List<ContactLocation> _contacts = [];
  LatLng? _myPosition;
  ContactLocation? _selected;
  RouteResult? _route;
  bool _loading = true;
  bool _routing = false;
  String? _error;
  bool _sharingMine = LiveLocationService.instance.isSharing;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final position = await LiveLocationService.instance.currentPosition();
      final contacts =
          await LiveLocationService.instance.fetchContactLocations();
      if (!mounted) return;
      setState(() {
        _myPosition = LatLng(position.latitude, position.longitude);
        _contacts = contacts;
        _loading = false;
        _error = null;
      });

      if (widget.focusContactId != null && _selected == null) {
        final match =
            contacts.where((c) => c.contactId == widget.focusContactId);
        if (match.isNotEmpty) {
          _selectContact(match.first);
        } else if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "This friend isn't sharing their location right now.",
              ),
            ),
          );
        }
      } else if (_selected != null) {
        // Refresh the route if the selected contact moved meaningfully.
        final updated =
            contacts.where((c) => c.contactId == _selected!.contactId);
        if (updated.isNotEmpty) {
          _selected = updated.first;
          _fetchRoute();
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = 'Could not load live locations. $e';
      });
    }
  }

  Future<void> _selectContact(ContactLocation contact) async {
    setState(() => _selected = contact);
    await _fetchRoute();
  }

  Future<void> _fetchRoute() async {
    if (_myPosition == null || _selected == null) return;
    setState(() => _routing = true);
    try {
      final route = await DirectionsService.route(
        from: _myPosition!,
        to: LatLng(_selected!.latitude, _selected!.longitude),
      );
      if (!mounted) return;
      setState(() {
        _route = route;
        _routing = false;
      });
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: route.points,
          padding: const EdgeInsets.fromLTRB(40, 120, 40, 220),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _routing = false;
        _route = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not draw a route: $e')),
      );
    }
  }

  Future<void> _openInMapsApp() async {
    final c = _selected;
    if (c == null) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${c.latitude},${c.longitude}&travelmode=walking',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _toggleMySharing() async {
    if (_sharingMine) {
      await LiveLocationService.instance.stopSharing();
      setState(() => _sharingMine = false);
    } else {
      final ok = await LiveLocationService.instance.startSharing();
      setState(() => _sharingMine = ok);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location permission is needed to share your position with trusted contacts.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Locations'),
        actions: [
          IconButton(
            tooltip:
                _sharingMine ? 'Stop sharing my location' : 'Share my location',
            icon: Icon(
                _sharingMine ? Icons.my_location : Icons.location_disabled),
            onPressed: _toggleMySharing,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                ))
              : Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _myPosition ?? const LatLng(0, 0),
                        initialZoom: 14,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.safetyu.app',
                        ),
                        if (_route != null)
                          PolylineLayer(polylines: [
                            Polyline(
                              points: _route!.points,
                              strokeWidth: 5,
                              color: AppColors.navy,
                            ),
                          ]),
                        MarkerLayer(markers: [
                          if (_myPosition != null)
                            Marker(
                              point: _myPosition!,
                              width: 40,
                              height: 40,
                              child: const _MeMarker(),
                            ),
                          for (final c in _contacts)
                            Marker(
                              point: LatLng(c.latitude, c.longitude),
                              width: 44,
                              height: 44,
                              child: GestureDetector(
                                onTap: () => _selectContact(c),
                                child: _ContactMarker(
                                  initial: c.name.isNotEmpty ? c.name[0] : '?',
                                  selected: _selected?.contactId == c.contactId,
                                ),
                              ),
                            ),
                        ]),
                      ],
                    ),
                    if (_contacts.isEmpty) const _EmptyStateCard(),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _BottomPanel(
                        contacts: _contacts,
                        selected: _selected,
                        route: _route,
                        routing: _routing,
                        onSelect: _selectContact,
                        onOpenMaps: _openInMapsApp,
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _MeMarker extends StatelessWidget {
  const _MeMarker();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      child: const Icon(Icons.person, color: Colors.white, size: 20),
    );
  }
}

class _ContactMarker extends StatelessWidget {
  final String initial;
  final bool selected;
  const _ContactMarker({required this.initial, required this.selected});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: selected ? AppColors.navy : Colors.deepOrange,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      alignment: Alignment.center,
      child: Text(
        initial.toUpperCase(),
        style:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard();
  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'None of your trusted contacts are sharing their location right now. '
            'Ask them to turn on "Share my location" from their SafetyU app.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  final List<ContactLocation> contacts;
  final ContactLocation? selected;
  final RouteResult? route;
  final bool routing;
  final ValueChanged<ContactLocation> onSelect;
  final VoidCallback onOpenMaps;

  const _BottomPanel({
    required this.contacts,
    required this.selected,
    required this.route,
    required this.routing,
    required this.onSelect,
    required this.onOpenMaps,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (selected != null) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(selected!.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(selected!.freshnessLabel,
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 12)),
                    ],
                  ),
                ),
                if (routing)
                  const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else if (route != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(route!.distanceLabel,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(route!.durationLabel,
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 12)),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onOpenMaps,
                icon: const Icon(Icons.directions),
                label: const Text('Start navigation'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
          ],
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: contacts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final c = contacts[i];
                final isSelected = selected?.contactId == c.contactId;
                return GestureDetector(
                  onTap: () => onSelect(c),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.navy.withOpacity(0.1)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? AppColors.navy : Colors.transparent,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        Text(c.distanceLabel,
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 12)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
