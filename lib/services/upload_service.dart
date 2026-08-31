import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../models/gallery_tags.dart';
import 'api_service.dart';
import 'upload_queue.dart';

/// Drains [UploadQueue] on its own, for as long as the app is open.
///
/// ## Why this exists
///
/// Draining used to be a side effect of the upload sheet being on screen: the
/// agent had to open the property's gallery and tap Upload, and if they didn't,
/// nothing moved. On 2026-08-28 an agent shot 35 photos, walked the house for
/// eighteen minutes with the sheet closed, and 27 of them sat in the queue for
/// eighty-five minutes on a phone that was demonstrably online the whole time —
/// they went up in a single thirteen-second burst the moment the gallery was
/// re-opened. From the agent's side that is indistinguishable from a failure,
/// and they reported it as one.
///
/// So the queue drains itself: on app start, on resume, and on a timer while
/// the app is open. No screen has to be visible, and no screen owns the work.
///
/// ## Storm guards
///
/// A self-driving retry loop is exactly the thing that turns one backend blip
/// into a device hammering the API, so the cadence is deliberately defensive:
///
///  * **One attempt per item per run.** The tick *is* the retry interval;
///    there is no inner retry loop stacking attempts on top of it.
///  * **Offline aborts the whole run after the first item.** If the very first
///    upload can't reach the server, the remaining items are not tried — 27
///    photos failing DNS in parallel every tick helps nobody.
///  * **Connection failures don't count as attempts.** A request that never
///    left the device didn't burden the server and mustn't burn the item's
///    budget: eighteen minutes of airplane mode would otherwise park a whole
///    shoot as permanently failed, and it would then need a manual retry —
///    the precise silence this class was written to end.
///  * **Server failures back off and are capped.** [_maxAttempts] real
///    attempts, then the photo is parked as `failed` with the server's own
///    message for the agent to retry by hand.
///  * **A 401 stops the run.** The ordinary re-login flow owns that; a
///    background loop must never race it.
class UploadService with WidgetsBindingObserver, ChangeNotifier {
  UploadService._();
  static final UploadService instance = UploadService._();

  /// How often the queue is checked while the app is in the foreground.
  ///
  /// Also the effective "connectivity regained" latency: with no connectivity
  /// plugin in the app, a short tick that no-ops on an empty queue is how a
  /// restored radio gets noticed. A tick with nothing queued does no I/O at
  /// all, so this is cheap enough to keep tight.
  static const Duration _tick = Duration(seconds: 20);

  /// Uploads in flight at once. Lower than the foreground sheet's 3: this runs
  /// unattended and may be competing with whatever screen the agent is
  /// actually using.
  static const int _maxConcurrent = 2;

  /// Real (server-answered) attempts before a photo is parked as failed and
  /// waits for an explicit retry.
  static const int _maxAttempts = 6;

  /// Backoff after a server-side failure, indexed by attempt count. Capped so
  /// a recovered backend is picked up within a couple of minutes.
  static const List<Duration> _backoff = [
    Duration(seconds: 20),
    Duration(seconds: 40),
    Duration(seconds: 90),
    Duration(minutes: 3),
  ];

  final ApiService _api = ApiService();

  Timer? _timer;
  bool _started = false;

  /// True while a flush run is in progress — the "Uploading…" affordance.
  bool _running = false;
  bool get isRunning => _running;

  /// True when the last run could not reach the server at all. Drives the
  /// "no connection" copy on the queue banner, and is recomputed at the end of
  /// every run — a run that got an answer, even a rejection, is not offline.
  bool _offline = false;
  bool get isOffline => _offline;

  /// Set when the server rejected our token. Flushing pauses until the app is
  /// resumed or something else asks for a flush, by which time the ordinary
  /// re-login flow has usually run.
  bool _authBlocked = false;

  /// Per-item earliest next attempt, for server-side backoff. In-memory only:
  /// a restart is itself a long enough wait.
  final Map<String, DateTime> _retryAfter = {};

  /// Monotonic count of photos confirmed landed this session. Screens snapshot
  /// it on open and compare on close to decide whether the property is worth
  /// re-fetching, without needing to have driven the upload themselves.
  int _successes = 0;
  int get successCount => _successes;

