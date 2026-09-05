import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/incident.dart';
import '../services/app_session.dart';

class UpdateCaseScreen extends StatelessWidget {
  const UpdateCaseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final incidentId = ModalRoute.of(context)?.settings.arguments as String?;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navyDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Update Case',
            style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        top: false,
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
                    Icon(Icons.help_outline, color: AppColors.navy, size: 38),
              ),
              const SizedBox(height: 24),
              Text('Has the emergency been resolved?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    if (incidentId != null) {
                      AppSession.instance.setIncidentStatus(
                          incidentId, IncidentStatus.resolved);
                    }
                    Navigator.pushReplacementNamed(context, '/case-resolved');
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26))),
                  child: const Text('Mark as Resolved',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Back To Case',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
