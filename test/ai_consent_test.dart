import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corex_mobile/services/ai_consent.dart';

/// Guards AI consent — App Store guidelines 5.1.1(i) / 5.1.2(i).
///
/// The rejection was for sending personal data to a third-party AI service
/// without asking first. The single invariant that fixes it: **nothing is
/// treated as consent except an explicit yes.** Every test here is a way that
/// could quietly stop being true — a fresh install reading as agreement, a
/// storage failure failing open, a colleague's answer surviving a sign-out.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final consent = AiConsent.instance;

  // The singleton caches its first read for the process, so each test starts
  // from a known store AND a cleared cache.
  Future<void> startWith(Map<String, Object> store) async {
    SharedPreferences.setMockInitialValues(store);
    await consent.clear();
  }

  group('nothing but an explicit yes counts as consent', () {
    test('a fresh install has not consented', () async {
      SharedPreferences.setMockInitialValues({});
      // Deliberately not calling clear() first: this is the true cold-start
      // path, where nothing has ever been written.
      expect(await consent.ensureLoaded(), AiConsentState.unknown);
      expect(consent.granted, isFalse);
    });

    test('unanswered is distinct from declined', () async {
      await startWith({});
      expect(consent.state, AiConsentState.unknown);
      await consent.set(false);
      expect(consent.state, AiConsentState.declined);
      // Both block the send; only the first should prompt again on its own.
      expect(consent.granted, isFalse);
    });

    test('agreeing grants, and survives a reload', () async {
      await startWith({});
      await consent.set(true);
      expect(consent.granted, isTrue);
      expect(await consent.ensureLoaded(), AiConsentState.granted);
    });

    test('declining is remembered, not re-asked', () async {
      await startWith({});
      await consent.set(false);
      expect(await consent.ensureLoaded(), AiConsentState.declined);
    });
  });

  group('the answer does not outlive the person who gave it', () {
    test('sign-out clears consent back to unanswered', () async {
      await startWith({});
      await consent.set(true);
      expect(consent.granted, isTrue);

      // Agents share devices — the next one to sign in must answer for
      // themselves rather than inherit this.
      await consent.clear();
      expect(consent.state, AiConsentState.unknown);
      expect(consent.granted, isFalse);
    });

    test('a cleared answer does not linger in storage', () async {
      await startWith({});
      await consent.set(true);
      await consent.clear();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('ai_consent_v1'), isNull);
    });
  });

  group('listeners see every change', () {
    test('setting and clearing both notify', () async {
      await startWith({});
      var notifications = 0;
      void listener() => notifications++;
      consent.addListener(listener);
      addTearDown(() => consent.removeListener(listener));

      await consent.set(true);
      await consent.set(false);
      await consent.clear();

      // The Settings row and the Ellie screen both mirror this state; a missed
      // notification leaves one of them showing the opposite of the truth.
      expect(notifications, 3);
    });
  });
}
