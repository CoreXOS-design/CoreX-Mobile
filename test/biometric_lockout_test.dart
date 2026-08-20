import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corex_mobile/services/security_service.dart';

/// Guards the fingerprint lockout: users reported the "Fingerprint sign-in"
/// toggle reading ON while the app never raised a prompt, stranding them at a
/// password form for a password they didn't know (nothing stores it by design).
///
/// The cause was two stores with different lifetimes. The opt-in flag sat in
/// plaintext SharedPreferences, which survives a reinstall, a cloud restore and
/// a device transfer; the auth token it claimed to unlock sat in a vault
/// encrypted under a non-exportable Android Keystore key, which does not. Every
/// path that lost one but not the other produced a dead toggle.
///
/// These tests pin the reconciliation. The vault is faked at the method-channel
/// level so the flags' *storage* is exercised, not mocked away.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Map<String, String> vault;

  setUp(() {
    vault = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map).cast<String, dynamic>();
      final key = args['key'] as String?;
      switch (call.method) {
        case 'write':
          vault[key!] = args['value'] as String;
          return null;
        case 'read':
          return vault[key];
        case 'delete':
          vault.remove(key);
          return null;
        case 'readAll':
          return vault;
        case 'containsKey':
          return vault.containsKey(key);
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  final security = SecurityService.instance;

  group('the opt-in flag lives with the token, not beside it', () {
    test('enabling writes to the vault and reads back', () async {
      SharedPreferences.setMockInitialValues({});
      await security.setBiometricEnabled(true);

      expect(vault['sec_biometric_enabled'], 'true',
          reason: 'the flag must land in the same vault as the auth token, '
              'so a device that loses the token loses the claim too');
      expect(await security.isBiometricEnabled(), isTrue);
    });

    test('disabling sticks', () async {
      SharedPreferences.setMockInitialValues({});
      await security.setBiometricEnabled(true);
      await security.setBiometricEnabled(false);

      expect(await security.isBiometricEnabled(), isFalse);
    });

    test('an unreadable vault answers "not enabled", never "enabled"', () async {
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'keystore-gone');
      });

      // Failing this direction re-offers setup, which is recoverable. Failing
      // the other way claims an unlock the app cannot perform — the lockout.
      expect(await security.isBiometricEnabled(), isFalse);
      expect(await security.hasPromptedBiometric(), isFalse);
    });
  });

  group('legacy plaintext flags migrate only when a token survived', () {
    test('a live install carries its opt-in forward', () async {
      SharedPreferences.setMockInitialValues({
        'sec_biometric_enabled': true,
        'sec_biometric_prompted': true,
      });

      await security.migrateLegacyBiometricFlags(hasToken: true);

      expect(await security.isBiometricEnabled(), isTrue,
          reason: 'upgrading must not silently switch fingerprint sign-in off');
      expect(await security.hasPromptedBiometric(), isTrue);
    });

    test('a restore with no token does NOT resurrect the opt-in', () async {
      // The reported bug, exactly: Android Auto Backup restored the plaintext
      // `true` onto a device whose keystore-bound token could never come back.
      SharedPreferences.setMockInitialValues({
        'sec_biometric_enabled': true,
        'sec_biometric_prompted': true,
      });

      await security.migrateLegacyBiometricFlags(hasToken: false);

      expect(await security.isBiometricEnabled(), isFalse,
          reason: 'an opt-in with no token to unlock is a toggle that can '
              'never raise a prompt');
      expect(await security.hasPromptedBiometric(), isFalse,
          reason: 'the setup offer must come back, or the user has no way to '
              'switch fingerprint sign-in on again');
    });

    test('the legacy keys are consumed, so a later restore cannot re-apply them',
        () async {
      SharedPreferences.setMockInitialValues({'sec_biometric_enabled': true});

      await security.migrateLegacyBiometricFlags(hasToken: false);
      // Second run: even claiming a token now must not revive the dropped flag.
      await security.migrateLegacyBiometricFlags(hasToken: true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('sec_biometric_enabled'), isFalse);
      expect(await security.isBiometricEnabled(), isFalse);
    });

    test('a clean install is left alone', () async {
      SharedPreferences.setMockInitialValues({});

      await security.migrateLegacyBiometricFlags(hasToken: true);

      expect(await security.isBiometricEnabled(), isFalse);
      expect(await security.hasPromptedBiometric(), isFalse);
    });
  });

  group('logout re-arms the one-time setup offer', () {
    // Without this, the "already prompted" mark outlived the opt-in that
    // logout switched off: the next sign-in never offered biometrics again and
    // the feature quietly ceased to exist for that user.
    test('clearBiometricPrompted lets the next sign-in offer again', () async {
      SharedPreferences.setMockInitialValues({});
      await security.markBiometricPrompted();
      expect(await security.hasPromptedBiometric(), isTrue);

      await security.clearBiometricPrompted();

      expect(await security.hasPromptedBiometric(), isFalse);
    });
  });
}