  /// Starts the lifecycle observer and the periodic drain. Safe to call more
  /// than once.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_tick, (_) => flush());
    // Anything left over from a previous session goes up now, without waiting
    // for the first tick and without anyone opening a gallery.
    flush();
  }

  void stopService() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Coming back from the camera app, from a call, or from airplane mode
    // being switched off in Settings. Clear the auth pause too: a resume is
    // the most likely moment for a re-login to have happened.
    _authBlocked = false;
    flush();
  }

  /// Drains every queued photo across every property.
  ///
  /// Re-entrant callers are collapsed: a second flush while one is running is
  /// dropped rather than queued, because the running one will pick up anything
  /// enqueued in the meantime.
  Future<void> flush() async {
    if (_running || _authBlocked) return;

    final items = await UploadQueue.instance.allItems();
    final now = DateTime.now();
    final ready = items
        .where((e) =>
            e.state == PendingUploadState.pending &&
            !(_retryAfter[e.id]?.isAfter(now) ?? false))
        .toList();
    if (ready.isEmpty) return;

    // Never upload on a session we don't have. Without this the whole queue
    // would 401 its way to the attempt cap while the agent sits on the login
    // screen, and the photos would be parked as failed by the time they signed
    // back in.
    if (await _api.getToken() == null) return;

    _running = true;
    notifyListeners();
    try {
      await _drain(ready);
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  /// Bounded worker pool over [ready]. Workers stop early when a run-level
  /// stop is signalled (offline, or an expired token).
  Future<void> _drain(List<PendingUpload> ready) async {
    var next = 0;
    var stop = false;
    var sawOffline = false;

    // The event loop is single-threaded, so reading and bumping [next] between
    // awaits is race-free — no two workers grab the same index.
    Future<void> worker() async {
      while (!stop && next < ready.length) {
        final item = ready[next++];
        final outcome = await _uploadOne(item);
        if (outcome == _Outcome.offline) sawOffline = true;
        if (outcome == _Outcome.offline || outcome == _Outcome.stopRun) {
          stop = true;
        }
      }
    }

    final workers =
        _maxConcurrent < ready.length ? _maxConcurrent : ready.length;
    await Future.wait(List.generate(workers, (_) => worker()));

    // A run that reached the server — even to be rejected by it — is not an
    // offline run. Without this the "no connection" copy would stick around
    // after the radio came back, on the strength of one old failure.
    _offline = sawOffline;
  }

  /// One attempt at one photo. Never retries in place — the caller's tick is
  /// the retry.
  Future<_Outcome> _uploadOne(PendingUpload item) async {
    // The intent is replayed exactly as it was persisted. In particular the
    // room tag comes from the item, never from a screen: the whole point of
    // storing it was that by the time a queued photo uploads, the selection it
    // was taken under is long gone.
    final String? roomTag = item.roomTag;

    await UploadQueue.instance.markUploading(item.id);
    try {
      final result = await _api.uploadPropertyImage(
        item.propertyId,
        item.file,
        roomTag,
        clientId: item.clientUploadId,
      );
      // Only a 2xx gets here, so this is the one place a photo may leave the
      // queue as "landed".
      _verifyFiledTag(sent: roomTag, result: result);
      _retryAfter.remove(item.id);
      _successes++;
      if (_offline) _offline = false;
      await UploadQueue.instance.remove(item.id);
      return _Outcome.ok;
    } on TagValidationException catch (e) {
      // The room no longer exists on this property. Retrying re-sends the same
      // dead tag forever, so park it with a message that names the actual fix.
      // The tag is left ON the item: it is the only record of where the agent
      // meant this photo to go, and the gallery offers a re-file from it.
      debugPrint('[upload] stale tag "${item.roomTag}" on ${item.id}: '
          '${e.availableTags.length} tags available');
      await UploadQueue.instance.markFailed(
          item.id, '"${item.roomTag}" is no longer a room on this property');
      return _Outcome.failed;
    } on ApiException catch (e) {
      return _handleApiFailure(item, e);
    } on SocketException {
      return _markOffline(item, countAttempt: false);
    } on TimeoutException {
      return _handleTimeout(item);
    } catch (e) {
      // http throws ClientException for a dropped/refused connection, which is
      // the same "never reached the server" shape as SocketException.
      debugPrint('[upload] transport failure on ${item.id}: $e');
      return _markOffline(item, countAttempt: false);
    }
  }

  /// A timeout is ambiguous: the request may well have reached the server and
  /// died on the way back. So it aborts the run like an offline failure, but it
  /// *does* count as an attempt and *does* escalate the backoff — a server that
  /// accepts connections and then hangs must not be retried flat out every
  /// tick, and a photo that has timed out six times needs a human, not a
  /// seventh round trip.
  Future<_Outcome> _handleTimeout(PendingUpload item) async {
    if (item.attempts >= _maxAttempts) {
      await UploadQueue.instance.markFailed(
          item.id, 'Upload kept timing out. Try again on a better connection.');
      return _Outcome.failed;
    }
    _retryAfter[item.id] = DateTime.now().add(_backoffFor(item.attempts));
    return _markOffline(item, countAttempt: true);
  }

  Future<_Outcome> _handleApiFailure(
      PendingUpload item, ApiException e) async {
    // 401: the token is gone. Stop the run and let the app's re-login flow
    // deal with it; the queue is untouched and drains after the next sign-in.
    if (e.statusCode == 401) {
      _authBlocked = true;
      await UploadQueue.instance.markPending(item.id);
      return _Outcome.stopRun;
    }

    // statusCode 0 is ApiService's marker for "the upload timed out" — it never
    // got an answer, so it takes the timeout path rather than being read as a
    // rejection.
    if (e.statusCode == 0) return _handleTimeout(item);

    // Any other 4xx is the server declining these bytes, on purpose. No retry
    // can change that, so surface the server's own message and let the agent
    // decide — dropping it silently is what made 27 photos "disappear".
    final permanent = e.statusCode >= 400 && e.statusCode < 500;
    if (permanent || item.attempts >= _maxAttempts) {
      await UploadQueue.instance.markFailed(item.id, e.message);
      return _Outcome.failed;
    }

    // 5xx / anything transient: back off and let a later tick try again.
    _retryAfter[item.id] = DateTime.now().add(_backoffFor(item.attempts));
    await UploadQueue.instance.markPending(item.id);
    return _Outcome.retry;
  }

  /// The server could not be reached (or did not answer). Leave the photo
  /// pending and abandon the rest of this run — 27 photos failing DNS in
  /// parallel every tick helps nobody.
  ///
  /// [countAttempt] is false for a request that never left the device: it
  /// burdened no server, so it must not burn the item's budget. Eighteen
  /// minutes of airplane mode would otherwise park a whole shoot as
  /// permanently failed, needing a manual retry — the exact silence this class
  /// exists to end.
  Future<_Outcome> _markOffline(PendingUpload item,
      {required bool countAttempt}) async {
    if (!countAttempt) {
      // markUploading already incremented; undo it.
      item.attempts = item.attempts > 0 ? item.attempts - 1 : 0;
    }
    await UploadQueue.instance.markPending(item.id);
    if (!_offline) {
      _offline = true;
      notifyListeners();
    }
    return _Outcome.offline;
  }

  /// Diagnostic: compares the tag we posted against the tag the server says it
  /// filed the photo under, from the 201 body.
  ///
  /// Log-only, deliberately. This used to raise a warning to the agent because
  /// the gallery had no way to show a misfiled photo — untagged photos were
  /// rendered nowhere at all. Now that Unsorted and every room render from the
  /// server's own grouping, a misfiled photo is visible where it actually is,
  /// which beats a snackbar about it. What is left here is the breadcrumb for
  /// diagnosing the *next* tag-loss incident.
  ///
  /// The server matches case- and whitespace-insensitively and stores the
  /// library's canonical casing, so "bedroom 2" coming back as "Bedroom 2" is
  /// a match, not a drift. Anything else means the photo is not where the
  /// agent put it — most importantly `filed == null`, which is the server
  /// saying "unsorted" no matter what the UI showed.
  ///
  /// Two responses carry no usable answer and must be sat out rather than read
  /// as "unsorted", or a correctly-filed photo gets reported as misfiled:
  ///
  ///  * a dedupe hit ([UploadedImage.duplicate]) — the server's fast path
  ///    answers `room_tag: null` whatever the photo was really filed under, and
  ///    that is the shape EVERY replayed upload takes, so this would cry wolf
  ///    on exactly the batches that had a rough time on the network;
  ///  * an unparseable body (empty [UploadedImage.url]) — we know nothing.
  void _verifyFiledTag(
      {required String? sent, required UploadedImage result}) {
    if (result.duplicate || result.url.isEmpty) return;
    final filed = result.roomTag;
    String norm(String? s) => (s ?? '').trim().toLowerCase();
    if (norm(sent) == norm(filed)) return;
    debugPrint('[upload] tag mismatch: sent room_tag=${sent ?? "(omitted)"} '
        'but server filed it under ${filed ?? "(unsorted)"}');
  }

  Duration _backoffFor(int attempts) {
    final i = attempts <= 0 ? 0 : attempts - 1;
    return _backoff[i < _backoff.length ? i : _backoff.length - 1];
  }

  /// Clears the failure state on [item] and asks for an immediate flush —
  /// the agent tapping Retry on a parked photo.
  Future<void> retry(PendingUpload item) async {
    _retryAfter.remove(item.id);
    _authBlocked = false;
    await UploadQueue.instance.markPending(item.id);
    await flush();
  }

  /// Retries every parked photo on one property.
  Future<void> retryAllFor(int propertyId) async {
    final items = await UploadQueue.instance.itemsFor(propertyId);
    for (final item in items) {
      if (item.state != PendingUploadState.failed) continue;
      _retryAfter.remove(item.id);
      await UploadQueue.instance.markPending(item.id);
    }
    _authBlocked = false;
    await flush();
  }

  @override
  void dispose() {
    stopService();
    super.dispose();
  }
}

/// What one attempt did, from the run’s point of view.
///
/// [offline] and [stopRun] both abandon the rest of the run; they are kept
/// apart because only [offline] means the server was unreachable, and only
/// that should leave the UI saying so.
enum _Outcome { ok, failed, retry, offline, stopRun }
