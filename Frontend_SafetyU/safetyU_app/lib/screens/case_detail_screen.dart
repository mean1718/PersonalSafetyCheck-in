import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/marker_icons.dart';
import '../theme/app_theme.dart';
import '../models/incident.dart';
import '../services/app_session.dart';
import '../services/emergency_responder_service.dart';
import '../widgets/case_status_widgets.dart';
import '../services/notification_service.dart';

class CaseDetailScreen extends StatefulWidget {
  const CaseDetailScreen({super.key});

  @override
  State<CaseDetailScreen> createState() => _CaseDetailScreenState();
}

class _CaseDetailScreenState extends State<CaseDetailScreen> {
  BitmapDescriptor? _incidentIcon;
  bool _markerIconRequested = false;

  Future<Incident?>? _caseFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Load the team's custom incident marker.
    if (!_markerIconRequested) {
      _markerIconRequested = true;

      MarkerIcons.destination(context).then((icon) {
        if (!mounted) return;
        setState(() => _incidentIcon = icon);
      });
    }

    // Load the case from the backend.
    _caseFuture ??= _loadIncident(context);
  }

  // =========================================================
  // LOAD CASE FROM BACKEND
  // =========================================================

  Future<Incident?> _loadIncident(BuildContext context) async {
    final args = ModalRoute.of(context)?.settings.arguments;

    String? caseId;

    if (args is String) {
      caseId = args;
    } else if (args is Incident) {
      caseId = args.id;
    }

    if (caseId == null || caseId.isEmpty) {
      return null;
    }

    try {
      final cases = await EmergencyResponderService.fetchCases();

      for (final incident in cases) {
        if (incident.id == caseId) {
          return incident;
        }
      }

      return null;
    } catch (e) {
      debugPrint('[CASE DETAIL] Failed to load case: $e');
      rethrow;
    }
  }

  // =========================================================
  // CALL PERSON
  // =========================================================

  Future<void> _callPerson(Incident incident) async {
    final digits = incident.phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(
      scheme: 'tel',
      path: digits,
    );

    try {
      final launched = await launchUrl(uri);

      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open the dialer for ${incident.phone}',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open the dialer for ${incident.phone}',
          ),
        ),
      );
    }
  }
 Future<void> _markEmergencyNotificationRead(
  String emergencyId,
) async {
  try {
    final notifications =
        await NotificationService.fetchAll();

    for (final notification
        in notifications) {
      if (notification['type']?.toString() !=
          'emergency_alert') {
        continue;
      }

      final emergencyValue =
          notification['emergency'];

      final notificationEmergencyId =
          emergencyValue
                  is Map<String, dynamic>
              ? emergencyValue['_id']
                    ?.toString()
              : emergencyValue?.toString();

      if (notificationEmergencyId !=
          emergencyId) {
        continue;
      }

      final notificationId =
          notification['_id']?.toString();

      if (notificationId != null) {
        try {
          await NotificationService.markRead(
            notificationId,
          );
        } catch (e) {
          debugPrint(
            'Failed to mark notification $notificationId read: $e',
          );
        }
      }
    }
  } catch (e) {
    debugPrint(
      'Failed to mark emergency notifications as read: $e',
    );
  }
}

  // =========================================================
  // TAKE CASE
  // =========================================================

  Future<void> _takeCase(Incident incident) async {
  try {
    await EmergencyResponderService.acceptCase(
      incident.id,
    );

    // Mark the original responder notification as read.
    // The Home red notification dot can disappear after
    // the responder actually takes the case.
    await _markEmergencyNotificationRead(incident.id);

    // Update local state immediately.
    AppSession.instance.setIncidentStatus(
      incident.id,
      IncidentStatus.inProgress,
    );

    if (!mounted) return;

    // Reload the authoritative case from backend.
    setState(() {
      _caseFuture = _loadIncident(context);
    });
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Failed to accept emergency: $e',
        ),
      ),
    );
  }
}

  // =========================================================
  // CANCEL CASE
  // =========================================================

  void _cancelCase(Incident incident) {
    // Keep the existing local behavior.
    // There is currently no backend "cancel case" endpoint.
    AppSession.instance.setIncidentStatus(
      incident.id,
      IncidentStatus.newCase,
    );

    setState(() {
      _caseFuture = _loadIncident(context);
    });
  }

  // =========================================================
  // VIEW ON MAP
  // =========================================================

  void _viewOnMap(
    BuildContext context,
    Incident incident,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: 320,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(20),
          ),
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: incident.location,
              zoom: 15,
            ),
            markers: {
              Marker(
                markerId: const MarkerId('incident'),
                position: incident.location,
                icon: _incidentIcon ??
                    BitmapDescriptor.defaultMarker,
              ),
            },
          ),
        ),
      ),
    );
  }

  // =========================================================
  // LOADING SCREEN
  // =========================================================

  Widget _buildLoading() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navyDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Case Details',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  // =========================================================
  // ERROR SCREEN
  // =========================================================

  Widget _buildError() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navyDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Case Details',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: AppColors.danger,
              ),
              const SizedBox(height: 12),
              Text(
                'Could not load this emergency case.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please go back to Cases and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _caseFuture = _loadIncident(context);
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                ),
                child: const Text(
                  'Try Again',
                  style: TextStyle(
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================
  // CASE NOT FOUND
  // =========================================================

  Widget _buildNotFound() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navyDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Case Details',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'This case is no longer available.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================
  // MAIN CASE DETAILS UI
  // =========================================================

  Widget _buildCaseDetails(
    BuildContext context,
    Incident incident,
  ) {
    final inProgress =
        incident.status == IncidentStatus.inProgress;

    final resolved =
        incident.status == IncidentStatus.resolved;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navyDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Case Details',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // =====================================================
              // PERSON HEADER
              // =====================================================

              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor:
                        AppColors.navy.withValues(alpha: 0.1),
                    child: Icon(
                      Icons.person,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          incident.personName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          incident.phone.isEmpty
                              ? 'No phone on file'
                              : incident.phone,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  CaseStatusBadge(
                    status: incident.status,
                    filled: true,
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // =====================================================
              // EMERGENCY TIME
              // =====================================================

              _DetailRow(
                icon: Icons.access_time,
                label: 'Emergency Time',
                value: formatClockTime(
                  incident.startedAt,
                ),
              ),

              const SizedBox(height: 12),

              // =====================================================
              // LOCATION
              // =====================================================

              _DetailRow(
                icon: Icons.place_outlined,
                label: 'Location',
                value: incident.destination,
              ),

              if (incident.locationIsStale) ...[
                const SizedBox(height: 6),
                const Text(
                  '⚠ Last known location — live signal was unavailable',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFFE59A2E),
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // =====================================================
              // IN PROGRESS
              // =====================================================

              if (inProgress) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 180,
                    child: GoogleMap(
                      initialCameraPosition:
                          CameraPosition(
                        target: incident.location,
                        zoom: 15.0,
                      ),
                      markers: {
                        Marker(
                          markerId:
                              const MarkerId('incident'),
                          position:
                              incident.location,
                          icon: _incidentIcon ??
                              BitmapDescriptor
                                  .defaultMarker,
                        ),
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ===================================================
                // CANCEL + CALL
                // ===================================================

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            _cancelCase(incident),
                        style: OutlinedButton.styleFrom(
                          minimumSize:
                              const Size(0, 46),
                        ),
                        child: const Text(
                          'Cancel',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _callPerson(incident),
                        icon: const Icon(
                          Icons.call,
                          size: 16,
                        ),
                        label: const Text(
                          'Call',
                        ),
                        style:
                            OutlinedButton.styleFrom(
                          minimumSize:
                              const Size(0, 46),
                          foregroundColor:
                              AppColors.navy,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ===================================================
                // UPDATE STATUS
                // ===================================================

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () async {
                      final result =
                          await Navigator.pushNamed(
                        context,
                        '/update-case',
                        arguments: incident.id,
                      );

                      if (result == true && mounted) {
                        setState(() {
                          _caseFuture =
                              _loadIncident(context);
                        });
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          AppColors.primaryButton,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(26),
                      ),
                    ),
                    child: const Text(
                      'Update Status',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ]

              // =====================================================
              // RESOLVED
              // =====================================================

              else if (resolved) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(
                      alpha: 0.1,
                    ),
                    borderRadius:
                        BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          incident.resolvedAt != null
                              ? 'Resolved at ${formatClockTime(incident.resolvedAt!)}'
                              : 'This case has been resolved.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.success,
                            fontWeight:
                                FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ]

              // =====================================================
              // NEW / WAITING
              // =====================================================

              else ...[
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _viewOnMap(
                      context,
                      incident,
                    ),
                    icon: const Icon(
                      Icons.map_outlined,
                      size: 18,
                    ),
                    label: const Text(
                      'View on Map',
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () =>
                        _takeCase(incident),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          AppColors.primaryButton,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(26),
                      ),
                    ),
                    child: const Text(
                      'Take Case',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // =====================================================
              // BACK
              // =====================================================

              Center(
                child: TextButton(
                  onPressed: () =>
                      Navigator.pop(context),
                  child: Text(
                    'Back To Cases',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Incident?>(
      future: _caseFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return _buildLoading();
        }

        if (snapshot.hasError) {
          return _buildError();
        }

        final incident = snapshot.data;

        if (incident == null) {
          return _buildNotFound();
        }

        return _buildCaseDetails(
          context,
          incident,
        );
      },
    );
  }
}

// =============================================================
// DETAIL ROW
// =============================================================

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: AppColors.navy,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}