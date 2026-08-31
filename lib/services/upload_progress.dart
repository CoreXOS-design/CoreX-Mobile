import 'dart:async';

import 'package:flutter/foundation.dart';

import 'upload_queue.dart';
import 'upload_service.dart';

/// What the upload bar should say right now, for one property.
///
/// Every number here is derived from the durable [UploadQueue] and nothing
/// else. That is the point: a count owned by a screen dies with the screen,
/// which is how an agent shot 18 photos, closed the app with 12 pending, and
/// never once saw a number telling him so.
class UploadProgressSnapshot {
  /// Photos in this batch — the high-water mark since the queue for this
  /// property was last empty. The denominator in "7 of 18".
  final int total;

  /// Still to go: pending plus the one on the wire. Excludes parked failures,
  /// which will not finish on their own and must not be counted as though
  /// they will.
  final int remaining;

  /// Parked failures needing an explicit retry.
  final int failed;

  /// A transfer is actually moving right now.
  final bool inFlight;

  /// The server could not be reached on the last attempt.
  final bool offline;

  /// The queue just emptied. Held true briefly so the agent gets the one
  /// thing this whole bar exists to give them: a moment that says it is safe
  /// to walk away.
  final bool justFinished;

  const UploadProgressSnapshot({
    required this.total,
    required this.remaining,
    required this.failed,
    required this.inFlight,
    required this.offline,
    required this.justFinished,
  });

  static const empty = UploadProgressSnapshot(
    total: 0,
    remaining: 0,
    failed: 0,
    inFlight: false,
    offline: false,
    justFinished: false,
  );

  int get done => total - remaining;

  /// Work is outstanding that will complete on its own. Drives both the
  /// warning line and the leave prompt.
  bool get isPending => remaining > 0;

  /// Anything at all to show.
  bool get isVisible => remaining > 0 || failed > 0 || justFinished;

  /// 0..1 across the batch, or null when there is no batch to measure.
  double? get fraction {
    if (total <= 0) return null;
    return (done / total).clamp(0.0, 1.0);
  }

  // Value equality so the 20s upload tick, which fires whether or not anything
  // changed, does not rebuild every watching screen for an identical bar.
  @override
  bool operator ==(Object other) =>
      other is UploadProgressSnapshot &&
      other.total == total &&
      other.remaining == remaining &&
      other.failed == failed &&
      other.inFlight == inFlight &&
      other.offline == offline &&
      other.justFinished == justFinished;

  @override
  int get hashCode =>
      Object.hash(total, remaining, failed, inFlight, offline, justFinished);
}

/// Per-property upload progress, projected from the durable queue.
///
/// Screens that can produce photos watch this instead of counting for
/// themselves, so the same number follows the agent from the camera to the
/// review grid to the gallery, survives navigation and backgrounding, and is
/// still right after a restart. Reopening the app to 12 pending shows 12
/// pending, because the queue said so — that is the promise the durable queue
/// makes, and this is where the agent finally sees it kept.
///
/// The queue only knows what is *left*, so the batch total is tracked here as
/// a high-water mark: it rises as photos are added and holds while they drain,
/// then resets once the queue empties.
class UploadProgress extends ChangeNotifier {
  UploadProgress._() {
    UploadQueue.instance.addListener(_recompute);
    UploadService.instance.addListener(_recompute);
  }
  static final UploadProgress instance = UploadProgress._();

  /// How long "All 18 photos uploaded" stays up before the bar disappears.
  static const Duration _finishedFor = Duration(seconds: 4);

  final Map<int, int> _watchers = {};
  final Map<int, int> _highWater = {};
  final Map<int, Timer> _finishedTimers = {};
  final Map<int, UploadProgressSnapshot> _snapshots = {};

  /// Registers interest in [propertyId]. Ref-counted, so two stacked screens
  /// watching the same property both work and neither's dispose blinds the
  /// other. Always pair with [unwatch].
  void watch(int propertyId) {
    _watchers[propertyId] = (_watchers[propertyId] ?? 0) + 1;
    // Seed this property's snapshot directly rather than going through
    // [_recompute]. Watchers register from initState, which can run inside
    // another widget's build; notifying there would setState an already-mounted
    // bar mid-build. The new widget reads the seeded value in its own first
    // build and needs no notification to do it.
    _snapshots[propertyId] = _computeFor(propertyId);
    // Warm the durable store so the count is right on the first frame rather
    // than flicking up from zero. This lands in a later microtask, where
    // notifying is safe.
    UploadQueue.instance.itemsFor(propertyId).then((_) => _recompute());
  }

  void unwatch(int propertyId) {
    final n = (_watchers[propertyId] ?? 0) - 1;
    if (n > 0) {
      _watchers[propertyId] = n;
      return;
    }
    _watchers.remove(propertyId);
    // Deliberately keeps [_highWater] and any running finish timer: the agent
    // moving from the camera to the gallery mid-batch must not restart the
    // count at whatever happens to be left.
  }

  UploadProgressSnapshot snapshotFor(int propertyId) =>
      _snapshots[propertyId] ?? UploadProgressSnapshot.empty;

  void _recompute() {
    var changed = false;
    for (final propertyId in _watchers.keys.toList()) {
      final next = _computeFor(propertyId);
      if (next != _snapshots[propertyId]) {
        _snapshots[propertyId] = next;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  UploadProgressSnapshot _computeFor(int propertyId) {
    final items = UploadQueue.instance.cachedItemsFor(propertyId);
    var remaining = 0;
    var failed = 0;
    var inFlight = false;
    for (final item in items) {
      if (item.state == PendingUploadState.failed) {
        failed++;
        continue;
      }
      remaining++;
      if (item.state == PendingUploadState.uploading) inFlight = true;
    }

    final previousHigh = _highWater[propertyId] ?? 0;
    var total = previousHigh;
    if (remaining > total) {
      total = remaining;
      _highWater[propertyId] = total;
    }

    var justFinished = _finishedTimers.containsKey(propertyId);
    if (remaining == 0) {
      // The batch drained. Say so, briefly, then forget it.
      if (previousHigh > 0 && !justFinished) {
        justFinished = true;
        _finishedTimers[propertyId] = Timer(_finishedFor, () {
          _finishedTimers.remove(propertyId);
          _highWater.remove(propertyId);
          _recompute();
        });
      } else if (!justFinished) {
        _highWater.remove(propertyId);
        total = 0;
      }
    } else if (justFinished) {
      // New photos arrived during the celebration — back to work.
      _finishedTimers.remove(propertyId)?.cancel();
      justFinished = false;
    }

    return UploadProgressSnapshot(
      total: total,
      remaining: remaining,
      failed: failed,
      inFlight: inFlight,
      offline: UploadService.instance.isOffline,
      justFinished: justFinished && remaining == 0,
    );
  }
}
