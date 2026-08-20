import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether this device offers fingerprint sign-in.
enum FingerprintSupport {
  /// Confirmed usable.
  available,

  /// Confirmed *not* offered — no hardware, nothing enrolled, or a Face-ID-only
  /// iPhone, which is excluded by product decision.
  notOffered,

  /// The platform could not answer. Usually transient (activity not resumed,
  /// sensor locked out, plugin busy). Callers offering an *existing* opt-in
  /// should treat this as "show the button and let the real prompt decide",
  /// never as a reason to hide it.
  unknown,
}

/// Owns biometric capability checks, the secure-credential vault, and the
/// "biometric enabled" / "first-login prompt shown" flags.
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

  /// Vault access is time-boxed for the same reason as in [ApiService]: the
  /// `encryptedSharedPreferences` configuration can hang on first read on some
  /// Android builds, and a hung read must cost seconds, not the launch.
  static const Duration _vaultTimeout = Duration(seconds: 3);

  static const _kEmail = 'sec_email';
  static const _kPassword = 'sec_password';
  static const _kBiometricEnabled = 'sec_biometric_enabled';
  static const _kBiometricPrompted = 'sec_biometric_prompted';

  /// Gate for offering quick sign-in. Product decision: fingerprint only —
  /// face recognition is deliberately not offered as a sign-in method.
  ///
  /// Enforceable exactly on iOS, where the platform names the sensor: a Face
  /// ID device reports [BiometricType.face] and gets no offer at all, a Touch
  /// ID device reports [BiometricType.fingerprint] and does.
  ///
  /// Android can't be filtered the same way — its plugin only ever reports
  /// STRONG/WEAK, never which sensor is behind them, and `BiometricPrompt` is
  /// asked for `BIOMETRIC_WEAK | BIOMETRIC_STRONG`. So on a phone with face
  /// unlock enrolled the OS may still choose it. There is no API in
  /// local_auth to demand a specific modality; the alternative would be
  /// dropping biometric sign-in on Android entirely.
  /// Tri-state so callers can tell "this device does not offer fingerprint
  /// sign-in" from "the probe could not answer right now". The second case is
  /// common and transient — the plugin throws or reports nothing while the
  /// activity is still resuming, after a sensor lockout, or on a device that
  /// has only just booted. Collapsing it into `false` used to hide the unlock
  /// button *and* skip auto-unlock for the whole session, with no retry and no
  /// message: the fingerprint option simply vanished.
  Future<FingerprintSupport> probeFingerprint() async {
    try {
      if (!await _auth.isDeviceSupported()) return FingerprintSupport.notOffered;
      if (!await _auth.canCheckBiometrics) return FingerprintSupport.unknown;
      final available = await _auth.getAvailableBiometrics();
      // Empty is not a verdict: the list is reliably empty while the sensor is
      // locked out or the activity has not resumed. Only a positive answer
      // that is face-only counts as "not offered".
      if (available.isEmpty) return FingerprintSupport.unknown;
      // Face-only enrolment (i.e. an iPhone with Face ID) — not offered.
      final faceOnly = available.contains(BiometricType.face) &&
          available.length == 1;
      return faceOnly
          ? FingerprintSupport.notOffered
          : FingerprintSupport.available;
    } on PlatformException catch (e) {
      debugPrint('[biometrics] probe failed: ${e.code} ${e.message}');
      return FingerprintSupport.unknown;
    }
  }

  /// Strict form, for deciding whether to *offer* opting in. An unknown probe
  /// answers no here — enabling a feature we could not confirm is worse than
  /// re-offering it at the next sign-in, which [AuthProvider] already does.
  Future<bool> canUseFingerprint() async =>
      await probeFingerprint() == FingerprintSupport.available;

  Future<bool> authenticate({String reason = 'Sign in to CoreX'}) async {
    isAuthenticating = true;
    final generation = ++_authGeneration;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          // Biometric only: quick sign-in is a fingerprint, not a device PIN.
          // Cancelling drops the user on the password form, which the OS
          // password manager can fill.
          biometricOnly: true,
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

  /// Both biometric flags live in the same vault as the auth token, and for
  /// one reason: **they must die together.**
  ///
  /// They used to sit in plain [SharedPreferences], which survives everything
  /// the keystore-bound token does not — a reinstall, a cloud restore, a
  /// device transfer. That left the exact state users got stuck in: a "biometric
  /// sign-in" toggle reading ON, no prompt at launch because there was no token
  /// left to unlock, and no stored password to fall back on. Sharing the
  /// vault's fate means a device that lost the token also loses the claim that
  /// biometrics were ever set up, so the app asks for a password *and says so*
  /// instead of silently offering nothing.
  ///
  /// `FlutterSecureStorage.xml` is excluded from Android backup for the same
  /// reason — see `android/app/src/main/res/xml/backup_rules.xml`.
  Future<bool> _readFlag(String key) async {
    try {
      final value = await _vault.read(key: key).timeout(_vaultTimeout);
      if (value != null) return value == 'true';
    } catch (e) {
      // A vault that can't be read answers "false" for both flags, which fails
      // in the safe direction: re-offer setup, don't claim an unlock we can't
      // perform.
      debugPrint('[biometrics] flag read failed ($key): $e');
    }
    return false;
  }

  Future<void> _writeFlag(String key, bool value) async {
    try {
      await _vault
          .write(key: key, value: value ? 'true' : 'false')
          .timeout(_vaultTimeout);
    } catch (e) {
      debugPrint('[biometrics] flag write failed ($key): $e');
    }
  }

  Future<bool> isBiometricEnabled() => _readFlag(_kBiometricEnabled);

  Future<void> setBiometricEnabled(bool value) =>
      _writeFlag(_kBiometricEnabled, value);

  Future<bool> hasPromptedBiometric() => _readFlag(_kBiometricPrompted);

  Future<void> markBiometricPrompted() =>
      _writeFlag(_kBiometricPrompted, true);

  /// Clears the one-time setup offer so the next sign-in re-offers biometrics.
  /// Called on logout: signing out disables biometrics, and without this the
  /// "already prompted" mark outlived it, so the offer never came back and the
  /// user had to discover the Settings toggle unaided.
  Future<void> clearBiometricPrompted() async {
    try {
      await _vault.delete(key: _kBiometricPrompted).timeout(_vaultTimeout);
    } catch (e) {
      debugPrint('[biometrics] prompted-flag clear failed: $e');
    }
  }

  /// One-time migration of the legacy plaintext flags out of SharedPreferences.
  ///
  /// [hasToken] is the gate that matters. A restored install brings the old
  /// plaintext `true` back but never the token it referred to, so adopting it
  /// unconditionally would recreate the very lockout this move was meant to
  /// end. The legacy keys are removed either way, so this runs at most once per
  /// install and a restore can never resurrect them a second time.
  Future<void> migrateLegacyBiometricFlags({required bool hasToken}) async {
    final prefs = await SharedPreferences.getInstance();
    final hadEnabled = prefs.containsKey(_kBiometricEnabled);
    final hadPrompted = prefs.containsKey(_kBiometricPrompted);
    if (!hadEnabled && !hadPrompted) return;

    final legacyEnabled = prefs.getBool(_kBiometricEnabled) ?? false;
    final legacyPrompted = prefs.getBool(_kBiometricPrompted) ?? false;
    await prefs.remove(_kBiometricEnabled);
    await prefs.remove(_kBiometricPrompted);

    if (legacyEnabled && hasToken) {
      await setBiometricEnabled(true);
    } else if (legacyEnabled) {
      debugPrint('[biometrics] dropped a legacy opt-in with no token to '
          'unlock — the password sign-in will re-offer it');
    }
    // Only carry "already prompted" forward alongside a live opt-in. Carrying
    // it on its own is how a restore silently suppressed the offer forever.
    if (legacyPrompted && legacyEnabled && hasToken) {
      await markBiometricPrompted();
    }
  }
}
