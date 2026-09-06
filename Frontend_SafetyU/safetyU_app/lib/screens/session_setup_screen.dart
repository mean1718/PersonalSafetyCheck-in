import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_theme.dart';
import '../models/contact.dart';
import '../services/app_session.dart';

class SessionSetupScreen extends StatefulWidget {
  const SessionSetupScreen({super.key});

  @override
  State<SessionSetupScreen> createState() => _SessionSetupScreenState();
}

class _SessionSetupScreenState extends State<SessionSetupScreen> {
  static const LatLng _defaultCenter = LatLng(11.5696, 104.9210); // Phnom Penh

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _destinationController = TextEditingController();
  final FocusNode _destinationFocusNode = FocusNode();
  final MapController _mapController = MapController();
  final ScrollController _scrollController = ScrollController();

  int _durationMinutes = 30;
  final TextEditingController _hourController =
      TextEditingController(text: '0');
  final TextEditingController _minuteController =
      TextEditingController(text: '30');
  List<Contact> _notifyContacts = [];
  bool _contactsConfirmed = false;

  // Real place search — hits OpenStreetMap's Nominatim search API directly
  // (the same open database Google-competitor map apps use), instead of the
  // platform's built-in Geocoder, which is much weaker at matching named
  // places like universities or shops rather than street addresses.
  Timer? _searchDebounce;
  List<_PlaceSuggestion> _suggestions = [];
  bool _isSearching = false;
  bool _previewFailed = false;
  bool _suppressNextSearch = false;
  String? _resolvedAddress;
  LatLng? _destinationCoords;

  StreamSubscription<Position>? _positionSub;
  LatLng? _currentPosition;
  String? _locationStatusMessage;
  double _zoom = 14.0;

  static const List<_QuickCategory> _quickCategories = [
    _QuickCategory('Restaurants', Icons.restaurant_outlined, 'restaurants'),
    _QuickCategory('Shopping', Icons.place_outlined, 'shopping mall'),
    _QuickCategory('Coffee', Icons.local_cafe_outlined, 'coffee shop'),
  ];

  @override
  void initState() {
    super.initState();
    _destinationController.addListener(_onDestinationChanged);
    _initLocationTracking();
  }

  bool _isLookingUpAddress = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _positionSub?.cancel();
    _destinationController.dispose();
    _destinationFocusNode.dispose();
    _hourController.dispose();
    _minuteController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // =========================================================
  // NAVIGATION HELPERS
  // =========================================================

  /// Used by every tappable "destination summary" surface (the card
  /// floating over the bottom of the map, and the plain destination card
  /// below it). Scrolls the map/search bar back into view, focuses the
  /// search field, AND re-runs the place search for whatever text is
  /// already there — so tapping it visibly does something (a results
  /// dropdown appears) instead of silently focusing a field you can't see
  /// changed.
  Future<void> _focusDestinationSearch() async {
    if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    if (!mounted) return;
    _destinationFocusNode.requestFocus();
    final text = _destinationController.text.trim();
    if (text.isNotEmpty) {
      _searchPlaces(text);
    }
  }

  // =========================================================
  // DURATION (hour / minute inputs)
  // =========================================================

  void _onDurationFieldChanged() {
    final hours = int.tryParse(_hourController.text.trim()) ?? 0;
    final minutes = int.tryParse(_minuteController.text.trim()) ?? 0;
    final total = (hours * 60 + minutes).clamp(1, 720);
    setState(() => _durationMinutes = total);
  }

  void _syncDurationFields() {
    _hourController.text = (_durationMinutes ~/ 60).toString();
    _minuteController.text = (_durationMinutes % 60).toString();
  }

