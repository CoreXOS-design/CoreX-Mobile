import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owns biometric capability checks, the secure-credential vault, and the
/// on-device prefs for "biometric enabled" / "first-login prompt shown".
class SecurityService {
  SecurityService._();
  static final SecurityService instance = SecurityService._();

  final LocalAuthentication _auth = LocalAuthentication();

  /// True while a system biometric/credential prompt is on screen. The
  /// inactivity gate consults this to avoid re-locking the session in
  /// response to the lifecycle transitions the prompt itself triggers.
  static bool isAuthenticating = false;

  /// Monotonic id for each [authenticate] call. The delayed reset of
  /// [isAuthenticating] only fires for the *latest* call, so a second prompt
  /// starting before the first's tail delay elapses can't clear the flag out
  /// from under it.
  static int _authGeneration = 0;
  final FlutterSecureStorage _vault = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _kEmail = 'sec_email';
  static const _kPassword = 'sec_password';
  static const _kBiometricEnabled = 'sec_biometric_enabled';
  static const _kBiometricPrompted = 'sec_biometric_prompted';

  Future<bool> canUseBiometrics() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      if (!supported || !canCheck) return false;
      final available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> authenticate({String reason = 'Sign in to CoreX'}) async {
    isAuthenticating = true;
    final generation = ++_authGeneration;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'CoreX sign-in',
            cancelButton: 'Use password',
          ),
          IOSAuthMessages(cancelButton: 'Use password'),
        ],
      );
    } on PlatformException catch (e) {
      // Swallowed so the caller can fall back to the password, but logged:
      // a prompt that silently never appears (no enrolment, activity not
      // resumed yet, plugin busy) is otherwise invisible on a real device.
      debugPrint('[biometrics] authenticate failed: ${e.code} ${e.message}');
      return false;
    } finally {
      // Keep the suppression alive briefly past the prompt dismissal so the
      // tail of lifecycle events (resumed/inactive flicker on some OEMs)
      // doesn't trip the inactivity lock.
      Future.delayed(const Duration(milliseconds: 800), () {
        // Only the most recent authenticate() may clear the flag; a newer
        // prompt that started in the meantime keeps the suppression alive
        // until its own delayed reset runs.
        if (generation == _authGeneration) {
          isAuthenticating = false;
        }
      });
    }
  }

  /// Remembers the email only. The password is deliberately never persisted:
  /// biometric unlock re-uses the existing session token, so nothing needs a
  /// stored password, and a vault that holds one is a vault worth attacking.
  /// The legacy password key is deleted on every save so installs that
  /// predate this behaviour get scrubbed on their next sign-in.
  Future<void> saveEmail(String email) async {
    await _vault.write(key: _kEmail, value: email);
    await _vault.delete(key: _kPassword);
  }

  Future<String?> readEmail() => _vault.read(key: _kEmail);

  Future<void> clearCredentials() async {
    await _vault.delete(key: _kEmail);
    await _vault.delete(key: _kPassword);
  }

  Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kBiometricEnabled) ?? false;
  }

  Future<void> setBiometricEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBiometricEnabled, value);
  }

  Future<bool> hasPromptedBiometric() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kBiometricPrompted) ?? false;
  }

  Future<void> markBiometricPrompted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBiometricPrompted, true);
  }
}
