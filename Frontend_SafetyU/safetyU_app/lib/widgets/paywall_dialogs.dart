import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../theme/app_theme.dart';
import '../services/app_session.dart';
import '../services/api_client.dart';
import '../services/payment_service.dart';

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
      triggeredByLimit: true,
    ),
  );
}

/// Shown when the person just wants to browse/manage plans — e.g. tapping
/// the "Protected" status card on Home, or a CTA inside the inline plan
/// carousel embedded in that same card — rather than having hit the
/// contact-notification cap. Same plan picker, QR scan, and payment flow as
/// [showLimitReachedDialog], just without the "you've reached the limit"
/// framing.
///
/// Returns:
/// - 'pro' if Pro payment succeeds
/// - 'pay' if Pay Per Contact payment succeeds
/// - null if the dialog is closed/cancelled
Future<String?> showPlansDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (context) => const _LimitReachedDialog(
      selectedMain: 0,
      selectedOther: 0,
      triggeredByLimit: false,
    ),
  );
}

const double _pricePerContact = 0.20;

/// Cambodia commonly prices things in either USD or KHR (Riel) side by
/// side. `_usdToKhrRate` is only used to show an *estimated* KHR figure on
/// the plan-picker/summary screens before a real payment has been created.
/// Once a real KHQR payment exists, the amount actually shown on the scan
/// screen should come from the backend response (`PendingPayment`), not
/// this local conversion — see the TODO further down.
enum _Currency { usd, khr }

const double _usdToKhrRate = 4100;

String _formatPrice(double usdAmount, _Currency currency) {
  if (currency == _Currency.usd) {
    return '\$${usdAmount.toStringAsFixed(2)}';
  }
  final khr = (usdAmount * _usdToKhrRate).round();
  final withCommas = khr
      .toString()
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  return '៛$withCommas';
}

String _currencyCode(_Currency c) => c == _Currency.usd ? 'USD' : 'KHR';

/// Small USD / KHR segmented switch shown on the plan picker and both
/// payment summary screens, before a KHQR code is generated.
class _CurrencyToggle extends StatelessWidget {
  final _Currency value;
  final ValueChanged<_Currency> onChanged;

  const _CurrencyToggle({required this.value, required this.onChanged});

  Widget _segment(_Currency c, String label) {
    final selected = value == c;
    return GestureDetector(
      onTap: () => onChanged(c),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.navy : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(_Currency.usd, 'USD'),
          _segment(_Currency.khr, 'KHR'),
        ],
      ),
    );
  }
}

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
  // False when opened as a general "View Plans" browse (e.g. from the Home
  // status card) rather than because a contact-notification cap was hit —
  // swaps the "you've reached the limit" copy for a plain plan picker and
  // hides the selected-contacts box, which has nothing to show in that case.
  final bool triggeredByLimit;

  const _LimitReachedDialog({
    required this.selectedMain,
    required this.selectedOther,
    this.triggeredByLimit = true,
  });

  @override
  State<_LimitReachedDialog> createState() => _LimitReachedDialogState();
}

class _LimitReachedDialogState extends State<_LimitReachedDialog> {
  static const double _proMonthlyPrice = 2.99;

  /// Initial selection is Free Plan.
  String _selectedPlan = 'free';

  _LimitStep _step = _LimitStep.plans;

  // Which currency the person wants to pay in. Chosen before a payment is
  // created; forwarded to PaymentService so the KHQR itself is generated in
  // that currency (see the TODO on _beginProPayment/_beginPayPayment).
  _Currency _currency = _Currency.usd;

  // Chosen quantities when this dialog is opened as a general "View Plans"
  // browse (Home's status card / "See All Plans") rather than because an
  // actual notify-list exceeded the free cap — i.e. widget.triggeredByLimit
  // is false. In that case widget.selectedMain/selectedOther are always 0
  // (showPlansDialog passes 0, 0), so there is nothing to derive "extra"
  // contacts from. Without these, Pay Per Contact opened from the
  // dashboard always computed 0 extra contacts and its "Continue to
  // Payment" button stayed permanently disabled — the person had no way
  // to say how many slots they wanted. These let them pick the quantity
  // directly via the steppers on the summary screen.
  int _manualExtraMain = 0;
  int _manualExtraOther = 0;

