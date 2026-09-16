import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../models/incident.dart';
import '../services/app_session.dart';
import '../services/emergency_responder_service.dart';
import '../widgets/responder_bottom_nav.dart';
import '../widgets/case_status_widgets.dart';

class CasesScreen extends StatefulWidget {
  const CasesScreen({super.key});

  @override
  State<CasesScreen> createState() => _CasesScreenState();
}

class _CasesScreenState extends State<CasesScreen> {
  IncidentStatus? _filter; // null = All

  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCases();
  }

  Future<void> _loadCases() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final cases =
          await EmergencyResponderService.fetchCases();

      // Keep the existing AppSession-based UI architecture
      // synchronized with the real backend cases.
      AppSession.instance.activeIncidents
        ..clear()
        ..addAll(cases);

      if (!mounted) return;

      setState(() {
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorMessage =
            'Unable to load emergency cases.';
      });
    }
  }

  void _onNavTap(int index) {
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(
          context,
          '/emergency-home',
        );
        break;

      case 2:
        Navigator.pushReplacementNamed(
          context,
          '/reports',
        );
        break;

      case 3:
        Navigator.pushReplacementNamed(
          context,
          '/profile',
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final all =
        AppSession.instance.activeIncidents;

    final filtered = _filter == null
        ? all
        : all
            .where(
              (incident) =>
                  incident.status == _filter,
            )
            .toList();

    return Scaffold(
      backgroundColor: AppColors.background,

      appBar: AppBar(
        backgroundColor: AppColors.navyDark,
        elevation: 0,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: const Text(
          'Cases',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loadCases,
            icon: const Icon(
              Icons.refresh,
              color: Colors.white,
            ),
          ),
        ],
      ),

      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(
                16,
                12,
                16,
                8,
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'All',
                      selected: _filter == null,
                      onTap: () {
                        setState(() {
                          _filter = null;
                        });
                      },
                    ),

                    const SizedBox(width: 8),

                    _FilterChip(
                      label: 'New',
                      color: AppColors.danger,
                      selected:
                          _filter ==
                              IncidentStatus.newCase,
                      onTap: () {
                        setState(() {
                          _filter =
                              IncidentStatus.newCase;
                        });
                      },
                    ),

                    const SizedBox(width: 8),

                    _FilterChip(
                      label: 'In Progress',
                      color:
                          const Color(0xFFE59A2E),
                      selected:
                          _filter ==
                              IncidentStatus.inProgress,
                      onTap: () {
                        setState(() {
                          _filter =
                              IncidentStatus.inProgress;
                        });
                      },
                    ),

                    const SizedBox(width: 8),

                    _FilterChip(
                      label: 'Resolved',
                      color:
                          AppColors.success,
                      selected:
                          _filter ==
                              IncidentStatus.resolved,
                      onTap: () {
                        setState(() {
                          _filter =
                              IncidentStatus.resolved;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),

            Expanded(
              child: _buildBody(filtered),
            ),
          ],
        ),
      ),

      bottomNavigationBar:
          ResponderBottomNav(
        currentIndex: 1,
        onTap: _onNavTap,
      ),
    );
  }

  Widget _buildBody(List<Incident> filtered) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 42,
                color: AppColors.textMuted,
              ),

              const SizedBox(height: 12),

              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color:
                      AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 16),

              OutlinedButton(
                onPressed: _loadCases,
                child:
                    const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 32,
          ),
          child: Text(
            'No cases here yet.',
            style: TextStyle(
              color:
                  AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCases,
      child: ListView.separated(
        padding:
            const EdgeInsets.fromLTRB(
          16,
          4,
          16,
          16,
        ),
        itemCount: filtered.length,
        separatorBuilder: (_, __) =>
            const SizedBox(height: 10),

        itemBuilder: (context, index) {
          final incident =
              filtered[index];

          return GestureDetector(
            onTap: () async {
              await Navigator.pushNamed(
                context,
                '/case-detail',
                arguments: incident.id,
              );

              // Refresh after returning from
              // case details.
              if (mounted) {
                _loadCases();
              }
            },

            child: Container(
              padding:
                  const EdgeInsets.all(14),

              decoration:
                  BoxDecoration(
                color: AppColors.card,
                borderRadius:
                    BorderRadius.circular(14),
                border: Border(
                  left: BorderSide(
                    color: caseStatusColor(
                      incident.status,
                    ),
                    width: 4,
                  ),
                ),
              ),

              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Emergency Assistance',
                          style:
                              const TextStyle(
                            fontSize: 13.5,
                            fontWeight:
                                FontWeight.w700,
                          ),
                        ),

                        const SizedBox(height: 3),

                        Text(
                          incident.personName,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                AppColors
                                    .textSecondary,
                          ),
                        ),

                        const SizedBox(height: 2),

                        Text(
                          incident.phone.isEmpty
                              ? 'No phone available'
                              : incident.phone,
                          style: TextStyle(
                            fontSize: 11.5,
                            color:
                                AppColors
                                    .textSecondary,
                          ),
                        ),

                        const SizedBox(height: 3),

                        Text(
                          incident.destination,
                          maxLines: 1,
                          overflow:
                              TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                AppColors.textMuted,
                          ),
                        ),

                        const SizedBox(height: 3),

                        Text(
                          formatElapsed(
                            incident.startedAt,
                          ),
                          style: TextStyle(
                            fontSize: 10.5,
                            color:
                                AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 10),

                  CaseStatusBadge(
                    status:
                        incident.status,
                    filled: true,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor =
        color ?? AppColors.navy;

    return GestureDetector(
      onTap: onTap,

      child: Container(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),

        decoration:
            BoxDecoration(
          color: selected
              ? chipColor.withValues(
                  alpha: 0.12,
                )
              : AppColors.card,

          borderRadius:
              BorderRadius.circular(20),

          border: Border.all(
            color: selected
                ? chipColor
                : AppColors.border,
          ),
        ),

        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight:
                FontWeight.w700,
            color: selected
                ? chipColor
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}