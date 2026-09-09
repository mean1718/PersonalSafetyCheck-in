import 'api_client.dart';
import 'app_session.dart';
import '../models/user_role.dart';

/// Wires SignUp/Login to the real backend:
///   POST /api/users/register
///   POST /api/users/login
///
/// The backend's User model only knows "user" or "emergency" as a role and
/// has no responder-verification concept at all, so which UserRole the
/// person is signing in/up as stays a client-side choice (it decides which
/// home screen they land on) — it isn't sent to or read from the backend.
class AuthService {
  /// Registers a new account, then logs in immediately — the register
  /// endpoint only confirms the account was created, it doesn't return a
  /// token, so a real session needs the follow-up login call.
  static Future<void> register({
    required String fullName,
    required String email,
    required String password,
    required String phone,
    required UserRole role,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    await ApiClient.post(
      '/users/register',
      {
        'name': fullName,
        'email': normalizedEmail,
        'password': password,
        'phone': phone,
      },
      auth: false,
    );
    await login(email: normalizedEmail, password: password, role: role);
  }

  static Future<void> login({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final data = await ApiClient.post(
      '/users/login',
      {'email': normalizedEmail, 'password': password},
      auth: false,
    );
    final user = data['user'] as Map<String, dynamic>? ?? {};

    AppSession.instance.authToken = data['token'] as String?;
    AppSession.instance.backendUserId = user['_id']?.toString();

    AppSession.instance.signIn(
      fullName: (user['name'] as String?) ?? normalizedEmail.split('@').first,
      email: (user['email'] as String?) ?? normalizedEmail,
      phone: (user['phone'] as String?) ?? '',
      role: role,
    );
  }
}
