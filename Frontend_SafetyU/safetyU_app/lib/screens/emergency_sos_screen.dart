import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../services/marker_icons.dart';
import '../theme/app_theme.dart';
import '../models/app_notification.dart';
import '../models/incident.dart';
import '../services/alert_sound.dart';
import '../services/app_session.dart';
import '../services/check_in_service.dart';
import '../services/emergency_service.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';

/// Emergency Assistant
///
/// The Emergency PIN is created during account registration.
///
/// Emergency flow:
///
///   Enter PIN
///        ↓
///   Automatic verification after 4th digit
///        ↓
///   Send Emergency Alert
///        ↓
///   Success
///
/// There is only ONE PIN input.
/// There is NO Confirm / Send button.
class EmergencySosScreen extends StatefulWidget {
  const EmergencySosScreen({super.key});

  @override
  State<EmergencySosScreen> createState() =>
      _EmergencySosScreenState();
}

enum _EmergencyStep {
  loading,
  enterPin,
  sending,
  success,
  failure,
}

class _EmergencySosScreenState
    extends State<EmergencySosScreen> {
  final TextEditingController _pinController =
      TextEditingController();

  GoogleMapController? _mapController;

  StreamSubscription<Position>? _positionSub;

  _EmergencyStep _step =
      _EmergencyStep.loading;

  String? _errorMessage;

  String? _locationStatusMessage;

  LatLng? _currentPosition;

  BitmapDescriptor? _meIcon;

  bool _markerIconsRequested = false;

  bool _isVerifyingPin = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Load the team's custom map marker.
    if (!_markerIconsRequested) {
      _markerIconsRequested = true;

      MarkerIcons.me(context).then((icon) {
        if (!mounted) return;

        setState(() {
          _meIcon = icon;
        });
      });
    }
  }

  @override
  void initState() {
    super.initState();

    // The Emergency PIN was already created
    // during normal user registration.
    _step = _EmergencyStep.enterPin;
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  // =========================================================
  // PIN VERIFICATION
  // =========================================================

  Future<void> _verifyEmergencyPin() async {
    if (_isVerifyingPin) return;

    final enteredPin =
        _pinController.text.trim();

    if (enteredPin.length != 4) {
      return;
    }

    setState(() {
      _isVerifyingPin = true;
      _errorMessage = null;
    });

    // Hide keyboard while verification is happening.
    FocusScope.of(context).unfocus();

    try {
      final verified =
          await AuthService.verifyEmergencyPin(
        enteredPin,
      );

      if (!mounted) return;

      if (!verified) {
        setState(() {
          _isVerifyingPin = false;
          _errorMessage =
              'Incorrect Emergency PIN';
        });

        _pinController.clear();
        return;
      }

      // PIN is correct.
      _pinController.clear();

      setState(() {
        _isVerifyingPin = false;
        _errorMessage = null;
      });

      // Correct PIN → send emergency alert.
      await _sendEmergencyAlert();
    } on ApiException catch (e) {
      if (!mounted) return;

      setState(() {
        _isVerifyingPin = false;
        _errorMessage = e.message;
      });

      _pinController.clear();
    } on ApiConnectionException catch (e) {
      if (!mounted) return;

      setState(() {
        _isVerifyingPin = false;
        _errorMessage = e.message;
      });

      _pinController.clear();
    } catch (e) {
      debugPrint(
        'Emergency PIN verification failed: $e',
      );

      if (!mounted) return;

      setState(() {
        _isVerifyingPin = false;
        _errorMessage =
            'Unable to verify your Emergency PIN. Please try again.';
      });

      _pinController.clear();
    }
  }

  // =========================================================
  // GET CURRENT LOCATION
  // =========================================================

  Future<LatLng?> _getCurrentPosition() async {
    try {
      final serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _locationStatusMessage =
                'Location services are turned off.';
          });
        }

        return null;
      }

      LocationPermission permission =
          await Geolocator.checkPermission();

      if (permission ==
          LocationPermission.denied) {
        permission =
            await Geolocator.requestPermission();
      }

      if (permission ==
              LocationPermission.denied ||
          permission ==
              LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _locationStatusMessage =
                'Location permission was not granted.';
          });
        }

        return null;
      }

      final position =
          await Geolocator.getCurrentPosition(
        desiredAccuracy:
            LocationAccuracy.high,
      );

      final location = LatLng(
        position.latitude,
        position.longitude,
      );

      if (!mounted) {
        return location;
      }

      setState(() {
        _currentPosition = location;
        _locationStatusMessage = null;
      });

      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          location,
          16.0,
        ),
      );

      return location;
    } catch (e) {
      debugPrint(
        'Could not get emergency location: $e',
      );

      if (mounted) {
        setState(() {
          _locationStatusMessage =
              'Could not get your current location.';
        });
      }

      return null;
    }
  }

  // =========================================================
  // SEND EMERGENCY ALERT
  // =========================================================

  Future<void> _sendEmergencyAlert() async {
    if (!mounted) return;

    setState(() {
      _step = _EmergencyStep.sending;
      _errorMessage = null;
    });

    try {
      // Play the emergency alert sound.
      AlertSoundService.playAlert(
        times: 5,
      );

      // Get current location.
      final pos =
          await _getCurrentPosition();

      if (!mounted) return;

      _currentPosition = pos;

      // -------------------------------------------------------
      // 1. Create emergency check-in
      // -------------------------------------------------------

      final checkInId =
          await CheckInService.start(
        message:
            'Emergency Assistant — immediate help requested',
        latitude: pos?.latitude,
        longitude: pos?.longitude,
      );

      if (checkInId == null) {
        throw Exception(
          'Could not create emergency check-in.',
        );
      }

      // -------------------------------------------------------
      // 2. Create emergency request
      // -------------------------------------------------------

      final emergencyId =
          await EmergencyService.start(
        checkInId: checkInId,
        message:
            'Emergency Assistant — needs immediate help',
        latitude: pos?.latitude,
        longitude: pos?.longitude,
      );

      if (emergencyId == null) {
        throw Exception(
          'Could not create emergency request.',
        );
      }

      // -------------------------------------------------------
      // 3. Escalate to Emergency Responder
      // -------------------------------------------------------

      await EmergencyService
          .escalateToEmergency(
        emergencyId,
      );

      // -------------------------------------------------------
      // 4. Add local SafetyU notification
      // -------------------------------------------------------

      AppSession.instance.addNotification(
        title: 'Emergency Responder',
        body:
            'Emergency Assistant alert sent for immediate assistance.',
        kind: NotificationKind.escalation,
      );

      // -------------------------------------------------------
      // 5. Add local incident record
      // -------------------------------------------------------

      if (pos != null) {
        AppSession.instance.addIncident(
          Incident(
            id: DateTime.now()
                .microsecondsSinceEpoch
                .toString(),
            personName:
                AppSession.instance.fullName.isEmpty
                    ? 'SafetyU User'
                    : AppSession.instance.fullName,
            phone:
                AppSession.instance.phone,
            destination:
                'Emergency Assistant — current location',
            location: pos,
            startedAt: DateTime.now(),
            notifiedContactIds: const [],
          ),
        );
      }

      if (!mounted) return;

      // Only show success after the backend
      // emergency request and escalation succeed.
      setState(() {
        _step = _EmergencyStep.success;
      });
    } catch (e) {
      debugPrint(
        'Emergency alert failed: $e',
      );

      if (!mounted) return;

      setState(() {
        _step = _EmergencyStep.failure;
        _errorMessage =
            'We could not send the emergency request. '
            'Please try again.';
      });
    }
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          AppColors.background,

      appBar: AppBar(
        backgroundColor:
            AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: AppColors.navy,
          ),
          onPressed: () {
            // Do not allow leaving while
            // PIN verification or emergency sending
            // is in progress.
            if (_step ==
                    _EmergencyStep.sending ||
                _isVerifyingPin) {
              return;
            }

            Navigator.maybePop(context);
          },
        ),
        title: Text(
          'Emergency Assistant',
          style: TextStyle(
            color:
                AppColors.textPrimary,
            fontSize: 18,
            fontWeight:
                FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),

      body: SafeArea(
        child: _buildCurrentStep(),
      ),
    );
  }

  // =========================================================
  // CURRENT STEP
  // =========================================================

  Widget _buildCurrentStep() {
    switch (_step) {
      case _EmergencyStep.loading:
        return _buildLoading();

      case _EmergencyStep.enterPin:
        return _buildEnterPin();

      case _EmergencyStep.sending:
        return _buildSending();

      case _EmergencyStep.success:
        return _buildSuccess();

      case _EmergencyStep.failure:
        return _buildFailure();
    }
  }

  // =========================================================
  // LOADING
  // =========================================================

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  // =========================================================
  // ENTER EMERGENCY PIN
  // =========================================================

  Widget _buildEnterPin() {
    return SingleChildScrollView(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 28,
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),

          // ---------------------------------------------------
          // Security icon
          // ---------------------------------------------------

          Container(
            width: 76,
            height: 76,
            decoration:
                BoxDecoration(
              color:
                  AppColors.danger
                      .withValues(
                alpha: 0.10,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.lock_outline,
              color:
                  AppColors.danger,
              size: 38,
            ),
          ),

          const SizedBox(height: 24),

          // ---------------------------------------------------
          // Title
          // ---------------------------------------------------

          Text(
            'Confirm Emergency Alert',
            textAlign:
                TextAlign.center,
            style: TextStyle(
              color:
                  AppColors.textPrimary,
              fontSize: 24,
              fontWeight:
                  FontWeight.w800,
            ),
          ),

          const SizedBox(height: 12),

          // ---------------------------------------------------
          // Description
          // ---------------------------------------------------

          Text(
            'Enter your Emergency PIN to confirm '
            'that you want to send an emergency alert.',
            textAlign:
                TextAlign.center,
            style: TextStyle(
              color:
                  AppColors.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 36),

          // =================================================
          // SINGLE PIN INPUT
          // =================================================

          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 6,
            ),
            decoration:
                BoxDecoration(
              color: AppColors.card,
              borderRadius:
                  BorderRadius.circular(16),
              border: Border.all(
                color:
                    _errorMessage != null
                        ? AppColors.danger
                        : AppColors.border,
                width:
                    _errorMessage != null
                        ? 1.6
                        : 1,
              ),
            ),
            child: TextField(
              controller:
                  _pinController,
              autofocus: true,
              enabled:
                  !_isVerifyingPin,
              keyboardType:
                  TextInputType.number,
              textInputAction:
                  TextInputAction.done,
              obscureText: true,
              obscuringCharacter: '•',
              maxLength: 4,
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                color:
                    AppColors.textPrimary,
                fontSize: 28,
                fontWeight:
                    FontWeight.w800,
                letterSpacing: 12,
              ),
              decoration:
                  const InputDecoration(
                counterText: '',
                border:
                    InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(
                  vertical: 14,
                ),
              ),
              onChanged: (value) {
                // Remove previous error when
                // the user starts entering a new PIN.
                if (_errorMessage != null) {
                  setState(() {
                    _errorMessage =
                        null;
                  });
                }

                // Automatically verify immediately
                // after the fourth digit.
                if (value.length == 4 &&
                    !_isVerifyingPin) {
                  _verifyEmergencyPin();
                }
              },
            ),
          ),

          // =================================================
          // ERROR MESSAGE
          // =================================================

          if (_errorMessage != null) ...[
            const SizedBox(height: 14),

            Text(
              _errorMessage!,
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                color:
                    AppColors.danger,
                fontSize: 13,
                fontWeight:
                    FontWeight.w600,
              ),
            ),
          ],

          // =================================================
          // VERIFYING MESSAGE
          // =================================================

          if (_isVerifyingPin) ...[
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child:
                      CircularProgressIndicator(
                    strokeWidth: 2,
                    color:
                        AppColors.danger,
                  ),
                ),

                const SizedBox(width: 10),

                Text(
                  'Verifying Emergency PIN...',
                  style: TextStyle(
                    color:
                        AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 30),

          // ---------------------------------------------------
          // Cancel
          // ---------------------------------------------------

          TextButton(
            onPressed:
                _isVerifyingPin
                    ? null
                    : () =>
                        Navigator.maybePop(
                          context,
                        ),
            child: Text(
              'Cancel',
              style: TextStyle(
                color:
                    AppColors.textSecondary,
                fontWeight:
                    FontWeight.w600,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // =================================================
          // LOCATION STATUS
          // =================================================

          if (_locationStatusMessage != null)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.all(12),
              margin:
                  const EdgeInsets.only(
                bottom: 14,
              ),
              decoration:
                  BoxDecoration(
                color:
                    AppColors.dangerLight,
                borderRadius:
                    BorderRadius.circular(
                  12,
                ),
              ),
              child: Text(
                _locationStatusMessage!,
                style: TextStyle(
                  color:
                      AppColors.danger,
                  fontSize: 12.5,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
            ),

          // =================================================
          // GOOGLE MAP
          // =================================================

          ClipRRect(
            borderRadius:
                BorderRadius.circular(16),
            child: SizedBox(
              height: 200,
              child: GoogleMap(
                onMapCreated:
                    (controller) {
                  _mapController =
                      controller;
                },
                initialCameraPosition:
                    CameraPosition(
                  target:
                      _currentPosition ??
                          const LatLng(
                            11.5696,
                            104.9210,
                          ),
                  zoom: 15.0,
                ),
                markers:
                    _currentPosition ==
                            null
                        ? {}
                        : {
                            Marker(
                              markerId:
                                  const MarkerId(
                                'me',
                              ),
                              position:
                                  _currentPosition!,
                              icon:
                                  _meIcon ??
                                      BitmapDescriptor
                                          .defaultMarker,
                            ),
                          },
                myLocationButtonEnabled:
                    false,
                zoomControlsEnabled:
                    false,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ---------------------------------------------------
          // Security message
          // ---------------------------------------------------

          Row(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 15,
                color:
                    AppColors.textMuted,
              ),

              const SizedBox(width: 6),

              Text(
                'Emergency PIN protected',
                style: TextStyle(
                  color:
                      AppColors.textMuted,
                  fontSize: 11.5,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================
  // SENDING
  // =========================================================

  Widget _buildSending() {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 30,
        ),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration:
                  BoxDecoration(
                color:
                    AppColors.danger
                        .withValues(
                  alpha: 0.10,
                ),
                shape:
                    BoxShape.circle,
              ),
              child: const Center(
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child:
                      CircularProgressIndicator(
                    strokeWidth: 3,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 28),

            Text(
              'Sending Emergency Alert',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                color:
                    AppColors.textPrimary,
                fontSize: 22,
                fontWeight:
                    FontWeight.w800,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              'Please wait while SafetyU sends '
              'your emergency request and current '
              'location to the Emergency Responder.',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                color:
                    AppColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // SUCCESS
  // =========================================================

  Widget _buildSuccess() {
    return Center(
      child: SingleChildScrollView(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 28,
        ),
        child: Column(
          children: [
            Container(
              width: 92,
              height: 92,
              decoration:
                  BoxDecoration(
                color:
                    AppColors.success
                        .withValues(
                  alpha: 0.12,
                ),
                shape:
                    BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle,
                color:
                    AppColors.success,
                size: 58,
              ),
            ),

            const SizedBox(height: 26),

            Text(
              'Emergency Request Sent',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                color:
                    AppColors.textPrimary,
                fontSize: 24,
                fontWeight:
                    FontWeight.w800,
              ),
            ),

            const SizedBox(height: 14),

            Text(
              'Your emergency request has been sent '
              'to the SafetyU Emergency Responder.',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                color:
                    AppColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 24),

            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.all(18),
              decoration:
                  BoxDecoration(
                color: AppColors.card,
                borderRadius:
                    BorderRadius.circular(16),
                border: Border.all(
                  color:
                      AppColors.border,
                ),
              ),
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color:
                        AppColors.danger,
                    size: 24,
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Text(
                      _currentPosition !=
                              null
                          ? 'Your current location was included with the emergency request.'
                          : 'The emergency request was sent, but your current location was unavailable.',
                      style: TextStyle(
                        color:
                            AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 54,
              child:
                  ElevatedButton(
                onPressed: () =>
                    Navigator.pop(
                  context,
                ),
                style:
                    ElevatedButton.styleFrom(
                  backgroundColor:
                      AppColors.navy,
                  foregroundColor:
                      Colors.white,
                  elevation: 0,
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                      27,
                    ),
                  ),
                ),
                child: const Text(
                  'Back to Home',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // FAILURE
  // =========================================================

  Widget _buildFailure() {
    return Center(
      child: SingleChildScrollView(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 28,
        ),
        child: Column(
          children: [
            Container(
              width: 92,
              height: 92,
              decoration:
                  BoxDecoration(
                color:
                    AppColors.danger
                        .withValues(
                  alpha: 0.10,
                ),
                shape:
                    BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline,
                color:
                    AppColors.danger,
                size: 56,
              ),
            ),

            const SizedBox(height: 26),

            Text(
              'Emergency Alert Failed',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                color:
                    AppColors.textPrimary,
                fontSize: 24,
                fontWeight:
                    FontWeight.w800,
              ),
            ),

            const SizedBox(height: 14),

            Text(
              _errorMessage ??
                  'We could not send the emergency request.',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                color:
                    AppColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 54,
              child:
                  ElevatedButton(
                onPressed: () {
                  _pinController.clear();

                  setState(() {
                    _errorMessage =
                        null;
                    _locationStatusMessage =
                        null;
                    _isVerifyingPin =
                        false;
                    _step =
                        _EmergencyStep.enterPin;
                  });
                },
                style:
                    ElevatedButton.styleFrom(
                  backgroundColor:
                      AppColors.danger,
                  foregroundColor:
                      Colors.white,
                  elevation: 0,
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                      27,
                    ),
                  ),
                ),
                child: const Text(
                  'Try Again',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            TextButton(
              onPressed: () =>
                  Navigator.pop(
                context,
              ),
              child: Text(
                'Back to Home',
                style: TextStyle(
                  color:
                      AppColors.textSecondary,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}