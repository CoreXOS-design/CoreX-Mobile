import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/messaging_service.dart';
import '../services/security_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  final MessagingService _messaging = MessagingService.instance;
  final SecurityService _security = SecurityService.instance;

  AuthProvider() {
    // React to any authenticated request 401'ing mid-session: the token is
    // already cleared by [ApiService]; here we drop the in-memory session so
    // the auth gate routes back to login instead of stranding the user on a
    // screen whose data silently fails to load.
    ApiService.sessionExpired.addListener(_onSessionExpired);
  }

  /// Fired when [ApiService] observes a 401. Ignored unless we currently
  /// believe we're authenticated — this skips 401s from the login call itself
  /// and avoids redundant work once already logged out. Credentials and
  /// biometric setup are intentionally left intact so the login screen can
  /// prefill / biometric-unlock straight back in.
  void _onSessionExpired() {
    if (!_isLoggedIn && !_isLocked) return;
    _isLoggedIn = false;
    _isLocked = false;
    _user = null;
    notifyListeners();
  }

  bool _isLoading = false;
  bool _isLoggedIn = false;
  bool _isLocked = false;
  bool _isChecking = true;
  bool _biometricEnabled = false;
  bool _needsBiometricSetupPrompt = false;
  String? _error;
  int? _lastLoginStatus;
  Map<String, dynamic>? _user;

  /// HTTP status of the most recent [login] attempt, or null on network error.
  /// 200 = success, 401/422 = bad credentials for an existing user.
  int? get lastLoginStatus => _lastLoginStatus;

  bool get isLoading => _isLoading;
  /// True only when fully authenticated AND not locked. AuthGate uses this
  /// to gate the home shell.
  bool get isLoggedIn => _isLoggedIn && !_isLocked;
  bool get isLocked => _isLocked;
  bool get isChecking => _isChecking;
  bool get biometricEnabled => _biometricEnabled;
  bool get needsBiometricSetupPrompt => _needsBiometricSetupPrompt;
  String? get error => _error;
  Map<String, dynamic>? get user => _user;
  String get userName => _user?['name'] ?? 'Agent';

  /// The logged-in user's id, used to tell their own listings from ones they
  /// only co-list. Walks the flat (`id`) and nested (`user.id`) shapes the
  /// profile / logged-user payloads use. Null when unavailable.
  int? get currentUserId {
    final flat = (_user?['id'] as num?)?.toInt();
    if (flat != null) return flat;
    final nested = _user?['user'];
    if (nested is Map) return (nested['id'] as num?)?.toInt();
    return null;
  }

  Future<void> checkAuth() async {
    _biometricEnabled = await _security.isBiometricEnabled();
    final token = await _api.getToken();
    if (token != null) {
      try {
        _user = await _api.getProfile().timeout(const Duration(seconds: 8));
        _isLoggedIn = true;
        _isLocked = _biometricEnabled;
        unawaited(_messaging.onLogin());
      } on TimeoutException {
        _isLoggedIn = false;
        _user = null;
      } catch (_) {
        await _api.clearToken();
        _isLoggedIn = false;
        _user = null;
      }
    }
    _isChecking = false;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    _lastLoginStatus = null;
    notifyListeners();

    try {
      final result = await _api.login(email, password);
      _lastLoginStatus = 200;
      await _api.saveToken(result['token']);
      _user = result['user'];
      _isLoggedIn = true;
      _isLocked = false;
      _isLoading = false;

      // Always remember the most recent credentials in the secure vault so
      // we can prefill the form (non-biometric users) or unlock on biometric
      // success without hitting the network again.
      await _security.saveCredentials(email, password);

      // First successful login on this device → ask whether to enable
      // biometrics. UI consumes [needsBiometricSetupPrompt] once and clears
      // it via [consumeBiometricSetupPrompt].
      if (!await _security.hasPromptedBiometric()) {
        if (await _security.canUseBiometrics()) {
          _needsBiometricSetupPrompt = true;
        } else {
          await _security.markBiometricPrompted();
        }
      }

      notifyListeners();
      unawaited(_messaging.onLogin());
      return true;
    } catch (e) {
      _lastLoginStatus = e is ApiException ? e.statusCode : null;
      _error = 'Invalid email or password';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Demo Mode sign-in. Backend picks a random user for the given role and
  /// returns a normal Sanctum token, so the rest of the app sees an ordinary
  /// authenticated session. Does NOT save credentials or prompt for biometrics.
  Future<bool> loginAsDemo(String role) async {
    _error = null;
    try {
      final result = await _api.demoLogin(role);
      await _api.saveToken(result['token']);
      _user = result['user'];
      _isLoggedIn = true;
      _isLocked = false;
      notifyListeners();
      unawaited(_messaging.onLogin());
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    } catch (_) {
      _error = 'Could not start demo session';
      notifyListeners();
      return false;
    }
  }

  /// Returns saved (email, password) so the LoginScreen can prefill the
  /// fields. Empty strings if nothing was saved.
  Future<({String email, String password})> readSavedCredentials() async {
    final c = await _security.readCredentials();
    return (email: c.email ?? '', password: c.password ?? '');
  }

  /// Inactivity / app-resume gate: keeps the token but bumps the user back
  /// to the login screen. Unlock via [unlockWithBiometrics] or [login].
  void lockSession() {
    if (!_isLoggedIn || _isLocked) return;
    _isLocked = true;
    notifyListeners();
  }

  Future<bool> unlockWithBiometrics() async {
    if (!_biometricEnabled) return false;
    final ok = await _security.authenticate(reason: 'Unlock CoreX');
    if (ok) {
      _isLocked = false;
      notifyListeners();
    }
    return ok;
  }

  Future<void> consumeBiometricSetupPrompt({required bool enable}) async {
    _needsBiometricSetupPrompt = false;
    await _security.markBiometricPrompted();
    if (enable) {
      final ok = await _security.authenticate(
        reason: 'Confirm biometrics to enable quick sign-in',
      );
      if (ok) {
        _biometricEnabled = true;
        await _security.setBiometricEnabled(true);
      }
    }
    notifyListeners();
  }

  Future<void> setBiometricEnabled(bool enable) async {
    if (enable) {
      if (!await _security.canUseBiometrics()) return;
      final ok = await _security.authenticate(
        reason: 'Confirm biometrics to enable quick sign-in',
      );
      if (!ok) return;
    }
    _biometricEnabled = enable;
    await _security.setBiometricEnabled(enable);
    notifyListeners();
  }

  Future<void> logout() async {
    await _messaging.onLogout();
    await _api.clearToken();
    await _security.setBiometricEnabled(false);
    // Wipe the saved email/password so the next user's login screen doesn't
    // prefill (and biometric unlock can't reuse) the previous user's creds.
    await _security.clearCredentials();
    _biometricEnabled = false;
    _isLoggedIn = false;
    _isLocked = false;
    _user = null;
    notifyListeners();
  }

  @override
  void dispose() {
    ApiService.sessionExpired.removeListener(_onSessionExpired);
    super.dispose();
  }
}
