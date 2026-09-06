import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/app_session.dart';

/// Shown when the person tries to notify more contacts than the free plan
/// allows. Returns `'pro'` if they tapped the Pro plan (already upgraded by
/// the time this returns), `'pay'` if they want to see the pay-per-contact
/// breakdown next, or `null` if they backed out.
Future<String?> showLimitReachedDialog(
  BuildContext context, {
  required int selectedMain,
  required int selectedOther,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _LimitReachedDialog(
      selectedMain: selectedMain,
      selectedOther: selectedOther,
    ),
  );
}

/// Shown after choosing "pay per contact" — breaks down exactly how many
/// extra Main/Other slots are needed and the one-time cost. Returns `true`
/// if the (simulated) payment succeeded.
Future<bool> showAddExtraContactsDialog(
  BuildContext context, {
  required int extraMain,
  required int extraOther,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _AddExtraContactsDialog(
      extraMain: extraMain,
      extraOther: extraOther,
    ),
  );
  return result ?? false;
}

const double _pricePerContact = 0.20;

enum _LimitStep { plans, proSummary, proScan, proSuccess }

class _LimitReachedDialog extends StatefulWidget {
  final int selectedMain;
  final int selectedOther;

  const _LimitReachedDialog(
      {required this.selectedMain, required this.selectedOther});

  @override
  State<_LimitReachedDialog> createState() => _LimitReachedDialogState();
}

class _LimitReachedDialogState extends State<_LimitReachedDialog> {
  static const double _proMonthlyPrice = 2.99;

  _LimitStep _step = _LimitStep.plans;

