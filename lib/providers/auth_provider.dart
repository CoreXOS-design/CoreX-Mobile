import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/messaging_service.dart';
import '../services/security_service.dart';

/// Outcome of a biometric unlock attempt. The caller shows different copy for
/// "you cancelled", "your session is gone" and "we couldn't reach the server",
/// which a bool can't carry.
enum BiometricUnlock {
  success,
  cancelled,

  /// The server rejected the token (401/403). A password sign-in is the only
  /// way back in.
  sessionExpired,

  /// The fingerprint was accepted but the profile call didn't come back. The
  /// token is untouched and still good — retrying is worthwhile, and telling
  /// the user their session expired would be a lie that sends them hunting for
  /// a password they may not know.
  unreachable,

  unavailable,
}

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
    // The token is gone, so biometrics have nothing left to unlock — only a
    // fresh password sign-in can restore a session from here.
    _hasStoredToken = false;
    _user = null;
    notifyListeners();
  }

  bool _isLoading = false;
  bool _isLoggedIn = false;
  bool _isLocked = false;
  bool _isChecking = true;
  bool _biometricEnabled = false;
  bool _hasStoredToken = false;
  bool _needsBiometricSetupPrompt = false;
  String? _error;
  int? _lastLoginStatus;
  String? _lastLoginCode;
  Map<String, dynamic>? _user;

  /// HTTP status of the most recent [login] attempt, or null on network error.
  /// 200 = success, 401/422 = bad credentials for an existing user,
  /// 403 = the password was right but app access has been deleted.
  int? get lastLoginStatus => _lastLoginStatus;

  /// Server-supplied reason for the most recent failed [login] —
  /// `invalid_password`, `user_not_found` or `account_deleted` — or null when
  /// the server sent no code (or the call never reached it).
  String? get lastLoginCode => _lastLoginCode;

  /// True when the last sign-in failed because this account's app access has
  /// been deleted. The password was correct; no token was issued.
  bool get lastLoginWasDeletedAccount =>
      _lastLoginCode == 'account_deleted' || _lastLoginStatus == 403;

  /// True when the session ended because app access was deleted — either on
  /// this device or another one. Survives the bounce back to the login screen
  /// so it can say *why* the user is looking at a password form again.
  bool get accountWasDeleted => ApiService.accountDeleted;

  bool get isLoading => _isLoading;
  /// True only when fully authenticated AND not locked. AuthGate uses this
  /// to gate the home shell.
  bool get isLoggedIn => _isLoggedIn && !_isLocked;
  bool get isLocked => _isLocked;
  bool get isChecking => _isChecking;
  bool get biometricEnabled => _biometricEnabled;

  /// True when the biometric prompt can actually get the user in: they opted
  /// in, and this device still holds a token to unlock.
  ///
  /// Deliberately not tied to [isLocked]. A cold start whose profile fetch
  /// timed out leaves us signed-out-but-tokened, and the user would otherwise
  /// be sent to the password form despite having enabled biometrics —
  /// [unlockWithBiometrics] completes the sign-in in that case.
  bool get canUnlockWithBiometrics => _biometricEnabled && _hasStoredToken;

  /// Opted in, but there is no session left on this device to unlock.
  ///
  /// This is the state users got stranded in: the toggle read ON while the
  /// login screen quietly never prompted, and since the password is never
  /// stored there was nothing else to try. The opt-in is deliberately kept —
  /// one password sign-in restores the token and biometrics resume without
  /// re-running setup — but the UI must *say* that rather than show a dead
  /// toggle. See [SecurityService.isBiometricEnabled].
  bool get biometricNeedsPasswordSignIn =>
      _biometricEnabled && !_hasStoredToken;

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
    final token = await _api.getToken();
    _hasStoredToken = token != null;
    // Must run before the flag is read: it decides whether a legacy (or
    // restored) plaintext opt-in is allowed to become the vault-backed one,
    // and that decision depends on whether a token actually survived.
    await _security.migrateLegacyBiometricFlags(hasToken: _hasStoredToken);
    _biometricEnabled = await _security.isBiometricEnabled();
    debugPrint('[auth] cold start: storedToken=$_hasStoredToken '
        'biometricEnabled=$_biometricEnabled');
    if (token != null) {
      try {
        _user = await _api.getProfile().timeout(const Duration(seconds: 8));
        _isLoggedIn = true;
        _isLocked = _biometricEnabled;
        debugPrint('[auth] session restored, locked=$_isLocked');
        unawaited(_messaging.onLogin());
      } on TimeoutException {
        // Token kept: the network was slow, not the session invalid. The
        // login screen can still offer biometrics, which retries the profile.
        debugPrint('[auth] profile fetch timed out — keeping the token');
        _isLoggedIn = false;
        _user = null;
      } catch (e) {
        // Only a genuine auth rejection invalidates the token. Launching with
        // no signal used to wipe it, which quietly signed the user out for
        // good — they'd be back at the password form with nothing to unlock.
        final rejected = e is ApiException &&
            (e.statusCode == 401 || e.statusCode == 403);
        debugPrint('[auth] profile fetch failed ($e) — '
            '${rejected ? 'clearing' : 'keeping'} the token');
        if (rejected) {
          await _api.clearToken();
          _hasStoredToken = false;
        }
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
    _lastLoginCode = null;
    notifyListeners();

    try {
      final result = await _api.login(email, password);
      _lastLoginStatus = 200;
      await _api.saveToken(result['token']);
      _user = result['user'];
      _isLoggedIn = true;
      _isLocked = false;
      _hasStoredToken = true;
      _isLoading = false;

      // Remember the email so the form can prefill it. The password is never
      // stored — after a lock the user either passes the biometric check or
      // types it again.
      await _security.saveEmail(email);

      // First successful login on this device → ask whether to enable
      // biometrics. UI consumes [needsBiometricSetupPrompt] once and clears
      // it via [consumeBiometricSetupPrompt].
      if (!await _security.hasPromptedBiometric()) {
        // Fingerprint-capable devices only — Face ID iPhones are excluded by
        // product decision, see [SecurityService.canUseFingerprint].
        //
        // A "no" here is deliberately NOT marked as prompted. The check answers
        // no whenever nothing is *enrolled* yet, which is the normal state of a
        // brand-new device — marking it would burn the one-time offer before
        // the user ever had a fingerprint to offer, and enrolling one later
        // would never bring it back. Same reasoning as the failed-confirmation
        // path in [consumeBiometricSetupPrompt]. Re-probing on each sign-in is
        // a cheap capability call with no UI.
        if (await _security.canUseFingerprint()) {
          _needsBiometricSetupPrompt = true;
        }
      }

      notifyListeners();
      unawaited(_messaging.onLogin());
      return true;
    } catch (e) {
      _lastLoginStatus = e is ApiException ? e.statusCode : null;
      _lastLoginCode = e is ApiException ? e.code : null;
      // A deleted account is not a credential problem — the password was
      // right. Saying "invalid email or password" would send the user hunting
      // for a typo that doesn't exist. The login screen renders the full
      // explanation; this is the fallback for anything reading [error].
      _error = lastLoginWasDeletedAccount
          ? 'This account has been deleted.'
          : 'Invalid email or password';
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
      _hasStoredToken = true;
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

  /// Last signed-in email, so the login form can prefill it. Empty when
  /// nothing was saved. Passwords are never stored, so there is nothing else
  /// to hand back.
  Future<String> readSavedEmail() async => await _security.readEmail() ?? '';

  /// Inactivity / app-resume gate: keeps the token but bumps the user back
  /// to the login screen. Unlock via [unlockWithBiometrics] or [login].
  void lockSession() {
    if (!_isLoggedIn || _isLocked) return;
    _isLocked = true;
    notifyListeners();
  }

  /// Runs the system prompt and, on success, restores the session.
  ///
  /// Two shapes of "signed out" reach here: a locked-but-live session (the
  /// normal cold start), and a session whose profile fetch failed at launch
  /// while the token survived. The second one needs the profile fetched now,
  /// or passing the biometric check would leave the user staring at the login
  /// form they just authenticated past.
  Future<BiometricUnlock> unlockWithBiometrics() async {
    if (!canUnlockWithBiometrics) return BiometricUnlock.unavailable;
    final ok = await _security.authenticate(reason: 'Unlock CoreX');
    if (!ok) return BiometricUnlock.cancelled;

    if (_isLoggedIn || _isLocked) {
      _isLocked = false;
      _isLoggedIn = true;
      notifyListeners();
      return BiometricUnlock.success;
    }

    try {
      _user = await _api.getProfile().timeout(const Duration(seconds: 8));
      _isLoggedIn = true;
      _isLocked = false;
      notifyListeners();
      unawaited(_messaging.onLogin());
      return BiometricUnlock.success;
    } catch (e) {
      // Same rule as [checkAuth]: only a genuine auth rejection invalidates the
      // token. This used to swallow *everything*, so a slow network or a flaky
      // connection retired biometric unlock for the rest of the session — the
      // user had passed the fingerprint check and still landed on a password
      // form, with a token that was in fact perfectly good.
      final rejected =
          e is ApiException && (e.statusCode == 401 || e.statusCode == 403);
      debugPrint('[auth] biometric unlock profile fetch failed ($e) — '
          '${rejected ? 'session is gone' : 'keeping the token'}');
      if (!rejected) return BiometricUnlock.unreachable;
      await _api.clearToken();
      _hasStoredToken = false;
      notifyListeners();
      return BiometricUnlock.sessionExpired;
    }
  }

  /// Returns whether biometric sign-in ended up enabled, so a confirmation
  /// that the user completed but the platform rejected doesn't fail silently —
  /// they'd close the app expecting a fingerprint prompt that never comes.
  Future<bool> consumeBiometricSetupPrompt({required bool enable}) async {
    _needsBiometricSetupPrompt = false;
    if (!enable) {
      // Declining is final — never nag. Settings still has the toggle.
      await _security.markBiometricPrompted();
      notifyListeners();
      return false;
    }

    final ok = await _security.authenticate(
      reason: 'Confirm biometrics to enable quick sign-in',
    );
    if (ok) {
      _biometricEnabled = true;
      await _security.setBiometricEnabled(true);
      await _security.markBiometricPrompted();
    }
    // A failed confirmation is deliberately NOT marked as prompted: the user
    // said yes, so offer it again at the next sign-in rather than silently
    // burning their one chance on a platform hiccup.
    debugPrint('[biometrics] setup confirmed=$ok');
    notifyListeners();
    return ok;
  }

  Future<void> setBiometricEnabled(bool enable) async {
    if (enable) {
      // Only a confirmed "this device doesn't offer it" bails out early. An
      // inconclusive probe falls through to the confirmation prompt, which is
      // the authoritative test anyway — bailing on it made the Settings switch
      // snap back with nothing said, the same silent failure as the vanishing
      // unlock button.
      if (await _security.probeFingerprint() == FingerprintSupport.notOffered) {
        return;
      }
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
    // Signing out disables biometrics, so the one-time setup offer has to be
    // re-armed with it. Without this the "already prompted" mark outlived the
    // opt-in it belonged to: the next sign-in never offered biometrics again,
    // and the feature just quietly stopped existing for that user.
    await _security.clearBiometricPrompted();
    // Wipe the saved email/password so the next user's login screen doesn't
    // prefill (and biometric unlock can't reuse) the previous user's creds.
    await _security.clearCredentials();
    _biometricEnabled = false;
    _hasStoredToken = false;
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
