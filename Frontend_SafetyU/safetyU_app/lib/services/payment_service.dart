import 'api_client.dart';

/// One Bakong KHQR payment as returned by the backend — either a Pro
/// subscription charge or a pay-per-contact charge. [qrString] is the raw
/// KHQR payload to render as a QR code (e.g. with `QrImageView`); it is a
/// real, scannable code any Bakong-linked banking/e-wallet app can pay.
class PendingPayment {
  final String id;
  final String purpose;
  final double amount;
  final String currency;
  final String qrString;
  final String md5;
  final DateTime expiresAt;

  PendingPayment({
    required this.id,
    required this.purpose,
    required this.amount,
    required this.currency,
    required this.qrString,
    required this.md5,
    required this.expiresAt,
  });

  factory PendingPayment.fromJson(Map<String, dynamic> json) {
    return PendingPayment(
      // Backend (paymentController.createKhqrPayment) returns the Mongo id
      // under `paymentId`, not `id`.
      id: json['paymentId']?.toString() ?? '',
      purpose: json['purpose']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: json['currency']?.toString() ?? 'USD',
      qrString: json['qrString']?.toString() ?? '',
      md5: json['md5']?.toString() ?? '',
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

/// Status of a payment as the client polls it: 'pending' (still waiting on
/// the Bakong network), 'paid', or 'expired' (the 5-minute QR window ran
/// out — start a new payment).
class PaymentStatus {
  final String status;
  const PaymentStatus(this.status);
  bool get isPaid => status == 'paid';
  bool get isExpired => status == 'expired';
  bool get isPending => status == 'pending';
}

class PaymentService {
  /// Creates a real KHQR code for upgrading to Pro. Scan and pay to
  /// activate — poll [checkStatus] with the returned payment's md5.
  static Future<PendingPayment> createProPayment() async {
    // Backend route (paymentRoutes.js): POST /api/payments/khqr
    final res = await ApiClient.post('/payments/khqr', {
      'purpose': 'pro_subscription',
    });
    // The backend returns the payment fields directly (no `payment`
    // wrapper) — see paymentController.createKhqrPayment.
    return PendingPayment.fromJson(res);
  }

  /// Creates a real KHQR code for buying [extraMain] extra main-contact
  /// slots and/or [extraOther] extra other-contact slots.
  static Future<PendingPayment> createPayPerContactPayment({
    required int extraMain,
    required int extraOther,
  }) async {
    // Backend route: POST /api/payments/khqr
    final res = await ApiClient.post('/payments/khqr', {
      'purpose': 'pay_per_contact',
      // Backend (paymentController.createKhqrPayment) reads
      // req.body.extraMain / req.body.extraOther, not *Slots.
      'extraMain': extraMain,
      'extraOther': extraOther,
    });
    return PendingPayment.fromJson(res);
  }

  /// Polls whether the payment identified by [md5] has actually settled on
  /// the Bakong network yet. Call this every few seconds while the QR is
  /// on screen. Note: the backend looks this up by the KHQR md5 hash, not
  /// the Mongo payment id — pass [PendingPayment.md5], not `.id`.
  static Future<PaymentStatus> checkStatus(String md5) async {
    // Backend route: GET /api/payments/khqr/:md5/status
    final res = await ApiClient.get('/payments/khqr/$md5/status');
    return PaymentStatus(res['status']?.toString() ?? 'pending');
  }
}