  Future<void> _beginProPayment() async {
    setState(() => _step = _LimitStep.proScan);
    // Demo-only stand-in for the real payment gateway calling back once the
    // QR code is scanned and paid — Pro is only granted once this actually
    // completes and the Success step is reached, same as the pay-per-contact
    // flow below.
    await Future.delayed(const Duration(seconds: 4));
    if (!mounted) return;
    AppSession.instance.upgradeToPro();
    setState(() => _step = _LimitStep.proSuccess);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step != _LimitStep.proScan,
      child: Dialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.86,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: switch (_step) {
              _LimitStep.plans => _buildPlansStep(context),
              _LimitStep.proSummary => _buildProSummaryStep(context),
              _LimitStep.proScan => _buildProScanStep(context),
              _LimitStep.proSuccess => _buildProSuccessStep(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPlansStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.topRight,
          child: IconButton(
            onPressed: () => Navigator.pop(context, null),
            icon: Icon(Icons.close, color: AppColors.textMuted, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ),
        Container(
          width: 56,
          height: 56,
          decoration:
              BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
          child: const Icon(Icons.groups, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 14),
        Text("You've reached the limit",
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text(
          'Free plan allows up to ${AppSession.freeMainContactLimit} main contacts and ${AppSession.freeOtherContactLimit} other contacts.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _countBlock('${widget.selectedMain}', 'Main Contacts'),
              Text('+',
                  style: TextStyle(
                      fontSize: 18,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700)),
              _countBlock('${widget.selectedOther}', 'Other Contacts'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Upgrade to Pro or pay a small fee to add more contacts.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        _PlanOption(
          icon: Icons.card_giftcard,
          title: 'Free Plan',
          tag: 'Current',
          subtitle:
              'Up to ${AppSession.freeMainContactLimit} main + ${AppSession.freeOtherContactLimit} other contacts',
          highlighted: false,
          onTap: null,
        ),
        const SizedBox(height: 10),
        _PlanOption(
          icon: Icons.workspace_premium,
          title: 'Pro Plan',
          tag: 'Most Popular',
          subtitle:
              'Unlimited contacts & all premium features — \$${_proMonthlyPrice.toStringAsFixed(2)}/month',
          highlighted: true,
          // Tapping Pro no longer upgrades instantly — it opens the same
          // kind of payment flow Pay Per Contact uses, and Pro is only
          // granted once that (simulated) payment actually completes.
          onTap: () => setState(() => _step = _LimitStep.proSummary),
        ),
        const SizedBox(height: 10),
        _PlanOption(
          icon: Icons.person_add_alt_1,
          title: 'Pay Per Contact',
          tag: null,
          subtitle:
              'Add extra contacts without upgrading — \$${_pricePerContact.toStringAsFixed(2)}/person',
          highlighted: false,
          onTap: () => Navigator.pop(context, 'pay'),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, 'pay'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navy,
                minimumSize: const Size(0, 46)),
            child: const Text('View Options'),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text('Choose Different Contacts Instead',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      ],
    );
  }

  Widget _buildProSummaryStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => setState(() => _step = _LimitStep.plans),
              icon: Icon(Icons.arrow_back, color: AppColors.textMuted),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const Spacer(),
            IconButton(
              onPressed: () => Navigator.pop(context, null),
              icon: Icon(Icons.close, color: AppColors.textMuted, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        Container(
          width: 56,
          height: 56,
          decoration:
              BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
          child: const Icon(Icons.workspace_premium,
              color: Colors.white, size: 26),
        ),
        const SizedBox(height: 14),
        Text('Upgrade to Pro',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text(
          'Unlimited contacts and all premium features, billed monthly.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.navy.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Pro Plan',
                  style: TextStyle(
                      fontSize: 11.5, color: AppColors.textSecondary)),
              Text('\$${_proMonthlyPrice.toStringAsFixed(2)}/month',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Cancel anytime. You\'ll be charged again each month until you do.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _beginProPayment,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navy,
                minimumSize: const Size(0, 46)),
            child: const Text('Continue to Payment'),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child:
              Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
        ),
      ],
    );
  }

  Widget _buildProScanStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Scan to Pay',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text('\$${_proMonthlyPrice.toStringAsFixed(2)}',
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppColors.navy)),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: _QrCode(
            seed: (_proMonthlyPrice * 100).round(),
            size: 180,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.navy),
            ),
            const SizedBox(width: 10),
            Text('Waiting for payment confirmation…',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Open your banking or e-wallet app and scan this code to complete the payment. This screen updates automatically once payment is received.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text('Cancel Payment',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      ],
    );
  }

  Widget _buildProSuccessStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration:
              BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
          child: const Icon(Icons.check, color: Colors.white, size: 34),
        ),
        const SizedBox(height: 16),
        Text("You're Pro Now",
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text(
          'Unlimited contacts and all premium features are unlocked.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, 'pro'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navy,
                minimumSize: const Size(0, 46)),
            child: const Text('Continue'),
          ),
        ),
      ],
    );
  }

  Widget _countBlock(String count, String label) {
    return Column(
      children: [
        Text(count,
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFFFF6554))),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _PlanOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? tag;
  final String subtitle;
  final bool highlighted;
  final VoidCallback? onTap;

  const _PlanOption({
    required this.icon,
    required this.title,
    required this.tag,
    required this.subtitle,
    required this.highlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: highlighted
              ? AppColors.navy.withValues(alpha: 0.06)
              : AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: highlighted ? AppColors.navy : AppColors.border,
              width: highlighted ? 1.4 : 1),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 20,
                color: highlighted ? AppColors.navy : AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      if (tag != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color:
                                highlighted ? AppColors.navy : AppColors.border,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(tag!,
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: highlighted
                                      ? Colors.white
                                      : AppColors.textSecondary)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PaymentStep { summary, awaitingScan, success }

class _AddExtraContactsDialog extends StatefulWidget {
  final int extraMain;
  final int extraOther;

  const _AddExtraContactsDialog(
      {required this.extraMain, required this.extraOther});

  @override
  State<_AddExtraContactsDialog> createState() =>
      _AddExtraContactsDialogState();
}

class _AddExtraContactsDialogState extends State<_AddExtraContactsDialog> {
  _PaymentStep _step = _PaymentStep.summary;

  Future<void> _beginPayment() async {
    setState(() => _step = _PaymentStep.awaitingScan);
    // Demo-only stand-in for the real payment gateway calling back once the
    // QR code is scanned and paid — nothing is granted to the account until
    // this actually completes and the Success step is reached.
    await Future.delayed(const Duration(seconds: 4));
    if (!mounted) return;
    setState(() => _step = _PaymentStep.success);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step != _PaymentStep.awaitingScan,
      child: Dialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.86,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: switch (_step) {
              _PaymentStep.summary => _buildSummary(context),
              _PaymentStep.awaitingScan => _buildQrStep(context),
              _PaymentStep.success => _buildSuccessStep(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final extraTotal = widget.extraMain + widget.extraOther;
    final total = extraTotal * _pricePerContact;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context, false),
              icon: Icon(Icons.arrow_back, color: AppColors.textMuted),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const Spacer(),
            IconButton(
              onPressed: () => Navigator.pop(context, false),
              icon: Icon(Icons.close, color: AppColors.textMuted, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
              color: const Color(0xFFFF6554), shape: BoxShape.circle),
          child: const Icon(Icons.account_balance_wallet,
              color: Colors.white, size: 26),
        ),
        const SizedBox(height: 14),
        Text('Add Extra Contacts',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text(
          extraTotal == 1
              ? "You're adding 1 extra contact."
              : "You're adding $extraTotal extra contacts.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              if (widget.extraMain > 0)
                _extraRow('Main Contact', widget.extraMain),
              if (widget.extraMain > 0 && widget.extraOther > 0)
                const SizedBox(height: 8),
              if (widget.extraOther > 0)
                _extraRow('Other Contact', widget.extraOther),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.navy.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('\$${_pricePerContact.toStringAsFixed(2)} per extra contact',
                  style: TextStyle(
                      fontSize: 11.5, color: AppColors.textSecondary)),
              Text('\$${total.toStringAsFixed(2)} total',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'No monthly fees. Pay only when you add more.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _beginPayment,
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6554),
                minimumSize: const Size(0, 46)),
            child: const Text('Continue to Payment'),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child:
              Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
        ),
      ],
    );
  }

  Widget _buildQrStep(BuildContext context) {
    final extraTotal = widget.extraMain + widget.extraOther;
    final total = extraTotal * _pricePerContact;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Scan to Pay',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text('\$${total.toStringAsFixed(2)}',
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppColors.navy)),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: _QrCode(
            seed: (total * 100).round(),
            size: 180,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.navy),
            ),
            const SizedBox(width: 10),
            Text('Waiting for payment confirmation…',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Open your banking or e-wallet app and scan this code to complete the payment. This screen updates automatically once payment is received.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel Payment',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      ],
    );
  }

  Widget _buildSuccessStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration:
              BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
          child: const Icon(Icons.check, color: Colors.white, size: 34),
        ),
        const SizedBox(height: 16),
        Text('Payment Successful',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text(
          'Your extra contact slots have been added to this session.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navy,
                minimumSize: const Size(0, 46)),
            child: const Text('Continue'),
          ),
        ),
      ],
    );
  }

  Widget _extraRow(String label, int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(fontSize: 12.5, color: AppColors.textPrimary)),
        Text('+$count',
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFFFF6554))),
      ],
    );
  }
}

