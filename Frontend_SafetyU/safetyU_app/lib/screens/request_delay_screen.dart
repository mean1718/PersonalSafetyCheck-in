import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import '../theme/app_theme.dart';
import '../widgets/safety_illustration.dart';

/// "Request Delay" — same layout as before (remaining time, hours/minutes,
/// reason, destination, Ok Start / Cancel), now with colour: a gradient
/// countdown card, colour-coded sections and a gradient main button.
///
/// Returns (via Navigator.pop) the same map the session screen expects:
/// extraSeconds, destination, latitude, longitude, reason.
class RequestDelayScreen extends StatefulWidget {
  const RequestDelayScreen({super.key});

  @override
  State<RequestDelayScreen> createState() => _RequestDelayScreenState();
}

class _RequestDelayScreenState extends State<RequestDelayScreen> {
  static const Color _blue = Color(0xFF2F80ED);
  static const Color _indigo = Color(0xFF5B5BD6);
  static const Color _orange = Color(0xFFF59E0B);
  static const Color _green = Color(0xFF27AE60);

  final TextEditingController _hourController =
      TextEditingController(text: '0');
  final TextEditingController _minuteController =
      TextEditingController(text: '25');
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();

  bool _isInitialized = false;
  bool _isConfirming = false;
  String _originalDestination = '';

  // The running countdown, kept ticking off a real end time so the number
  // on this screen doesn't freeze at the moment it was opened.
  DateTime _endsAt = DateTime.now();
  Timer? _ticker;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      final rawArguments = ModalRoute.of(context)?.settings.arguments;
      if (rawArguments is Map<String, dynamic>) {
        final remaining = rawArguments['remainingSeconds'] as int? ?? 0;
        _endsAt = DateTime.now().add(Duration(seconds: remaining));
        _originalDestination = rawArguments['destination']?.toString() ?? '';
        _destinationController.text = _originalDestination;
      }
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      _isInitialized = true;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _hourController.dispose();
    _minuteController.dispose();
    _reasonController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  int get _remainingSeconds {
    final ms = _endsAt.difference(DateTime.now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  String _formatRemaining(int seconds) {
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    final int secs = seconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = secs.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  Future<void> _confirmDelay() async {
    if (_isConfirming) return;

    final int extraHours = int.tryParse(_hourController.text) ?? 0;
    final int extraMinutes = int.tryParse(_minuteController.text) ?? 0;
    final int totalExtraSeconds = (extraHours * 3600) + (extraMinutes * 60);

    if (totalExtraSeconds <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Enter how much extra time you need (at least 1 minute).')),
      );
      return;
    }

    final String newDestination = _destinationController.text.trim();
    if (newDestination.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Destination is required.')),
      );
      return;
    }

    setState(() => _isConfirming = true);

    // Only re-geocode if the destination text actually changed.
    double? latitude;
    double? longitude;
    if (newDestination != _originalDestination) {
      try {
        final List<Location> results =
            await locationFromAddress(newDestination);
        if (results.isNotEmpty) {
          latitude = results.first.latitude;
          longitude = results.first.longitude;
        }
      } catch (_) {
        // Keep the old pin location if lookup fails.
      }
    }

    if (!mounted) return;

    Navigator.pop(context, {
      'extraSeconds': totalExtraSeconds,
      'destination': newDestination,
      'latitude': latitude,
      'longitude': longitude,
      'reason': _reasonController.text.trim(),
    });
  }

  // ---- colourful building blocks ----

  Widget _sectionTitle(IconData icon, Color color, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }

  Widget _remainingCard() {
    final left = _remainingSeconds;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_blue, _indigo],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _blue.withValues(alpha: 0.30),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.timer_outlined, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Currently remaining',
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            _formatRemaining(left),
            style: const TextStyle(
              fontSize: 24,
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // One box (hours or minutes). Uses a bare TextField so it doesn't draw
  // the theme's own box inside this box (the "box in a box" look).
  Widget _timeBox(TextEditingController controller, String unit, Color color) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.4),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          Text(
            unit,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint, IconData icon, Color color) {
    OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        fontSize: 13,
        color: AppColors.textMuted.withValues(alpha: 0.9),
      ),
      prefixIcon: Icon(icon, size: 20, color: color),
      filled: true,
      fillColor: color.withValues(alpha: 0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: border(color.withValues(alpha: 0.45), 1.2),
      enabledBorder: border(color.withValues(alpha: 0.45), 1.2),
      focusedBorder: border(color, 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Request Delay',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    _remainingCard(),
                    const SizedBox(height: 24),

                    // SECTION 1: I NEED MORE TIME
                    _sectionTitle(Icons.more_time, _blue, 'I NEED MORE TIME'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                            child: _timeBox(_hourController, 'Hour', _blue)),
                        const SizedBox(width: 14),
                        Expanded(
                            child: _timeBox(
                                _minuteController, 'Minutes', _indigo)),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // SECTION 2: REASON (OPTIONAL)
                    _sectionTitle(Icons.chat_bubble_outline, _orange,
                        'REASON (OPTIONAL)'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _reasonController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _fieldDecoration(
                          'e.g. Stuck in heavy traffic',
                          Icons.edit_outlined,
                          _orange),
                    ),
                    const SizedBox(height: 24),

                    // SECTION 3: CONFIRM DESTINATION
                    _sectionTitle(
                        Icons.place_outlined, _green, 'CONFIRM DESTINATION'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _destinationController,
                      textCapitalization: TextCapitalization.words,
                      decoration: _fieldDecoration(
                          'e.g. Central Market', Icons.place, _green),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // BOTTOM BUTTONS
            SkylineBottomBar(
              height: 190,
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_blue, _indigo],
                        ),
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(
                            color: _blue.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _isConfirming ? null : _confirmDelay,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          disabledBackgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                        child: _isConfirming
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_circle_outline,
                                      color: Colors.white, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Ok Start',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: AppColors.card,
                        side: BorderSide(
                          color: AppColors.danger.withValues(alpha: 0.7),
                          width: 1.4,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
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