  /// Number of extra Main/Other contact slots being purchased.
  /// - triggeredByLimit: derived from how many contacts they actually
  ///   tried to notify past the free cap (the old behavior).
  /// - browse mode (opened from Home): there's no over-the-cap list to
  ///   derive from, so this reflects what the person picked with the
  ///   quantity steppers instead.
  (int, int) get _extraCounts {
    if (widget.triggeredByLimit) {
      return (
        max(0, widget.selectedMain - AppSession.freeMainContactLimit),
        max(0, widget.selectedOther - AppSession.freeOtherContactLimit),
      );
    }
    return (_manualExtraMain, _manualExtraOther);
  }

  // Real Bakong KHQR payment in flight, if any (see services/payment_service.dart).
  PendingPayment? _pendingPayment;
  String? _paymentError;
  bool _creatingPayment = false;
  Timer? _pollTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  String _friendlyError(Object error) {
    if (error is ApiException || error is ApiConnectionException) {
      return error.toString();
    }
    return 'Something went wrong creating the payment. Please try again.';
  }

  /// Polls the backend every 3s for whether the KHQR on screen has actually
  /// been paid yet (the backend checks the live Bakong network). Stops
  /// itself once the payment settles, expires, or the dialog is closed.
  void _startPolling({required VoidCallback onPaid}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final payment = _pendingPayment;
      if (payment == null || !mounted) return;
      try {
        final status = await PaymentService.checkStatus(payment.md5);
        if (!mounted) return;
        if (status.isPaid) {
          _pollTimer?.cancel();
          onPaid();
        } else if (status.isExpired) {
          _pollTimer?.cancel();
          setState(() {
            _paymentError =
                'This QR code expired before payment was received. Please try again.';
            _step = _LimitStep.plans;
          });
        }
        // isPending: keep waiting quietly, no need to update UI each tick.
      } catch (_) {
        // Transient network hiccup while polling — try again next tick
        // rather than interrupting the person mid-payment.
      }
    });
  }

  // ---------------------------------------------------------------------------
  // PRO PAYMENT
  // ---------------------------------------------------------------------------

  Future<void> _beginProPayment() async {
    // Guard against double-tap / accidental re-entry firing a second
    // create request while the first is still in flight (this is what
    // was causing the backend's duplicate-md5 crash).
    if (_creatingPayment) return;

    setState(() {
      _step = _LimitStep.proScan;
      _creatingPayment = true;
      _paymentError = null;
    });

    try {
      // currency now flows into PaymentService.createProPayment, which
      // sends it to the backend as body key 'currency' (matching the
      // Payment mongoose schema's field name). Not yet confirmed against
      // paymentController.js itself — if the backend reads req.body under
      // a different key, this silently falls back to its 'USD' default.
      final payment = await PaymentService.createProPayment(
        currency: _currencyCode(_currency),
      );
      if (!mounted) return;
      setState(() {
        _pendingPayment = payment;
        _creatingPayment = false;
      });
      _startPolling(
        onPaid: () {
          if (!mounted) return;
          // Credit locally only after the backend confirms the real
          // Bakong payment settled.
          AppSession.instance.upgradeToPro();
          setState(() => _step = _LimitStep.proSuccess);
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creatingPayment = false;
        _paymentError = _friendlyError(error);
      });
    }
  }

  // ---------------------------------------------------------------------------
  // PAY PER CONTACT PAYMENT
  // ---------------------------------------------------------------------------

  Future<void> _beginPayPayment() async {
    // Same double-tap guard as _beginProPayment.
    if (_creatingPayment) return;

    final (extraMain, extraOther) = _extraCounts;

    setState(() {
      _step = _LimitStep.payScan;
      _creatingPayment = true;
      _paymentError = null;
    });

    try {
      // Same currency wiring as _beginProPayment — see the note there.
      final payment = await PaymentService.createPayPerContactPayment(
        extraMain: extraMain,
        extraOther: extraOther,
        currency: _currencyCode(_currency),
      );
      if (!mounted) return;
      setState(() {
        _pendingPayment = payment;
        _creatingPayment = false;
      });
      _startPolling(
        onPaid: () {
          if (!mounted) return;
          AppSession.instance.purchaseExtraSlots(
            extraMain: extraMain,
            extraOther: extraOther,
          );
          setState(() => _step = _LimitStep.paySuccess);
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creatingPayment = false;
        _paymentError = _friendlyError(error);
      });
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step != _LimitStep.proScan && _step != _LimitStep.payScan,
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
            gradient: LinearGradient(
              colors: widget.triggeredByLimit
                  ? [AppColors.navy, AppColors.navy]
                  : [const Color(0xFFFFC24B), const Color(0xFFFF9A3C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: widget.triggeredByLimit
                ? null
                : [
                    BoxShadow(
                      color: const Color(0xFFFF9A3C).withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Icon(
            widget.triggeredByLimit ? Icons.groups : Icons.workspace_premium,
            color: Colors.white,
            size: 28,
          ),
        ),

        const SizedBox(height: 14),

        // Title
        Text(
          widget.triggeredByLimit
              ? "You've reached the limit"
              : 'Choose Your Plan',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),

        const SizedBox(height: 6),

        // Description
        Text(
          widget.triggeredByLimit
              ? 'Free plan allows up to '
                  '${AppSession.freeMainContactLimit} main contacts and '
                  '${AppSession.freeOtherContactLimit} other contacts.'
              : AppSession.instance.isProActive
                  ? "You're on Pro — unlimited contacts and every premium feature."
                  : 'Pick the plan that fits how you stay safe.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondary,
          ),
        ),

        const SizedBox(height: 16),

        // Selected contacts — only meaningful when this dialog was opened
        // because an actual notify-list exceeded the free cap.
        if (widget.triggeredByLimit) ...[
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
        ],

        if (_paymentError != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _paymentError!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5, color: Colors.red),
            ),
          ),
        ],

        const SizedBox(height: 16),

        Text(
          widget.triggeredByLimit
              ? 'Upgrade to Pro or pay a small fee to add more contacts.'
              : 'Upgrade any time — changes apply instantly.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),

        const SizedBox(height: 12),

        _CurrencyToggle(
          value: _currency,
          onChanged: (c) => setState(() => _currency = c),
        ),

        const SizedBox(height: 16),

        // -------------------------------------------------------------------
        // FREE PLAN
        // -------------------------------------------------------------------

        _PlanOption(
          icon: Icons.card_giftcard,
          title: 'Free Plan',
          tag: AppSession.instance.isProActive ? null : 'Current',
          subtitle: 'Up to ${AppSession.freeMainContactLimit} main + '
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
          tag: AppSession.instance.isProActive ? 'Current' : 'Most Popular',
          subtitle: 'Unlimited contacts & all premium features — '
              '${_formatPrice(_proMonthlyPrice, _currency)}/month',
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
          subtitle: 'Add extra contacts without upgrading — '
              '${_formatPrice(_pricePerContact, _currency)}/person',
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
            widget.triggeredByLimit
                ? 'Choose Different Contacts Instead'
                : 'Maybe Later',
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

        const SizedBox(height: 14),

        _CurrencyToggle(
          value: _currency,
          onChanged: (c) => setState(() => _currency = c),
        ),

        const SizedBox(height: 14),

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
                '${_formatPrice(_proMonthlyPrice, _currency)}/month',
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
        const SizedBox(height: 4),
        Text(
          // qrCurrency is what's actually encoded on the KHQR — normally
          // the same as the locally-selected currency, since the backend
          // now honors it. Only fall back to the local selection while no
          // payment exists yet and we're still showing a pre-payment
          // estimate, or if an older backend build ignores the request.
          _pendingPayment?.qrCurrency ?? _currencyCode(_currency),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          // Once a real payment is created, qrAmount/qrCurrency is exactly
          // what your banking app will show when this code is scanned —
          // the local _formatPrice conversion is only a placeholder while
          // that request is still in flight.
          _pendingPayment != null
              ? _pendingPayment!.qrAmount
                  .toStringAsFixed(_pendingPayment!.qrCurrency == 'USD' ? 2 : 0)
              : _formatPrice(_proMonthlyPrice, _currency),
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
        ),
        if (_pendingPayment != null &&
            _pendingPayment!.qrCurrency != 'USD') ...[
          const SizedBox(height: 2),
          Text(
            // The account is charged/tracked in USD internally even though
            // the QR itself is in another currency — surface both so the
            // amount on screen never looks disconnected from what gets
            // scanned.
            '≈ \$${_pendingPayment!.amount.toStringAsFixed(2)} USD',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
        ],
        const SizedBox(height: 18),
        _khqrPanel(),
        const SizedBox(height: 16),
        if (_paymentError == null)
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
                _creatingPayment
                    ? 'Generating your KHQR code…'
                    : 'Waiting for payment confirmation…',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          )
        else
          Text(
            _paymentError!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.red),
          ),
        const SizedBox(height: 8),
        Text(
          'Open your Bakong-linked banking or e-wallet app and scan this '
          'real KHQR code to complete the payment. This screen updates '
          'automatically once the payment is received.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () {
            _pollTimer?.cancel();
            setState(() {
              _selectedPlan = 'pro';
              _pendingPayment = null;
              _paymentError = null;
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

  /// Shared KHQR-or-loading panel used by both the Pro and Pay Per Contact
  /// scan steps.
  Widget _khqrPanel() {
    return Container(
      padding: const EdgeInsets.all(14),
      width: 208,
      height: 208,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: _creatingPayment || _pendingPayment == null
          ? Center(
              child: CircularProgressIndicator(color: AppColors.navy),
            )
          : QrImageView(
              data: _pendingPayment!.qrString,
              version: QrVersions.auto,
              size: 180,
              gapless: true,
            ),
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
    final (extraMain, extraOther) = _extraCounts;

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
          widget.triggeredByLimit
              ? (extraTotal == 1
                  ? 'You need 1 extra contact.'
                  : 'You need $extraTotal extra contacts.')
              : 'Choose how many extra contact slots to add.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondary,
          ),
        ),

        const SizedBox(height: 14),

        _CurrencyToggle(
          value: _currency,
          onChanged: (c) => setState(() => _currency = c),
        ),

        const SizedBox(height: 14),

        // Browse mode (opened from Home, not from hitting the free-plan
        // cap): there's no already-selected contact list to base the
        // purchase on, so the person picks the quantity directly here.
        if (!widget.triggeredByLimit) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                _quantityStepper(
                  label: 'Main Contact',
                  value: _manualExtraMain,
                  onChanged: (v) => setState(() => _manualExtraMain = v),
                ),
                const SizedBox(height: 12),
                _quantityStepper(
                  label: 'Other Contact',
                  value: _manualExtraOther,
                  onChanged: (v) => setState(() => _manualExtraOther = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ] else ...[
          // Limit-triggered mode: just show the breakdown of what's
          // already been selected on the previous screen.
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
                if (extraMain > 0 && extraOther > 0) const SizedBox(height: 10),
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
          const SizedBox(height: 14),
        ],

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
                '${_formatPrice(_pricePerContact, _currency)} per extra contact',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '${_formatPrice(total, _currency)} total',
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
    final (extraMain, extraOther) = _extraCounts;

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
        const SizedBox(height: 4),
        Text(
          // See the note in _buildProScanStep — qrCurrency is what's
          // actually on the KHQR, not the local currency toggle.
          _pendingPayment?.qrCurrency ?? _currencyCode(_currency),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _pendingPayment != null
              ? _pendingPayment!.qrAmount
                  .toStringAsFixed(_pendingPayment!.qrCurrency == 'USD' ? 2 : 0)
              : _formatPrice(total, _currency),
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
        ),
        if (_pendingPayment != null &&
            _pendingPayment!.qrCurrency != 'USD') ...[
          const SizedBox(height: 2),
          Text(
            '≈ \$${_pendingPayment!.amount.toStringAsFixed(2)} USD',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          '$extraTotal extra contact${extraTotal == 1 ? '' : 's'}',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 18),
        _khqrPanel(),
        const SizedBox(height: 16),
        if (_paymentError == null)
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
                _creatingPayment
                    ? 'Generating your KHQR code…'
                    : 'Waiting for payment confirmation…',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          )
        else
          Text(
            _paymentError!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.red),
          ),
        const SizedBox(height: 8),
        Text(
          'Open your Bakong-linked banking or e-wallet app and scan this '
          'real KHQR code to complete the payment. This screen updates '
          'automatically once the payment is received.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () {
            _pollTimer?.cancel();
            setState(() {
              _selectedPlan = 'pay';
              _pendingPayment = null;
              _paymentError = null;
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
    final (extraMain, extraOther) = _extraCounts;

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
                    _formatPrice(total, _currency),
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

  // ---------------------------------------------------------------------------
  // QUANTITY STEPPER (browse-mode Pay Per Contact — pick counts directly)
  // ---------------------------------------------------------------------------

  Widget _quantityStepper({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _stepperButton(
              icon: Icons.remove,
              onTap: value > 0 ? () => onChanged(value - 1) : null,
            ),
            SizedBox(
              width: 30,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            _stepperButton(
              icon: Icons.add,
              // 20 is a generous ceiling just to avoid an unbounded
              // counter — there's no real-world reason to buy more slots
              // than that in one purchase.
              onTap: value < 20 ? () => onChanged(value + 1) : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _stepperButton(
      {required IconData icon, required VoidCallback? onTap}) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.navy.withValues(alpha: 0.08)
              : AppColors.border.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 15,
          color: enabled ? AppColors.navy : AppColors.textMuted,
        ),
      ),
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
            color: highlighted ? AppColors.navy : AppColors.border,
            width: highlighted ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: highlighted ? AppColors.navy : AppColors.textSecondary,
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
                            color:
                                highlighted ? AppColors.navy : AppColors.border,
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
// PLAN PROMO SLIDES — shared data for both the inline carousel (embedded in
// the Home "Protected" card) and the popup carousel below.
// ===========================================================================

class _PlanPromoSlide {
  final List<Color> gradient;
  final IconData icon;
  final String eyebrow;
  final String title;
  final String price;
  final List<String> bullets;
  final String ctaLabel;

  const _PlanPromoSlide({
    required this.gradient,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.price,
    required this.bullets,
    required this.ctaLabel,
  });

  // A muted version of the slide's own accent for icon/text sitting on the
  // white CTA pill and price chip, so each slide reads as its own color
  // (navy/orange/teal) rather than all three looking identical.
  Color get accent => gradient.last;
}

const List<_PlanPromoSlide> _promoSlides = [
  _PlanPromoSlide(
    gradient: [Color(0xFF232B52), Color(0xFF11142A)],
    icon: Icons.card_giftcard_rounded,
    eyebrow: 'YOUR CURRENT PLAN',
    title: 'Free',
    price: '\$0',
    bullets: [
      'Up to 2 main contacts',
      '1 other contact',
      'Core safety sessions',
    ],
    ctaLabel: 'See All Plans',
  ),
  _PlanPromoSlide(
    gradient: [Color(0xFFFFC24B), Color(0xFFFF7A3C)],
    icon: Icons.workspace_premium_rounded,
    eyebrow: 'MOST POPULAR',
    title: 'Pro',
    price: '\$2.99/mo',
    bullets: [
      'Unlimited contacts',
      'All premium features',
      'Priority emergency alerts',
    ],
    ctaLabel: 'Upgrade to Pro',
  ),
  _PlanPromoSlide(
    gradient: [Color(0xFF0F9B7E), Color(0xFF29D6A8)],
    icon: Icons.person_add_alt_1_rounded,
    eyebrow: 'PAY AS YOU GO',
    title: 'Pay Per Contact',
    price: '\$0.20 / person',
    bullets: [
      'No subscription',
      'Add contacts any time',
      'One-time payment',
    ],
    ctaLabel: 'Add Contacts',
  ),
];

// ===========================================================================
// INLINE PLAN CAROUSEL — lives permanently inside the "You are Protected"
// card on Home for free-plan users (see home_dashboard_screen.dart). This
// replaces the old "pulsing chip + separate 30s popup" approach: instead of
// interrupting the person with a modal, the same Free / Pro / Pay-Per-Contact
// slides just sit right there, always visible, autoplaying and swipeable.
// Tapping a slide's CTA opens the real [showPlansDialog] flow (QR/Bakong
// payment) — this widget itself never touches payment.
// ===========================================================================

class PlanPromoInlineCard extends StatefulWidget {
  final VoidCallback onSeeAllPlans;

  const PlanPromoInlineCard({super.key, required this.onSeeAllPlans});

  @override
  State<PlanPromoInlineCard> createState() => _PlanPromoInlineCardState();
}

class _PlanPromoInlineCardState extends State<PlanPromoInlineCard> {
  final PageController _pageController = PageController();
  Timer? _autoplayTimer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _restartAutoplay();
  }

  void _restartAutoplay() {
    _autoplayTimer?.cancel();
    _autoplayTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_pageController.hasClients) return;
      final next = (_page + 1) % _promoSlides.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _autoplayTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
    // Restart the timer so a manual swipe/tap doesn't just get overridden
    // by autoplay a second later.
    _restartAutoplay();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 174,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: _promoSlides.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => _InlinePromoSlideView(
                slide: _promoSlides[i],
                onCta: widget.onSeeAllPlans,
              ),
            ),
            Positioned(
              left: 2,
              top: 0,
              bottom: 0,
              child: Center(
                child: _PromoArrow(
                  icon: Icons.chevron_left,
                  onTap: () => _goTo(
                      (_page - 1 + _promoSlides.length) % _promoSlides.length),
                ),
              ),
            ),
            Positioned(
              right: 2,
              top: 0,
              bottom: 0,
              child: Center(
                child: _PromoArrow(
                  icon: Icons.chevron_right,
                  onTap: () => _goTo((_page + 1) % _promoSlides.length),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_promoSlides.length, (i) {
                  final active = i == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color:
                          Colors.white.withValues(alpha: active ? 0.95 : 0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlinePromoSlideView extends StatelessWidget {
  final _PlanPromoSlide slide;
  final VoidCallback onCta;

  const _InlinePromoSlideView({required this.slide, required this.onCta});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: slide.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Faint full-bleed watermark of the slide's own icon, same idea as
          // the leaf/shield background texture in the reference mockups.
          Positioned(
            right: -22,
            bottom: -22,
            child: Icon(
              slide.icon,
              size: 130,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),

          // The glowing "medallion" standing in for the 3D badge/shield
          // renders in the reference mockups — an icon on a soft glow disc, ringed
          // by a thin orbit line and a small sparkle accent.
          Positioned(
            right: 14,
            top: 14,
            child: _PromoMedallion(icon: slide.icon),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Eyebrow pill (crown icon, like "MOST POPULAR" / "PAY AS
                // YOU GO" in the reference) + coin-style price chip.
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.workspace_premium,
                              color: Colors.white, size: 11),
                          const SizedBox(width: 4),
                          Text(
                            slide.eyebrow,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.payments,
                              color: Colors.white, size: 11),
                          const SizedBox(width: 4),
                          Text(
                            slide.price,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Small icon avatar + title/subtitle, mirroring the
                // "Free / Up to 2 main contacts" row in the reference.
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(slide.icon, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            slide.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                            ),
                          ),
                          Text(
                            slide.bullets.first,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),

                // CTA pill, same "white pill, colored label + arrow" shape
                // as the reference's "See All Plans" / "Add Contacts".
                GestureDetector(
                  onTap: onCta,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          slide.ctaLabel,
                          style: TextStyle(
                            color: slide.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Icon(Icons.arrow_forward,
                            color: slide.accent, size: 13),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Glowing icon-on-a-disc with a thin orbit ring and a sparkle accent —
/// a lightweight, vector stand-in for the 3D crown/shield/people-card
/// renders in the reference mockups, built entirely from Flutter primitives
/// so it stays crisp at any size and needs no image assets.
class _PromoMedallion extends StatelessWidget {
  final IconData icon;
  const _PromoMedallion({required this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft outer glow.
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.22),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          // Thin orbit ring.
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.35),
                width: 1.2,
              ),
            ),
          ),
          // Icon medallion.
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          // Sparkle accent, top-right of the medallion.
          const Positioned(
            top: 2,
            right: 2,
            child: Icon(Icons.auto_awesome, color: Colors.white, size: 14),
          ),
        ],
      ),
    );
  }
}

class _PromoArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _PromoArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.22),
          shape: BoxShape.circle,
        ),
        child:
            Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 20),
      ),
    );
  }
}
