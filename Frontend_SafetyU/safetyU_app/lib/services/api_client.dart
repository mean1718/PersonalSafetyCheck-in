import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'app_session.dart';

/// Thrown when the backend answered but with a non-2xx status. Carries the
/// backend's own `message` field when it sent one — every controller in
/// backend_SafetyU responds with `{ "message": "..." }` on error, so this
/// is usually something worth showing the person directly (e.g. "Invalid
/// email or password").
class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}

/// Thrown when the request never reached the server at all — wrong
/// ApiConfig.baseUrl, backend not running, no network, timed out, etc.
/// Kept separate from [ApiException] so callers (and the person) can tell
/// "the server said no" apart from "couldn't even reach the server".
class ApiConnectionException implements Exception {
  final String message;
  ApiConnectionException(this.message);
  @override
  String toString() => message;
}

/// Thin JSON/HTTP wrapper shared by every service in this folder. Adds the
/// signed-in person's JWT automatically once AppSession.instance.authToken
/// is set (AuthService.login sets it after a successful login).
class ApiClient {
  // Render's free tier puts the backend to sleep after ~15 min idle and
  // a cold start can take 30-60+ seconds. 12s was timing out before the
  // server had even finished waking up, so allow a full minute.
  static const Duration _timeout = Duration(seconds: 60);

  /// Pings /health to wake a sleeping backend. Fire-and-forget: call it
  /// early (app start, signup screens) so by the time the person taps
  /// "Create Account" the server is already awake. Never throws.
  static Future<void> wakeUp() async {
    try {
      await http.get(_uri('/health')).timeout(const Duration(seconds: 90));
    } catch (_) {
      // Ignore - this is only a warm-up.
    }
  }

  static Map<String, String> _headers({bool auth = true}) {
    final headers = {'Content-Type': 'application/json'};
    final token = AppSession.instance.authToken;
    if (auth && token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  static Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> body = {};
    if (res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {
        // Non-JSON body (e.g. an HTML error page because baseUrl is
        // wrong) — fall through and let the status code drive the error.
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body;
    }
    throw ApiException(
      res.statusCode,
      (body['message'] as String?) ?? 'Server error (${res.statusCode})',
    );
  }

  static Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request,
  ) async {
    try {
      final res = await request().timeout(_timeout);
      return _decode(res);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiConnectionException(
        'The server is taking longer than usual to wake up. '
        'Please wait a few seconds and tap the button again.',
      );
    } catch (e) {
      throw ApiConnectionException(
        'Could not reach the SafetyU server at ${ApiConfig.baseUrl}. '
        'Check that the backend is running and ApiConfig.baseUrl is '
        'correct for how you\'re testing. ($e)',
      );
    }
  }

  static Future<Map<String, dynamic>> get(String path, {bool auth = true}) =>
      _send(
        () => http.get(_uri(path), headers: _headers(auth: auth)),
      );

  static Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) =>
      _send(
        () => http.post(_uri(path),
            headers: _headers(auth: auth), body: jsonEncode(body)),
      );

  static Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body,
  ) =>
      _send(
        () => http.put(_uri(path), headers: _headers(), body: jsonEncode(body)),
      );

  static Future<Map<String, dynamic>> delete(String path) => _send(
        () => http.delete(_uri(path), headers: _headers()),
      );
}
