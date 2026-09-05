import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class CaseResolvedScreen extends StatelessWidget {
  const CaseResolvedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                    color: AppColors.success, shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Colors.white, size: 44),
              ),
              const SizedBox(height: 24),
              Text('Case Resolved',
                  style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 10),
              Text(
                'The emergency case has been successfully resolved.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textSecondary,
                    height: 1.4),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pushNamedAndRemoveUntil(
                      context, '/cases', (route) => route.isFirst),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26))),
                  child: const Text('Done',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
