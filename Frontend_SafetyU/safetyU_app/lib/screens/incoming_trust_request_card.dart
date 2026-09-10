import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class IncomingTrustRequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onConfirm;
  final VoidCallback onReject;
  const IncomingTrustRequestCard({super.key, required this.request, required this.onConfirm, required this.onReject});

  @override
  Widget build(BuildContext context) {
    final sender = request['sender'] as Map<String, dynamic>? ?? {};
    final name = sender['name']?.toString() ?? 'SafetyU user';
    final phone = sender['phone']?.toString() ?? '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.border.withValues(alpha: .6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        if (phone.isNotEmpty) Text(phone, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Text('$name wants to add you as a trusted contact.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: ElevatedButton(onPressed: onConfirm, child: const Text('Confirm'))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton(onPressed: onReject, child: const Text('Reject'))),
        ]),
      ]),
    );
  }
}
