import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/app_session.dart';

/// Shown when the person tries to notify more contacts than the free plan
/// allows.
///
/// Returns:
/// - 'pro' if Pro payment succeeds
/// - 'pay' if Pay Per Contact payment succeeds
/// - null if the dialog is closed/cancelled
Future<String?> showLimitReachedDialog(
  BuildContext context, {
  required int selectedMain,
  required int selectedOther,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _LimitReachedDialog(
      selectedMain: selectedMain,
      selectedOther: selectedOther,
    ),
  );
}

const double _pricePerContact = 0.20;

enum _LimitStep {
  plans,

  // Free
  freeSummary,

  // Pro
  proSummary,
  proScan,
  proSuccess,

  // Pay Per Contact
  paySummary,
  payScan,
  paySuccess,
}

class _LimitReachedDialog extends StatefulWidget {
  final int selectedMain;
  final int selectedOther;

  const _LimitReachedDialog({
    required this.selectedMain,
    required this.selectedOther,
  });

  @override
  State<_LimitReachedDialog> createState() => _LimitReachedDialogState();
}

class _LimitReachedDialogState extends State<_LimitReachedDialog> {
  static const double _proMonthlyPrice = 2.99;

  /// Initial selection is Free Plan.
  String _selectedPlan = 'free';

  _LimitStep _step = _LimitStep.plans;

  // ---------------------------------------------------------------------------
  // PRO PAYMENT
  // ---------------------------------------------------------------------------

  Future<void> _beginProPayment() async {
    setState(() {
      _step = _LimitStep.proScan;
    });

    // Demo payment delay.
    await Future.delayed(const Duration(seconds: 4));

    if (!mounted) return;

    // Upgrade only after payment completes.
    AppSession.instance.upgradeToPro();

    setState(() {
      _step = _LimitStep.proSuccess;
    });
  }

  // ---------------------------------------------------------------------------
  // PAY PER CONTACT PAYMENT
  // ---------------------------------------------------------------------------

  Future<void> _beginPayPayment() async {
    setState(() {
      _step = _LimitStep.payScan;
    });

    // Demo payment delay.
    await Future.delayed(const Duration(seconds: 4));

    if (!mounted) return;

    setState(() {
      _step = _LimitStep.paySuccess;
    });
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step != _LimitStep.proScan &&
          _step != _LimitStep.payScan,
      child: Dialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.86,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: switch (_step) {
              _LimitStep.plans => _buildPlansStep(context),

              // Free
              _LimitStep.freeSummary => _buildFreeSummaryStep(context),

              // Pro
              _LimitStep.proSummary => _buildProSummaryStep(context),
              _LimitStep.proScan => _buildProScanStep(context),
              _LimitStep.proSuccess => _buildProSuccessStep(context),

              // Pay Per Contact
              _LimitStep.paySummary => _buildPaySummaryStep(context),
              _LimitStep.payScan => _buildPayScanStep(context),
              _LimitStep.paySuccess => _buildPaySuccessStep(context),
            },
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PLANS
  // ---------------------------------------------------------------------------

  Widget _buildPlansStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.topRight,
          child: IconButton(
            onPressed: () => Navigator.pop(context, null),
            icon: Icon(
              Icons.close,
              color: AppColors.textMuted,
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ),

        // Icon
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.navy,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.groups,
            color: Colors.white,
            size: 28,
          ),
        ),

        const SizedBox(height: 14),

        // Title
        Text(
          "You've reached the limit",
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),

        const SizedBox(height: 6),

