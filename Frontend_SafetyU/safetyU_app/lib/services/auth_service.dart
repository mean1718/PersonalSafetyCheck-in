import 'api_client.dart';
import 'app_session.dart';
import 'push_notification_service.dart';
import '../models/user_role.dart';
import '../models/verification_status.dart';

class AuthService {
  // =========================================================
  // REGISTER
  // =========================================================

  static Future<void> register({
    required String fullName,
    required String email,
    required String password,
    required String phone,
    required UserRole role,
    String? officerId,
    String? emergencyPin,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();

    await ApiClient.post(
      '/users/register',
      {
        'name': fullName,
        'email': normalizedEmail,
        'password': password,
        'phone': phone,
        'role': role == UserRole.emergencyResponder ? 'responder' : 'user',

        // -----------------------------------------------------
        // Responder Officer ID
        // -----------------------------------------------------
        if (role == UserRole.emergencyResponder &&
            officerId != null &&
            officerId.trim().isNotEmpty)
          'officerId': officerId.trim().toUpperCase(),

        // -----------------------------------------------------
        // Normal User Emergency PIN
        // -----------------------------------------------------
        if (role == UserRole.user &&
            emergencyPin != null &&
            emergencyPin.trim().isNotEmpty)
          'emergencyPin': emergencyPin.trim(),
      },
      auth: false,
    );

    // Automatically log the new account in.
    await login(
      email: normalizedEmail,
      password: password,
      role: role,
    );
  }

  // =========================================================
  // LOGIN
  // =========================================================

  static Future<void> login({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();

    final data = await ApiClient.post(
      '/users/login',
      {
        'email': normalizedEmail,
        'password': password,
      },
      auth: false,
    );

    final user = data['user'] as Map<String, dynamic>? ?? {};

    // Save JWT token.
    AppSession.instance.authToken = data['token'] as String?;

    // Save backend user ID.
    AppSession.instance.backendUserId = user['id']?.toString();
    AppSession.instance.hasEmergencyPin = user['hasEmergencyPin'] == true;

    // ---------------------------------------------------------
    // Determine actual role from backend
    // ---------------------------------------------------------

    final backendRole = user['role']?.toString() ?? 'user';

    final actualRole = backendRole == 'responder'
        ? UserRole.emergencyResponder
        : UserRole.user;

    // ---------------------------------------------------------
    // Responder Officer ID
    // ---------------------------------------------------------

    AppSession.instance.badgeId = user['officerId']?.toString() ?? '';

    // ---------------------------------------------------------
    // Responder verification status
    // ---------------------------------------------------------

    AppSession.instance.responderStatus = _parseResponderStatus(
      user['responderStatus'],
    );

    // ---------------------------------------------------------
    // Save signed-in user session
    // ---------------------------------------------------------

    AppSession.instance.signIn(
      fullName: (user['name'] as String?) ?? normalizedEmail.split('@').first,
      email: (user['email'] as String?) ?? normalizedEmail,
      phone: (user['phone'] as String?) ?? '',
      role: actualRole,
    );

    AppSession.instance.syncPlanFromBackend(
      isPro: user['isPro'] as bool?,
      proExpiresAt: DateTime.tryParse(user['proExpiresAt']?.toString() ?? ''),
      purchasedExtraMainSlots:
          (user['purchasedExtraMainSlots'] as num?)?.toInt(),
      purchasedExtraOtherSlots:
          (user['purchasedExtraOtherSlots'] as num?)?.toInt(),
      extraSlotsExpireAt:
          DateTime.tryParse(user['extraSlotsExpireAt']?.toString() ?? ''),
    );

    PushNotificationService.registerAfterLogin();
  }

  // =========================================================
// LOGOUT
// =========================================================
//
// Tells the backend that the current responder is offline.
//
// The backend is responsible for changing:
//   isOnline   -> false
//   lastSeenAt -> current time
//
// Local Flutter session cleanup is handled by ProfileScreen.
// =========================================================

  static Future<void> logout() async {
    await ApiClient.post(
      '/users/logout',
      {},
      auth: true,
    );
  }

  // =========================================================
  // VERIFY EMERGENCY PIN
  // =========================================================
  //
  // Used by Emergency Assistant.
  //
  // The PIN is verified by the backend against the bcrypt
  // hash stored in MongoDB.
  //
  // The PIN is NOT stored in plain text in Flutter.
  // =========================================================

  static Future<bool> verifyEmergencyPin(
    String pin,
  ) async {
    final enteredPin = pin.trim();

    if (!RegExp(r'^\d{4}$').hasMatch(enteredPin)) {
      throw ApiException(
        400,
        'Emergency PIN must be exactly 4 digits.',
      );
    }

    final data = await ApiClient.post(
      '/users/verify-emergency-pin',
      {
        'pin': enteredPin,
      },
      auth: true,
    );

    return data['verified'] == true;
  }
// =========================================================
// CREATE EMERGENCY PIN
// =========================================================
//
// Used ONLY when an existing account does not have
// an Emergency PIN yet.
//
// This is different from changeEmergencyPin():
//
// CREATE:
//     New PIN
//     Confirm PIN
//
// CHANGE:
//     Current PIN
//     New PIN
//     Confirm PIN
// =========================================================

  static Future<void> createEmergencyPin({
    required String newPin,
    required String confirmPin,
  }) async {
    final pin = newPin.trim();
    final confirmation = confirmPin.trim();

    // ---------------------------------------------------------
    // Validate PIN
    // ---------------------------------------------------------

    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw ApiException(
        400,
        'Emergency PIN must be exactly 4 digits.',
      );
    }

    if (!RegExp(r'^\d{4}$').hasMatch(confirmation)) {
      throw ApiException(
        400,
        'Confirm Emergency PIN must be exactly 4 digits.',
      );
    }

    if (pin != confirmation) {
      throw ApiException(
        400,
        'Emergency PINs do not match.',
      );
    }

    // ---------------------------------------------------------
    // Create PIN in backend
    // ---------------------------------------------------------

    final data = await ApiClient.post(
      '/users/create-emergency-pin',
      {
        'newPin': pin,
        'confirmPin': confirmation,
      },
      auth: true,
    );

    // ---------------------------------------------------------
    // Update local session
    // ---------------------------------------------------------

    AppSession.instance.hasEmergencyPin = data['hasEmergencyPin'] == true;

    // In case backend does not return the field for some reason,
    // a successful request itself means the PIN now exists.
    if (data['hasEmergencyPin'] == null) {
      AppSession.instance.hasEmergencyPin = true;
    }

    AppSession.instance.notifyListeners();
  }

  // =========================================================
// CHANGE EMERGENCY PIN
// =========================================================
//
// Used from Profile / Settings.
//
// The user enters:
//   1. Current PIN
//   2. New PIN
//   3. Confirm New PIN
//
// The backend verifies the current PIN and securely hashes
// the new PIN with bcrypt.
// =========================================================

  static Future<void> changeEmergencyPin({
    required String currentPin,
    required String newPin,
    required String confirmPin,
  }) async {
    final oldPin = currentPin.trim();
    final pin = newPin.trim();
    final confirmation = confirmPin.trim();

    // ---------------------------------------------------------
    // Validate all PINs
    // ---------------------------------------------------------

    if (!RegExp(r'^\d{4}$').hasMatch(oldPin)) {
      throw ApiException(
        400,
        'Current Emergency PIN must be exactly 4 digits.',
      );
    }

    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw ApiException(
        400,
        'New Emergency PIN must be exactly 4 digits.',
      );
    }

    if (!RegExp(r'^\d{4}$').hasMatch(confirmation)) {
      throw ApiException(
        400,
        'Confirmation PIN must be exactly 4 digits.',
      );
    }

    if (pin != confirmation) {
      throw ApiException(
        400,
        'Emergency PINs do not match.',
      );
    }

    if (oldPin == pin) {
      throw ApiException(
        400,
        'New Emergency PIN must be different from your current PIN.',
      );
    }

    // ---------------------------------------------------------
    // Change PIN in backend
    // ---------------------------------------------------------

    await ApiClient.put(
      '/users/change-emergency-pin',
      {
        'currentPin': oldPin,
        'newPin': pin,
        'confirmPin': confirmation,
      },
    );
  }

  // =========================================================
  // RESPONDER STATUS
  // =========================================================

  static VerificationStatus _parseResponderStatus(
    dynamic value,
  ) {
    switch (value?.toString()) {
      case 'approved':
        return VerificationStatus.verified;

      case 'rejected':
        return VerificationStatus.rejected;

      case 'pending':
      default:
        return VerificationStatus.pending;
    }
  }
}
