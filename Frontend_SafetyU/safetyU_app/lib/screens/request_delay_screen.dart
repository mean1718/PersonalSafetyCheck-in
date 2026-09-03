import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import '../theme/app_theme.dart';

class RequestDelayScreen extends StatefulWidget {
  const RequestDelayScreen({super.key});

  @override
  State<RequestDelayScreen> createState() => _RequestDelayScreenState();
}

class _RequestDelayScreenState extends State<RequestDelayScreen> {
  final TextEditingController _hourController =
      TextEditingController(text: '0');
  final TextEditingController _minuteController =
      TextEditingController(text: '25');
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();

  bool _isInitialized = false;
  bool _isConfirming = false;
  int _currentRemainingSeconds = 0;
  String _originalDestination = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      // Pull in whatever the active session already knows: the countdown
      // that's currently running and the destination the user typed on the
      // setup screen. Previously this screen always opened blank/at 0h25m
      // no matter what the real session state was.
      final rawArguments = ModalRoute.of(context)?.settings.arguments;
      if (rawArguments is Map<String, dynamic>) {
        _currentRemainingSeconds =
            rawArguments['remainingSeconds'] as int? ?? 0;
        _originalDestination = rawArguments['destination']?.toString() ?? '';
        _destinationController.text = _originalDestination;
      }
      _isInitialized = true;
    }
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _reasonController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  String _formatRemaining(int seconds) {
    final int minutes = seconds ~/ 60;
    final int secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
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

    // Only re-geocode if the destination text actually changed — no point
    // hitting the network again for the same place.
    double? latitude;
    double? longitude;
    if (newDestination.isNotEmpty && newDestination != _originalDestination) {
      try {
        final List<Location> results =
            await locationFromAddress(newDestination);
        if (results.isNotEmpty) {
          latitude = results.first.latitude;
          longitude = results.first.longitude;
        }
      } catch (_) {
        // Keep the old pin location if lookup fails — still update the
        // text so the person's typed destination isn't lost.
      }
    }

    if (!mounted) return;

    // Return everything the active session needs: the extra time, the
    // (possibly edited) destination text, its real coordinates if we
    // found any, and the optional reason.
    Navigator.pop(context, {
      'extraSeconds': totalExtraSeconds,
      'destination': newDestination,
      'latitude': latitude,
      'longitude': longitude,
      'reason': _reasonController.text.trim(),
    });
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

                    // Shows the countdown the user actually started with,
                    // so this screen doesn't feel disconnected from the
                    // session running behind it.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.border.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Currently remaining',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _formatRemaining(_currentRemainingSeconds),
                            style: TextStyle(
                              fontSize: 16,
                              color: AppColors.navy,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // SECTION 1: I NEED MORE TIME
                    Text(
                      'I NEED MORE TIME',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.border.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _hourController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                Text(
                                  'Hour',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.border.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _minuteController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                Text(
                                  'Minutes',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // SECTION 2: REASON (OPTIONAL)
                    Text(
                      'REASON (OPTIONAL)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _reasonController,
                      decoration: InputDecoration(
                        hintText: 'e.g. Stuck in heavy traffic',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted.withValues(alpha: 0.7),
                        ),
                        filled: true,
                        fillColor: AppColors.card,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppColors.border.withValues(alpha: 0.5),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppColors.border.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // SECTION 3: CONFIRM DESTINATION
                    Text(
                      'CONFIRM DESTINATION',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _destinationController,
                      decoration: InputDecoration(
                        hintText: 'e.g. Central Market',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted.withValues(alpha: 0.7),
                        ),
                        filled: true,
                        fillColor: AppColors.card,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppColors.border.withValues(alpha: 0.5),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppColors.border.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // BOTTOM BUTTONS
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isConfirming ? null : _confirmDelay,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
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
                          : const Text(
                              'Ok Start',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
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
                        backgroundColor: AppColors.background,
                        side: BorderSide(
                          color: AppColors.border.withValues(alpha: 0.8),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: AppColors.textPrimary,
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