  /// Once both the person's live position and the chosen destination are
  /// known, prefill a starting Expected Time estimate from the straight-
  /// line distance between them (assuming a brisk walking pace) — so the
  /// person is adjusting a real, distance-based number instead of typing
  /// one in blind. They can still edit it before starting.
  void _maybeEstimateDuration() {
    if (_currentPosition == null || _destinationCoords == null) return;
    final distanceMeters = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _destinationCoords!.latitude,
      _destinationCoords!.longitude,
    );
    final distanceKm = distanceMeters / 1000;
    const walkingKmPerHour = 5.0;
    final estimatedMinutes = ((distanceKm / walkingKmPerHour) * 60).round();
    final rounded = ((estimatedMinutes / 5).round() * 5).clamp(5, 720);
    setState(() => _durationMinutes = rounded);
    _syncDurationFields();
  }

  // =========================================================
  // LIVE LOCATION
  // =========================================================

  Future<void> _initLocationTracking() async {
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _locationStatusMessage =
            'Turn on location services to see your live position.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _locationStatusMessage =
              'Location permission denied. Showing the map without your position.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => _locationStatusMessage =
            'Location permission is permanently denied. Enable it in system settings.');
        return;
      }

      final Position initial = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      final initialLatLng = LatLng(initial.latitude, initial.longitude);
      setState(() {
        _currentPosition = initialLatLng;
        _locationStatusMessage = null;
      });
      AppSession.instance.updateLastKnownPosition(initialLatLng);
      try {
        _mapController.move(initialLatLng, _zoom);
      } catch (_) {}

      _positionSub?.cancel();
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, distanceFilter: 5),
      ).listen(
        (Position position) {
          if (!mounted) return;
          final latLng = LatLng(position.latitude, position.longitude);
          setState(() => _currentPosition = latLng);
          AppSession.instance.updateLastKnownPosition(latLng);
          // Keep following the person's live position — like Google Maps'
          // blue dot — right up until they've picked a destination. Once a
          // destination is set we stop auto-panning so both pins (them +
          // the destination) stay visible instead of the map recentering
          // on them every GPS tick.
          if (_destinationCoords == null) {
            try {
              _mapController.move(latLng, _zoom);
            } catch (_) {}
          }
        },
        onError: (Object error) {
          debugPrint('[SETUP] Location stream error: $error');
        },
      );
    } catch (e) {
      debugPrint('[SETUP] Location init failed: $e');
      if (mounted) {
        setState(() =>
            _locationStatusMessage = 'Could not read your live location.');
      }
    }
  }

  void _recenterOnMe() {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_locationStatusMessage ??
                'Your live location isn\'t available yet.')),
      );
      return;
    }
    setState(() => _zoom = 15.0);
    _mapController.move(_currentPosition!, _zoom);
  }

  void _zoomBy(double delta) {
    final center = _destinationCoords ?? _currentPosition ?? _defaultCenter;
    setState(() => _zoom = (_zoom + delta).clamp(3.0, 18.0));
    _mapController.move(center, _zoom);
  }

  // =========================================================
  // DESTINATION SEARCH (real Nominatim/OpenStreetMap lookup)
  // =========================================================

  void _onDestinationChanged() {
    if (_suppressNextSearch) {
      _suppressNextSearch = false;
      return;
    }
    _searchDebounce?.cancel();
    final text = _destinationController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _suggestions = [];
        _resolvedAddress = null;
        _destinationCoords = null;
        _previewFailed = false;
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    _searchDebounce =
        Timer(const Duration(milliseconds: 500), () => _searchPlaces(text));
  }

  /// Calls Nominatim's public search endpoint directly (OpenStreetMap's
  /// own database of named places, addresses, and POIs) and returns
  /// several real candidate matches to choose from, instead of silently
  /// betting on a single guessed address.
  Future<void> _searchPlaces(String query) async {
    List<_PlaceSuggestion> results = [];
    bool failed = false;
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'jsonv2',
        'addressdetails': '1',
        'limit': '6',
      });
      final response = await http.get(uri, headers: {
        'User-Agent': 'SafeCircleApp/1.0 (student safety project)',
        'Accept-Language': 'en',
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body) as List<dynamic>;
        results = data
            .map((e) => _PlaceSuggestion(
                  displayName: e['display_name'] as String,
                  lat: double.parse(e['lat'] as String),
                  lon: double.parse(e['lon'] as String),
                ))
            .toList();
      } else {
        failed = true;
      }
    } catch (e) {
      debugPrint('[SETUP] Place search failed: $e');
      failed = true;
    }

    if (!mounted || _destinationController.text.trim() != query) return;
    setState(() {
      _suggestions = results;
      _isSearching = false;
      _previewFailed = failed || results.isEmpty;
    });
  }

  /// A single best-match lookup, used as a last-resort fallback in
  /// [_startSession] if the person hits Start before picking a suggestion.
  Future<_PlaceSuggestion?> _fetchFirstMatch(String query) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'jsonv2',
        'limit': '1',
      });
      final response = await http.get(uri, headers: {
        'User-Agent': 'SafeCircleApp/1.0 (student safety project)',
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final List<dynamic> data = json.decode(response.body) as List<dynamic>;
      if (data.isEmpty) return null;
      final e = data.first;
      return _PlaceSuggestion(
        displayName: e['display_name'] as String,
        lat: double.parse(e['lat'] as String),
        lon: double.parse(e['lon'] as String),
      );
    } catch (e) {
      debugPrint('[SETUP] Fallback geocode failed: $e');
      return null;
    }
  }

  /// Locks in one of the real search results: this is what makes the pin
  /// (and the coordinates handed to the active session) point at the exact
  /// place the person tapped, not a guess.
  ///
  /// The text field only ever shows the short place name (e.g. "Cambodia
  /// Academy of Digital Technology"), never the full comma-separated
  /// address — putting the whole address in with the cursor left at the
  /// end made the field auto-scroll to the tail of the string, which is
  /// what made the beginning look "invisible". The full address still
  /// shows underneath as [_resolvedAddress].
  void _selectSuggestion(_PlaceSuggestion s) {
    final shortName = s.displayName.split(',').first.trim();
    _suppressNextSearch = true;
    _destinationController.text = shortName;
    _destinationController.selection = const TextSelection.collapsed(offset: 0);
    setState(() {
      _destinationCoords = LatLng(s.lat, s.lon);
      _resolvedAddress = s.displayName;
      _previewFailed = false;
      _isSearching = false;
      _suggestions = [];
      _zoom = 16.0;
    });
    try {
      _mapController.move(LatLng(s.lat, s.lon), _zoom);
    } catch (_) {}
    _destinationFocusNode.unfocus();
    _maybeEstimateDuration();
  }

  void _pickQuickCategory(_QuickCategory category) {
    final query = '${category.searchTerm}, Phnom Penh';
    _destinationController.text = query;
    _destinationController.selection =
        TextSelection.collapsed(offset: query.length);
    _destinationFocusNode.requestFocus();
  }

  bool get _canStartSession => _contactsConfirmed && !_isLookingUpAddress;

  DateTime get _expectedArrival =>
      DateTime.now().add(Duration(minutes: _durationMinutes));

  String _formatClock(DateTime time) {
    final hour24 = time.hour;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $period';
  }

  Future<void> _pickArrivalTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_expectedArrival),
      helpText: 'Select the time you expect to arrive',
    );
    if (picked == null) return;

    final nowDate = DateTime.now();
    var target = DateTime(
        nowDate.year, nowDate.month, nowDate.day, picked.hour, picked.minute);
    if (!target.isAfter(nowDate)) {
      target = target.add(const Duration(days: 1));
    }

    final minutesUntil = target.difference(nowDate).inMinutes;
    setState(() {
      _durationMinutes = minutesUntil.clamp(5, 720).toInt();
    });
    _syncDurationFields();
  }

  /// Notify Contacts is required, and you can't get through it with zero
  /// people: if there isn't a single confirmed friend yet, this sends the
  /// person to the Friends screen to add one first, instead of opening a
  /// picker with nothing in it.
  Future<void> _pickContacts() async {
    if (AppSession.instance.friends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Add a trusted friend first — you need at least one to start a safety session.')),
      );
      await Navigator.pushNamed(context, '/contacts');
      if (!mounted) return;
      if (AppSession.instance.friends.isEmpty) {
        // Still nobody confirmed — nothing more we can do here yet.
        return;
      }
    }

    final result = await Navigator.pushNamed(
      context,
      '/select-contacts',
      arguments: _notifyContacts.map((c) => c.id).toList(),
    );
    if (result is List<Contact> && result.isNotEmpty) {
      setState(() {
        _notifyContacts = result;
        _contactsConfirmed = true;
      });
    }
  }

  Future<void> _startSession() async {
    if (!_contactsConfirmed || _notifyContacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Select at least one trusted friend to notify before starting your session.')),
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please enter a destination before starting your session.')),
      );
      return;
    }
    if (_isLookingUpAddress) return;

    final String destination = _destinationController.text.trim();
    setState(() => _isLookingUpAddress = true);

    double latitude = _defaultCenter.latitude;
    double longitude = _defaultCenter.longitude;
    bool foundRealLocation = false;

    if (_destinationCoords != null &&
        _resolvedAddress != null &&
        !_previewFailed) {
      latitude = _destinationCoords!.latitude;
      longitude = _destinationCoords!.longitude;
      foundRealLocation = true;
    } else {
      final match = await _fetchFirstMatch(destination);
      if (match != null) {
        latitude = match.lat;
        longitude = match.lon;
        foundRealLocation = true;
      }
    }

    if (!mounted) return;
    setState(() => _isLookingUpAddress = false);

    if (!foundRealLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Couldn\'t find "$destination" on the map — starting with an approximate location.',
          ),
        ),
      );
    }

    final int durationSeconds = _durationMinutes * 60;

    Navigator.pushNamed(
      context,
      '/active-session',
      arguments: {
        'destination': destination,
        'durationSeconds': durationSeconds,
        'expectedTimeStr': _formatClock(_expectedArrival),
        'latitude': latitude,
        'longitude': longitude,
        'notifyContactIds': _notifyContacts.map((c) => c.id).toList(),
      },
    );
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    const navyColor = Color(0xFF0D1B3E);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFFFF8A71)),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'New Safety Session',
          style: TextStyle(
            color: navyColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMapSection(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20.0, vertical: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isSearching) ...[
                        const Row(
                          children: [
                            SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 8),
                            Text('Searching…',
                                style: TextStyle(
                                    fontSize: 12.5, color: Colors.grey)),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ] else if (_previewFailed) ...[
                        const Row(
                          children: [
                            Icon(Icons.error_outline,
                                color: Color(0xFFE59A2E), size: 16),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                "Couldn't find this place — double-check spelling or add detail (e.g. city).",
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFE59A2E),
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      const Text(
                        'Destination',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: navyColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildDestinationInputCard(),
                      const SizedBox(height: 16),
                      const Text(
                        'Expected Time',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: navyColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTimeInputBox(
                              controller: _hourController,
                              unit: 'Hour',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTimeInputBox(
                              controller: _minuteController,
                              unit: 'Minutes',
                            ),
                          ),
                        ],
                      ),
                      if (_destinationCoords != null &&
                          _currentPosition != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Estimated from your current distance to the destination — adjust freely.',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Text(
                        'Arrival Time',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: navyColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _pickArrivalTime,
                        child: Container(
                          width: MediaQuery.of(context).size.width * 0.45,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.access_time,
                                  color: Colors.grey, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                _formatClock(_expectedArrival),
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: navyColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Notify Contacts',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: navyColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _pickContacts,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8EEF9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _contactsConfirmed
                                  ? Colors.transparent
                                  : AppColors.danger,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _contactsConfirmed
                                    ? Icons.people_outline
                                    : Icons.warning_amber_rounded,
                                color: _contactsConfirmed
                                    ? navyColor
                                    : AppColors.danger,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  !_contactsConfirmed
                                      ? 'Select Contacts'
                                      : _notifyContacts
                                          .map((c) => c.fullName)
                                          .join(', '),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: _contactsConfirmed
                                        ? navyColor
                                        : AppColors.danger,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!_contactsConfirmed) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Required — you need at least one confirmed friend selected to start a session.',
                          style: TextStyle(
                              fontSize: 11.5, color: AppColors.danger),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _canStartSession ? _startSession : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: navyColor,
                            disabledBackgroundColor:
                                navyColor.withValues(alpha: 0.35),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                            elevation: 0,
                          ),
                          child: _isLookingUpAddress
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.verified_user_outlined,
                                        color: Colors.white, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Start Safety Session',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapSection() {
    return SizedBox(
      height: 310,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter:
                  _currentPosition ?? _destinationCoords ?? _defaultCenter,
              initialZoom: _zoom,
            ),
            children: [
              // CartoDB's Voyager basemap — free, no API key, and much
              // closer to a Google-Maps look (labeled roads, shaded land
              // use, points of interest) than the plain OSM default tiles.
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.safetyu.app',
                maxZoom: 19,
              ),
              if (_currentPosition != null && _destinationCoords != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [_currentPosition!, _destinationCoords!],
                      strokeWidth: 3,
                      color: const Color(0xFF0D1B3E).withValues(alpha: 0.4),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_destinationCoords != null)
                    Marker(
                      point: _destinationCoords!,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.location_on,
                          color: Colors.redAccent, size: 36),
                    ),
                  if (_currentPosition != null)
                    Marker(
                      point: _currentPosition!,
                      width: 20,
                      height: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 10,
            left: 14,
            right: 14,
            child: Column(
              children: [
                Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(21),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Colors.grey, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _destinationController,
                          focusNode: _destinationFocusNode,
                          textInputAction: TextInputAction.search,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'Search location (e.g. CADT)',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Destination is required';
                            }
                            return null;
                          },
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                        ),
                      ),
                      if (_destinationController.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _destinationController.clear();
                            setState(() {
                              _suggestions = [];
                              _destinationCoords = null;
                              _resolvedAddress = null;
                              _previewFailed = false;
                            });
                            _destinationFocusNode.requestFocus();
                          },
                          child: const Icon(Icons.close,
                              color: Colors.grey, size: 16),
                        ),
                    ],
                  ),
                ),
                if (_suggestions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 210),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _suggestions.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 14, endIndent: 14),
                      itemBuilder: (context, i) {
                        final s = _suggestions[i];
                        final parts = s.displayName.split(',');
                        final primary = parts.first.trim();
                        final rest = parts.skip(1).join(',').trim();
                        return InkWell(
                          onTap: () => _selectSuggestion(s),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                const Icon(Icons.place_outlined,
                                    size: 18, color: Color(0xFF0D1B3E)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(primary,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF0D1B3E))),
                                      if (rest.isNotEmpty)
                                        Text(rest,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _quickCategories.map((cat) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 6.0),
                                child: GestureDetector(
                                  onTap: () => _pickQuickCategory(cat),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.05),
                                          blurRadius: 4,
                                        )
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(cat.icon,
                                            size: 14,
                                            color: const Color(0xFF0D1B3E)),
                                        const SizedBox(width: 4),
                                        Text(
                                          cat.label,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF0D1B3E),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      PopupMenuButton<String>(
                        tooltip: 'More options',
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        onSelected: (value) {
                          if (value == 'refresh') {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Refreshing your location…')),
                            );
                            _initLocationTracking();
                          } else if (value == 'clear') {
                            _destinationController.clear();
                            setState(() {
                              _suggestions = [];
                              _destinationCoords = null;
                              _resolvedAddress = null;
                              _previewFailed = false;
                            });
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'refresh',
                            child: Row(
                              children: [
                                Icon(Icons.my_location, size: 18),
                                SizedBox(width: 10),
                                Text('Refresh my location'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'clear',
                            child: Row(
                              children: [
                                Icon(Icons.clear, size: 18),
                                SizedBox(width: 10),
                                Text('Clear destination'),
                              ],
                            ),
                          ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.more_horiz,
                              size: 16, color: Color(0xFF0D1B3E)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            right: 12,
            top: 80,
            child: Column(
              children: [
                _buildCircularIconButton(Icons.my_location, _recenterOnMe),
                const SizedBox(height: 6),
                _buildCircularIconButton(Icons.add, () => _zoomBy(1)),
                const SizedBox(height: 6),
                _buildCircularIconButton(Icons.remove, () => _zoomBy(-1)),
              ],
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 12,
            child: GestureDetector(
              onTap: _focusDestinationSearch,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.place_outlined,
                          color: Color(0xFF0D1B3E), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _destinationController.text.isEmpty
                                ? 'Select Destination'
                                : _destinationController.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF0D1B3E),
                            ),
                          ),
                          if (_resolvedAddress != null)
                            Text(
                              _resolvedAddress!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Color(0xFF0D1B3E)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDestinationInputCard() {
    return GestureDetector(
      onTap: _focusDestinationSearch,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            const Icon(Icons.place_outlined, color: Colors.grey, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _destinationController.text.isEmpty
                    ? 'Enter destination'
                    : _destinationController.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0D1B3E),
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeInputBox({
    required TextEditingController controller,
    required String unit,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0D1B3E),
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (_) => _onDurationFieldChanged(),
            ),
          ),
          Text(
            unit,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0D1B3E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircularIconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
            ),
          ],
        ),
        child: Icon(icon, size: 16, color: const Color(0xFF0D1B3E)),
      ),
    );
  }
}

class _PlaceSuggestion {
  final String displayName;
  final double lat;
  final double lon;
  const _PlaceSuggestion(
      {required this.displayName, required this.lat, required this.lon});
}

class _QuickCategory {
  final String label;
  final IconData icon;
  final String searchTerm;
  const _QuickCategory(this.label, this.icon, this.searchTerm);
}
