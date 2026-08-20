import 'package:flutter_test/flutter_test.dart';

import 'package:corex_mobile/main.dart' show kFirstFrameMarker;
import 'package:corex_mobile/providers/auth_provider.dart';
import 'package:corex_mobile/services/messaging_service.dart';

/// Guards the cold-start path that got 1.0.9(15) rejected under Guideline
/// 2.1(a) ("crashed on launch").
///
/// Nothing here needs a platform channel on purpose — these are exactly the
/// failures that happen *before* any plugin is reachable, which is why they
/// present as a launch crash rather than a caught error.
void main() {
  group('cold start survives an uninitialised Firebase', () {
    // `main` wraps `Firebase.initializeApp()` in a try/catch, but that was a
    // false comfort while `MessagingService` resolved
    // `FirebaseMessaging.instance` in a field initialiser:
    // `FirebaseMessaging.instance` calls `Firebase.app()`, which throws when no
    // default app exists. `AuthProvider` holds a `MessagingService`, so a
    // caught init failure still took down the first widget build one frame
    // later. Both constructors must stay inert.
    //
    // No `Firebase.initializeApp()` runs in this file — that is the point.

    test('MessagingService.instance constructs without a Firebase app', () {
      expect(() => MessagingService.instance, returnsNormally);
    });

    test('AuthProvider constructs without a Firebase app', () {
      // AuthProvider holds MessagingService as a field, so this fails for the
      // same reason if the lazy `_fcm` getter is ever turned back into a field.
      late AuthProvider provider;
      expect(() => provider = AuthProvider(), returnsNormally);
      provider.dispose();
    });
  });

  test('first-frame marker matches the string codemagic.yaml greps for', () {
    // The simulator launch smoke test asserts on this literal. If it drifts,
    // the gate silently stops proving that a frame rendered and starts only
    // proving the process is alive — which is true even for a black screen.
    expect(kFirstFrameMarker, 'COREX_FIRST_FRAME_OK');
  });
}