/// A self-contained, dependency-free stand-in for a real QR code. This demo
/// has no payment gateway to generate an actual scannable code for, so this
/// draws a deterministic (seeded) QR-like block pattern purely for the
/// visual — swap in a real generator (e.g. the `qr_flutter` package) once a
/// real payment provider is wired up.
class _QrCode extends StatelessWidget {
  final int seed;
  final double size;

  const _QrCode({required this.seed, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _QrPainter(seed: seed)),
    );
  }
}

class _QrPainter extends CustomPainter {
  final int seed;
  static const int _grid = 21;

  _QrPainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / _grid;
    final random = Random(seed);
    final paint = Paint()..color = const Color(0xFF0B1F3A);

    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    bool isFinder(int r, int c) {
      const positions = [
        [0, 0],
        [0, _grid - 7],
        [_grid - 7, 0],
      ];
      for (final p in positions) {
        if (r >= p[0] && r < p[0] + 7 && c >= p[1] && c < p[1] + 7) {
          return true;
        }
      }
      return false;
    }

    void drawFinder(int r, int c) {
      canvas.drawRect(
        Rect.fromLTWH(c * cell, r * cell, cell * 7, cell * 7),
        paint,
      );
      canvas.drawRect(
        Rect.fromLTWH((c + 1) * cell, (r + 1) * cell, cell * 5, cell * 5),
        Paint()..color = Colors.white,
      );
      canvas.drawRect(
        Rect.fromLTWH((c + 2) * cell, (r + 2) * cell, cell * 3, cell * 3),
        paint,
      );
    }

    for (var r = 0; r < _grid; r++) {
      for (var c = 0; c < _grid; c++) {
        if (isFinder(r, c)) continue;
        if (random.nextDouble() < 0.42) {
          canvas.drawRect(
            Rect.fromLTWH(c * cell, r * cell, cell, cell),
            paint,
          );
        }
      }
    }

    drawFinder(0, 0);
    drawFinder(0, _grid - 7);
    drawFinder(_grid - 7, 0);
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) =>
      oldDelegate.seed != seed;
}
