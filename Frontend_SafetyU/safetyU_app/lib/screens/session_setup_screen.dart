import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:geocoding/geocoding.dart';
import '../theme/app_theme.dart';
import '../models/contact.dart';
import '../services/app_session.dart';

class SessionSetupScreen extends StatefulWidget {
  const SessionSetupScreen({super.key});

  @override
  State<SessionSetupScreen> createState() => _SessionSetupScreenState();
}

class _SessionSetupScreenState extends State<SessionSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _destinationController = TextEditingController();
  int _durationMinutes = 30;
  List<Contact> _notifyContacts = [];

  // Live "does this address actually exist" preview, so a typo gets caught
  // before the session starts instead of after.
  Timer? _previewDebounce;
  String? _resolvedAddress;
  bool _isPreviewLoading = false;
  bool _previewFailed = false;

  @override
  void initState() {
    super.initState();
    // Default to notifying every saved trusted contact.
    _notifyContacts = List.of(AppSession.instance.contacts);
    _destinationController.addListener(_onDestinationChanged);
  }

  bool _isLookingUpAddress = false;

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _destinationController.dispose();
    super.dispose();
  }

  void _onDestinationChanged() {
    _previewDebounce?.cancel();
    final text = _destinationController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _resolvedAddress = null;
        _previewFailed = false;
        _isPreviewLoading = false;
      });
      return;
    }
    setState(() => _isPreviewLoading = true);
    _previewDebounce =
        Timer(const Duration(milliseconds: 700), () => _lookupPreview(text));
  }

  Future<void> _lookupPreview(String text) async {
    try {
      final results = await locationFromAddress(text);
      if (!mounted || _destinationController.text.trim() != text) return;
      if (results.isEmpty) {
        setState(() {
          _resolvedAddress = null;
          _previewFailed = true;
          _isPreviewLoading = false;
        });
        return;
      }
      final loc = results.first;
      String formatted = text;
      try {
        final placemarks =
            await placemarkFromCoordinates(loc.latitude, loc.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          formatted = [p.street, p.locality, p.country]
              .where((s) => s != null && s.isNotEmpty)
              .join(', ');
          if (formatted.isEmpty) formatted = text;
        }
      } catch (_) {}

      if (!mounted || _destinationController.text.trim() != text) return;
      setState(() {
        _resolvedAddress = formatted;
        _previewFailed = false;
        _isPreviewLoading = false;
      });
    } catch (e) {
      if (!mounted || _destinationController.text.trim() != text) return;
      setState(() {
        _resolvedAddress = null;
        _previewFailed = true;
        _isPreviewLoading = false;
      });
    }
  }

  /// The real clock time this session will end at, computed live from
  /// whatever duration the person actually picked — not a hardcoded label.
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
    final now = TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_expectedArrival),
      helpText: 'Select the time you expect to arrive',
    );
    if (picked == null) return;

    final nowDate = DateTime.now();
    var target = DateTime(
        nowDate.year, nowDate.month, nowDate.day, picked.hour, picked.minute);
    // If the chosen clock time has already passed today, they mean tomorrow.
    if (!target.isAfter(nowDate)) {
      target = target.add(const Duration(days: 1));
    }

    final minutesUntil = target.difference(nowDate).inMinutes;
    setState(() {
      _durationMinutes = minutesUntil.clamp(5, 720).toInt();
    });

    debugPrint(
        '[SETUP] Arrival time picked -> ${picked.hour}:${picked.minute}, now=$now, durationMinutes=$_durationMinutes');
  }

  Future<void> _pickContacts() async {
    final result = await Navigator.pushNamed(
      context,
      '/select-contacts',
      arguments: _notifyContacts.map((c) => c.id).toList(),
    );
    if (result is List<Contact>) {
      setState(() => _notifyContacts = result);
    }
  }

  Future<void> _startSession() async {
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

    // DEBUG: confirm exactly what the slider/text field hold right now.
    debugPrint(
        '[SETUP] Start Session tapped -> destination="$destination", durationMinutes=$_durationMinutes');

    setState(() => _isLookingUpAddress = true);

    double latitude = 11.5696;
    double longitude = 104.9210;
    bool foundRealLocation = false;

    try {
      final List<Location> results = await locationFromAddress(destination);
      if (results.isNotEmpty) {
        latitude = results.first.latitude;
        longitude = results.first.longitude;
        foundRealLocation = true;
      }
    } catch (e) {
      debugPrint('[SETUP] Geocoding failed: $e');
      foundRealLocation = false;
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
    // DEBUG: this is the exact map object being sent to ActiveSessionScreen.
    debugPrint(
        '[SETUP] Navigating with arguments -> destination="$destination", durationSeconds=$durationSeconds, lat=$latitude, lng=$longitude');

    if (!mounted) return;
    Navigator.pushNamed(
      context,
      '/active-session',
      arguments: {
        'destination': destination,
        'durationSeconds': durationSeconds,
        'expectedTimeStr': _formatClock(_expectedArrival),
        'latitude': latitude,
        'longitude': longitude,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Setup Safety Session'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Destination',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _destinationController,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: 'Enter the real address you\'re heading to',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Destination is required';
                    }
                    return null;
                  },
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                ),
                if (_isPreviewLoading) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text('Checking this address…',
                          style: TextStyle(
                              fontSize: 12.5, color: AppColors.textMuted)),
                    ],
                  ),
                ] else if (_resolvedAddress != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: AppColors.success, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Found: $_resolvedAddress',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.success,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ] else if (_previewFailed) ...[
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: Color(0xFFE59A2E), size: 16),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "Couldn't find this place — double-check the spelling or add more detail (city, country).",
                          style: TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFFE59A2E),
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 28),
                Text(
                  'Estimated Duration: $_durationMinutes minutes',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Slider(
                  value: _durationMinutes.toDouble().clamp(5, 120).toDouble(),
                  min: 5,
                  max: 120,
                  divisions: 23,
                  label: '$_durationMinutes mins',
                  onChanged: (val) {
                    setState(() {
                      _durationMinutes = val.toInt();
                    });
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Or pick the exact time you expect to arrive:',
                  style:
                      TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _pickArrivalTime,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.schedule, color: AppColors.navy, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Arrive by ${_formatClock(_expectedArrival)}',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Icon(Icons.chevron_right, color: AppColors.textMuted),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'The countdown will follow exactly what you set here — $_durationMinutes minutes from now.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Notify These Contacts',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _pickContacts,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.people_outline,
                            color: AppColors.navy, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _notifyContacts.isEmpty
                                ? 'No trusted contacts selected'
                                : _notifyContacts
                                    .map((c) => c.fullName)
                                    .join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary),
                          ),
                        ),
                        Icon(Icons.chevron_right, color: AppColors.textMuted),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLookingUpAddress ? null : _startSession,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
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
                        : const Text(
                            'Start Session',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
