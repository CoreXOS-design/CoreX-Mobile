import 'package:flutter_test/flutter_test.dart';

import 'package:corex_mobile/services/upload_progress.dart';

/// What the upload bar promises the agent.
///
/// An agent shot 18 photos, closed the app with 12 pending, and never saw a
/// count — it lived on the gallery, and he went camera → close. These pin the
/// arithmetic the bar shows once it follows him, in particular that a batch
/// total holds while the queue drains: without it "7 of 18" would count down
/// against itself and read as though photos were being lost.
void main() {
  UploadProgressSnapshot snap({
    int total = 0,
    int remaining = 0,
    int failed = 0,
    bool inFlight = false,
    bool offline = false,
    bool justFinished = false,
  }) =>
      UploadProgressSnapshot(
        total: total,
        remaining: remaining,
        failed: failed,
        inFlight: inFlight,
        offline: offline,
        justFinished: justFinished,
      );

  group('batch arithmetic', () {
    test('done counts against the batch total, not what is left', () {
      // 18 shot, 11 landed, 7 to go.
      final s = snap(total: 18, remaining: 7, inFlight: true);
      expect(s.done, 11);
      expect(s.fraction, closeTo(11 / 18, 0.001));
    });

    test('a fresh batch reads as no progress, not as finished', () {
      final s = snap(total: 18, remaining: 18);
      expect(s.done, 0);
      expect(s.fraction, 0.0);
      expect(s.isPending, isTrue);
    });

    test('no batch means no progress bar rather than a divide by zero', () {
      expect(snap().fraction, isNull);
    });
  });

  group('what the bar shows at all', () {
    test('pending work is visible and prompts before leaving', () {
      final s = snap(total: 18, remaining: 12);
      expect(s.isVisible, isTrue);
      expect(s.isPending, isTrue);
    });

    test('an empty queue shows nothing', () {
      expect(snap().isVisible, isFalse);
      expect(snap().isPending, isFalse);
    });

    test('the finished moment is visible but is not pending work', () {
      // "All 18 photos uploaded" — the moment that tells the agent it is safe
      // to walk away. It must not also trigger the leave prompt.
      final s = snap(total: 18, justFinished: true);
      expect(s.isVisible, isTrue);
      expect(s.isPending, isFalse);
    });

    test('parked failures are visible but never counted as pending', () {
      // They will not finish on their own, so "keep the app open" and "will
      // continue next time" would both be lies about them.
      final s = snap(failed: 3);
      expect(s.isVisible, isTrue);
      expect(s.isPending, isFalse);
    });

    test('failures alongside pending work do not inflate the count', () {
      final s = snap(total: 18, remaining: 5, failed: 2);
      expect(s.remaining, 5);
      expect(s.done, 13);
      expect(s.isPending, isTrue);
    });
  });

  group('snapshot equality', () {
    test('identical states compare equal, so the 20s tick is not a rebuild',
        () {
      expect(snap(total: 18, remaining: 7, inFlight: true),
          snap(total: 18, remaining: 7, inFlight: true));
    });

    test('a photo landing is a change', () {
      expect(snap(total: 18, remaining: 7),
          isNot(snap(total: 18, remaining: 6)));
    });

    test('going offline is a change even with the same counts', () {
      expect(snap(total: 18, remaining: 7),
          isNot(snap(total: 18, remaining: 7, offline: true)));
    });
  });
}