        // Description
        Text(
          'Free plan allows up to '
          '${AppSession.freeMainContactLimit} main contacts and '
          '${AppSession.freeOtherContactLimit} other contacts.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondary,
          ),
        ),

        const SizedBox(height: 16),

        // Selected contacts
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
              _countBlock(
                '${widget.selectedMain}',
                'Main Contacts',
              ),
              Text(
                '+',
                style: TextStyle(
                  fontSize: 18,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              _countBlock(
                '${widget.selectedOther}',
                'Other Contacts',
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        Text(
          'Upgrade to Pro or pay a small fee to add more contacts.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),

        const SizedBox(height: 16),

        // -------------------------------------------------------------------
        // FREE PLAN
        // -------------------------------------------------------------------

        _PlanOption(
          icon: Icons.card_giftcard,
          title: 'Free Plan',
          tag: 'Current',
          subtitle:
              'Up to ${AppSession.freeMainContactLimit} main + '
              '${AppSession.freeOtherContactLimit} other contacts',
          highlighted: _selectedPlan == 'free',
          onTap: () {
            setState(() {
              _selectedPlan = 'free';
              _step = _LimitStep.freeSummary;
            });
          },
        ),

        const SizedBox(height: 10),

        // -------------------------------------------------------------------
        // PRO PLAN
        // -------------------------------------------------------------------

        _PlanOption(
          icon: Icons.workspace_premium,
          title: 'Pro Plan',
          tag: 'Most Popular',
          subtitle:
              'Unlimited contacts & all premium features — '
              '\$${_proMonthlyPrice.toStringAsFixed(2)}/month',
          highlighted: _selectedPlan == 'pro',
          onTap: () {
            setState(() {
              _selectedPlan = 'pro';
              _step = _LimitStep.proSummary;
            });
          },
        ),

        const SizedBox(height: 10),

        // -------------------------------------------------------------------
        // PAY PER CONTACT
        // -------------------------------------------------------------------

        _PlanOption(
          icon: Icons.person_add_alt_1,
          title: 'Pay Per Contact',
          tag: 'One-Pay-Per-Person',
          subtitle:
              'Add extra contacts without upgrading — '
              '\$${_pricePerContact.toStringAsFixed(2)}/person',
          highlighted: _selectedPlan == 'pay',
          onTap: () {
            setState(() {
              _selectedPlan = 'pay';
              _step = _LimitStep.paySummary;
            });
          },
        ),

        const SizedBox(height: 16),

        // -------------------------------------------------------------------
        // VIEW OPTIONS
        // -------------------------------------------------------------------

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              setState(() {
                if (_selectedPlan == 'free') {
                  _step = _LimitStep.freeSummary;
                } else if (_selectedPlan == 'pro') {
                  _step = _LimitStep.proSummary;
                } else {
                  _step = _LimitStep.paySummary;
                }
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.navy,
              minimumSize: const Size(0, 46),
            ),
            child: const Text('View Options'),
          ),
        ),

        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(
            'Choose Different Contacts Instead',
            style: TextStyle(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // FREE SUMMARY
  // ---------------------------------------------------------------------------

  Widget _buildFreeSummaryStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _summaryHeader(
          onBack: () {
            setState(() {
              _step = _LimitStep.plans;
            });
          },
        ),

        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.navy,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.card_giftcard,
            color: Colors.white,
            size: 26,
          ),
        ),

        const SizedBox(height: 14),

        Text(
          'Free Plan',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),

        const SizedBox(height: 6),

        Text(
          'You are currently using the Free Plan.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondary,
          ),
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
              _freeFeatureRow(
                'Main Contacts',
                'Up to ${AppSession.freeMainContactLimit}',
              ),
              const SizedBox(height: 10),
              _freeFeatureRow(
                'Other Contacts',
                'Up to ${AppSession.freeOtherContactLimit}',
              ),
              const SizedBox(height: 10),
              _freeFeatureRow(
                'Monthly Fee',
                'Free',
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        Text(
          'You can continue using the Free Plan, but you cannot add more '
          'contacts until you choose another option.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
          ),
        ),

        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              Navigator.pop(context, null);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.navy,
              minimumSize: const Size(0, 46),
            ),
            child: const Text('Continue with Free Plan'),
          ),
        ),

        TextButton(
          onPressed: () {
            setState(() {
              _step = _LimitStep.plans;
            });
          },
          child: Text(
            'Back to Plans',
            style: TextStyle(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // PRO SUMMARY
  // ---------------------------------------------------------------------------

  Widget _buildProSummaryStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _summaryHeader(
          onBack: () {
            setState(() {
              _step = _LimitStep.plans;
            });
          },
        ),

        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.navy,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.workspace_premium,
            color: Colors.white,
            size: 26,
          ),
        ),

        const SizedBox(height: 14),

        Text(
          'Upgrade to Pro',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),

        const SizedBox(height: 6),

        Text(
          'Unlimited contacts and all premium features, billed monthly.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondary,
          ),
        ),

        const SizedBox(height: 16),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: AppColors.navy.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Pro Plan',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '\$${_proMonthlyPrice.toStringAsFixed(2)}/month',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        Text(
          'Cancel anytime. You\'ll be charged again each month until you do.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10.5,
            color: AppColors.textMuted,
          ),
        ),

        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _beginProPayment,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.navy,
              minimumSize: const Size(0, 46),
            ),
            child: const Text('Continue to Payment'),
          ),
        ),

        // IMPORTANT:
        // Cancel returns to Plans instead of closing the dialog.
        TextButton(
          onPressed: () {
            setState(() {
              _step = _LimitStep.plans;
            });
          },
          child: Text(
            'Cancel',
            style: TextStyle(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // PRO SCAN
  // ---------------------------------------------------------------------------

  Widget _buildProScanStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Scan to Pay',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),

        const SizedBox(height: 6),

        Text(
          '\$${_proMonthlyPrice.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
        ),

        const SizedBox(height: 18),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.border,
            ),
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
                strokeWidth: 2,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Waiting for payment confirmation…',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        Text(
          'Open your banking or e-wallet app and scan this code to complete '
          'the payment. This screen updates automatically once payment is received.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
          ),
        ),

        const SizedBox(height: 16),

        TextButton(
          onPressed: () {
            setState(() {
              _selectedPlan = 'pro';
              _step = _LimitStep.plans;
            });
          },
          child: Text(
            'Cancel Payment',
            style: TextStyle(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // PRO SUCCESS
  // ---------------------------------------------------------------------------

  Widget _buildProSuccessStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.success,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check,
            color: Colors.white,
            size: 34,
          ),
        ),

        const SizedBox(height: 16),

        Text(
          "You're Pro Now",
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),

        const SizedBox(height: 6),

        Text(
          'Unlimited contacts and all premium features are unlocked.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondary,
          ),
        ),

        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, 'pro'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.navy,
              minimumSize: const Size(0, 46),
            ),
            child: const Text('Continue'),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // PAY PER CONTACT SUMMARY
  // ---------------------------------------------------------------------------

  Widget _buildPaySummaryStep(BuildContext context) {
    final extraMain = max(
      0,
      widget.selectedMain - AppSession.freeMainContactLimit,
    );

    final extraOther = max(
      0,
      widget.selectedOther - AppSession.freeOtherContactLimit,
    );

    final extraTotal = extraMain + extraOther;
    final total = extraTotal * _pricePerContact;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _summaryHeader(
          onBack: () {
            setState(() {
              _step = _LimitStep.plans;
            });
          },
        ),

        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFFF6554),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.account_balance_wallet,
            color: Colors.white,
            size: 26,
          ),
        ),

        const SizedBox(height: 14),

        Text(
          'Pay Per Contact',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),

        const SizedBox(height: 6),

        Text(
          extraTotal == 1
              ? 'You need 1 extra contact.'
              : 'You need $extraTotal extra contacts.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondary,
          ),
        ),

        const SizedBox(height: 16),

        // Extra contact breakdown
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              if (extraMain > 0)
                _extraRow(
                  'Main Contact',
                  extraMain,
                ),

              if (extraMain > 0 && extraOther > 0)
                const SizedBox(height: 10),

              if (extraOther > 0)
                _extraRow(
                  'Other Contact',
                  extraOther,
                ),

              if (extraTotal == 0)
                Text(
                  'No extra contacts are required.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Price
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: AppColors.navy.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '\$${_pricePerContact.toStringAsFixed(2)} per extra contact',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '\$${total.toStringAsFixed(2)} total',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        Text(
          'No monthly fees. Pay only when you add more.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10.5,
            color: AppColors.textMuted,
          ),
        ),

        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: extraTotal > 0 ? _beginPayPayment : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6554),
              minimumSize: const Size(0, 46),
            ),
            child: const Text('Continue to Payment'),
          ),
        ),

        // IMPORTANT:
        // Cancel returns to Plans.
        TextButton(
          onPressed: () {
            setState(() {
              _step = _LimitStep.plans;
            });
          },
          child: Text(
            'Cancel',
            style: TextStyle(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // PAY PER CONTACT SCAN
  // ---------------------------------------------------------------------------

  Widget _buildPayScanStep(BuildContext context) {
    final extraMain = max(
      0,
      widget.selectedMain - AppSession.freeMainContactLimit,
    );

    final extraOther = max(
      0,
      widget.selectedOther - AppSession.freeOtherContactLimit,
    );

    final extraTotal = extraMain + extraOther;
    final total = extraTotal * _pricePerContact;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Scan to Pay',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),

        const SizedBox(height: 6),

        Text(
          '\$${total.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
        ),

        const SizedBox(height: 6),

        Text(
          '$extraTotal extra contact${extraTotal == 1 ? '' : 's'}',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),

        const SizedBox(height: 18),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.border,
            ),
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
                strokeWidth: 2,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Waiting for payment confirmation…',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        Text(
          'Open your banking or e-wallet app and scan this code to complete '
          'the payment. This screen updates automatically once payment is received.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
          ),
        ),

        const SizedBox(height: 16),

        TextButton(
          onPressed: () {
            setState(() {
              _selectedPlan = 'pay';
              _step = _LimitStep.plans;
            });
          },
          child: Text(
            'Cancel Payment',
            style: TextStyle(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // PAY PER CONTACT SUCCESS
  // ---------------------------------------------------------------------------

  Widget _buildPaySuccessStep(BuildContext context) {
    final extraMain = max(
      0,
      widget.selectedMain - AppSession.freeMainContactLimit,
    );

    final extraOther = max(
      0,
      widget.selectedOther - AppSession.freeOtherContactLimit,
    );

    final extraTotal = extraMain + extraOther;
    final total = extraTotal * _pricePerContact;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.success,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check,
            color: Colors.white,
            size: 34,
          ),
        ),

        const SizedBox(height: 16),

        Text(
          'Payment Successful',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),

        const SizedBox(height: 6),

        Text(
          extraTotal == 1
              ? '1 extra contact has been added.'
              : '$extraTotal extra contacts have been added.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondary,
          ),
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
              _extraRow(
                'Extra Contacts',
                extraTotal,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Paid',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '\$${total.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, 'pay'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.navy,
              minimumSize: const Size(0, 46),
            ),
            child: const Text('Continue'),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SUMMARY HEADER
  // ---------------------------------------------------------------------------

  Widget _summaryHeader({
    required VoidCallback onBack,
  }) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: Icon(
            Icons.arrow_back,
            color: AppColors.textMuted,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const Spacer(),
        IconButton(
          onPressed: () => Navigator.pop(context, null),
          icon: Icon(
            Icons.close,
            color: AppColors.textMuted,
            size: 20,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // FREE FEATURE ROW
  // ---------------------------------------------------------------------------

  Widget _freeFeatureRow(
    String title,
    String value,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // CONTACT COUNT
  // ---------------------------------------------------------------------------

  Widget _countBlock(
    String count,
    String label,
  ) {
    return Column(
      children: [
        Text(
          count,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFFFF6554),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // EXTRA CONTACT ROW
  // ---------------------------------------------------------------------------

  Widget _extraRow(
    String label,
    int count,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          '+$count',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFFFF6554),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// PLAN OPTION
// ===========================================================================

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
            color: highlighted
                ? AppColors.navy
                : AppColors.border,
            width: highlighted ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: highlighted
                  ? AppColors.navy
                  : AppColors.textSecondary,
            ),

            const SizedBox(width: 10),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),

                      if (tag != null) ...[
                        const SizedBox(width: 6),

                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: highlighted
                                ? AppColors.navy
                                : AppColors.border,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            tag!,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: highlighted
                                  ? Colors.white
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 2),

                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
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

// ===========================================================================
// QR CODE
// ===========================================================================

class _QrCode extends StatelessWidget {
  final int seed;
  final double size;

  const _QrCode({
    required this.seed,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _QrPainter(
          seed: seed,
        ),
      ),
    );
  }
}

// ===========================================================================
// QR PAINTER
// ===========================================================================

class _QrPainter extends CustomPainter {
  final int seed;

  static const int _grid = 21;

  _QrPainter({
    required this.seed,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final cell = size.width / _grid;
    final random = Random(seed);

    final paint = Paint()
      ..color = const Color(0xFF0B1F3A);

    // White background
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white,
    );

    // Finder pattern positions
    bool isFinder(
      int r,
      int c,
    ) {
      const positions = [
        [0, 0],
        [0, _grid - 7],
        [_grid - 7, 0],
      ];

      for (final p in positions) {
        if (r >= p[0] &&
            r < p[0] + 7 &&
            c >= p[1] &&
            c < p[1] + 7) {
          return true;
        }
      }

      return false;
    }

    // Draw finder pattern
    void drawFinder(
      int r,
      int c,
    ) {
      canvas.drawRect(
        Rect.fromLTWH(
          c * cell,
          r * cell,
          cell * 7,
          cell * 7,
        ),
        paint,
      );

      canvas.drawRect(
        Rect.fromLTWH(
          (c + 1) * cell,
          (r + 1) * cell,
          cell * 5,
          cell * 5,
        ),
        Paint()..color = Colors.white,
      );

      canvas.drawRect(
        Rect.fromLTWH(
          (c + 2) * cell,
          (r + 2) * cell,
          cell * 3,
          cell * 3,
        ),
        paint,
      );
    }

    // Random QR-like blocks
    for (var r = 0; r < _grid; r++) {
      for (var c = 0; c < _grid; c++) {
        if (isFinder(r, c)) continue;

        if (random.nextDouble() < 0.42) {
          canvas.drawRect(
            Rect.fromLTWH(
              c * cell,
              r * cell,
              cell,
              cell,
            ),
            paint,
          );
        }
      }
    }

    // Finder patterns
    drawFinder(0, 0);
    drawFinder(0, _grid - 7);
    drawFinder(_grid - 7, 0);
  }

  @override
  bool shouldRepaint(
    covariant _QrPainter oldDelegate,
  ) {
    return oldDelegate.seed != seed;
  }
}

