import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_version.dart';
import 'api_service.dart';

/// A phase in one photo's life, as the **device** saw it.
///
/// There is deliberately no `received`. The server writes that itself when the
/// bytes land and rejects it from a client: "did it actually arrive" is the one
/// thing the phone cannot be the witness for, and it is the whole question.
enum PhotoPhase {
  /// The shutter fired, or the picker handed this photo back. Emitted the
  /// moment the file exists on disk — before any preview, review step or
  /// "Done", and before the durable queue row.
  captured,

  /// The durable queue row is committed. The gap between this and [captured]
  /// is the blind spot the whole feature exists to light up.
  queued,

  uploadStarted,
  uploadOk,

  /// One attempt failed. The reason belongs in `meta.error`.
  uploadFailed,

  /// We gave up, or the agent deleted the photo.
  dropped,
}

extension PhotoPhaseWire on PhotoPhase {
  String get wire {
    switch (this) {
      case PhotoPhase.captured:
        return 'captured';
      case PhotoPhase.queued:
        return 'queued';
      case PhotoPhase.uploadStarted:
        return 'upload_started';
      case PhotoPhase.uploadOk:
        return 'upload_ok';
      case PhotoPhase.uploadFailed:
        return 'upload_failed';
      case PhotoPhase.dropped:
        return 'dropped';
    }
  }
}

/// One event on the local log: the server payload plus a device-local id used
/// only to delete the right line after a successful send.
class _LoggedEvent {
  final String localId;
  final Map<String, dynamic> payload;

  _LoggedEvent(this.localId, this.payload);

  String toLine() => jsonEncode({'lid': localId, 'e': payload});

  static _LoggedEvent? fromLine(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) return null;
      final lid = decoded['lid'];
      final payload = decoded['e'];
      if (lid is! String || payload is! Map) return null;
      return _LoggedEvent(lid, Map<String, dynamic>.from(payload));
    } catch (_) {
      // A half-written trailing line from a kill mid-append. Skip it; the
      // events either side of it are still perfectly good.
      return null;
    }
  }
}

/// Per-photo diagnostics for the upload pipeline: a durable local log of what
/// happened to every photo, flushed to `POST /v1/mobile/photo-events`.
///
/// ## Why this exists
///
/// The server only ever sees the survivors. On 2026-08-31 an agent shot ~40
/// photos on listing 15753 and 28 arrived; the only reason we could prove the
/// other 12 were never enqueued is that `client_upload_id` happened to run
/// 1..28 with no gaps. That was luck — the key is an idempotency token, not a
/// diagnostic. A photo that dies between the camera and the queue leaves no
/// trace anywhere, on the device or on the server.
///
/// ## Why it is durable, and not a ping
///
/// The naive version fails in exactly the case we care about: emit "captured"
/// over the network at the shutter, have the app killed two seconds later, and
/// the ping dies with the app — the photo is invisible again, which is the bug.
/// So the write to the local log is the primary act and the network send is a
/// second, separate step:
///
///  * every event is appended to a durable file (Application Support, same
///    survivability as the upload queue) before anything touches the network;
///  * flushes are opportunistic — app start, resume, the existing 20s upload
///    tick, and after any upload attempt;
///  * an event is deleted **only** on a 2xx. Anything else stays for the next
///    flush;
///  * replays are safe: the server dedupes on
///    `(property_id, client_upload_id, phase)`. Resending beats losing.
///
/// ## Telemetry never costs a photo
///
/// [record] is synchronous, returns immediately, and swallows everything. No
/// capture, enqueue or upload ever awaits this class or can be failed by it. If
/// the log write fails the event is dropped and the photo carries on; if the
/// endpoint is dead the queue keeps uploading exactly as it did before.
class PhotoTelemetry {
  PhotoTelemetry._();
  static final PhotoTelemetry instance = PhotoTelemetry._();

  static const String _dirName = 'photo_telemetry';
  static const String _fileName = 'events.jsonl';

  /// Server cap per call.
  static const int _batchSize = 200;

  /// Batches sent per flush. Three keeps a backlog draining briskly while
  /// staying far under the endpoint's 60/min throttle (a 20s tick could only
  /// ever reach 9/min at this rate).
  static const int _maxBatchesPerFlush = 3;

  /// Hard cap on the local log so a long offline stretch cannot grow
  /// unbounded. Oldest events are dropped first: the newest are the ones that
  /// explain what the agent is complaining about right now.
  static const int _maxEvents = 3000;

  /// Backoff after a failed flush, indexed by consecutive failures. Capped at
  /// five minutes — a dead endpoint must cost the device almost nothing, but
  /// the log has to keep trying, because nothing else will ever send it.
  static const List<Duration> _backoff = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
  ];

  final ApiService _api = ApiService();

  /// Every disk operation is chained through here, so an append can never
  /// interleave with a rewrite and the load always happens first. The network
  /// send deliberately runs *outside* this chain: a slow request must not park
  /// new `captured` events in memory, unwritten, for the length of a timeout —
  /// that is precisely the window a kill would lose them in.
  Future<void> _io = Future<void>.value();
  bool _loaded = false;

  final List<_LoggedEvent> _events = [];

  bool _flushing = false;
  int _failures = 0;
  DateTime? _nextAttemptAt;
  int _seq = 0;

  /// Records one event. Fire-and-forget by contract: never awaited, never
  /// throws, never blocks the caller.
  ///
  /// [occurredAt] is the **phone's** clock at the moment the thing happened,
  /// not the moment we flush — measuring capture→arrival lag is the point, so
  /// callers that record after the fact must pass the real time.
  void record({
    required int propertyId,
    required String clientUploadId,
    required PhotoPhase phase,
    DateTime? occurredAt,
    String? batchId,
    Map<String, dynamic>? meta,
  }) {
    try {
      final payload = <String, dynamic>{
        'property_id': propertyId,
        'client_upload_id': clientUploadId,
        'phase': phase.wire,
        'occurred_at': (occurredAt ?? DateTime.now()).millisecondsSinceEpoch,
        if (batchId != null) 'batch_id': batchId,
        'meta': <String, dynamic>{
          'app_build': '$kAppVersion+$kAppBuildNumber',
          if (meta != null) ...meta,
        },
      };
      final event = _LoggedEvent(_nextLocalId(), payload);
      _run(() async {
        await _ensureLoaded();
        _events.add(event);
        await _append(event);
        if (_events.length > _maxEvents) await _trim();
      });
    } catch (_) {
      // Losing a diagnostic must never cost a photo.
    }
  }

  /// Sends whatever is pending. Safe to call as often as anything likes: it
  /// no-ops on an empty log, while a flush is already running, while backing
  /// off from a failure, and while signed out.
  Future<void> flush() async {
    if (_flushing) return;
    final until = _nextAttemptAt;
    if (until != null && until.isAfter(DateTime.now())) return;

    _flushing = true;
    try {
      for (var i = 0; i < _maxBatchesPerFlush; i++) {
        final batch = await _takeBatch();
        if (batch.isEmpty) return;

        // Signed out: keep the events and try again after the next sign-in.
        // Sending without a token would only burn the backoff.
        if (await _api.getToken() == null) return;

        final sent = await _send(batch);
        if (!sent) return;
        await _forget(batch);
        // A short batch means the log is drained; nothing left to send.
        if (batch.length < _batchSize) return;
      }
    } catch (e) {
      debugPrint('[photo-telemetry] flush aborted: $e');
    } finally {
      _flushing = false;
    }
  }

  /// POSTs one batch. Returns true when the events may be deleted locally.
  Future<bool> _send(List<_LoggedEvent> batch) async {
    try {
      await _api.postPhotoEvents(batch.map((e) => e.payload).toList());
      _failures = 0;
      _nextAttemptAt = null;
      return true;
    } on ApiException catch (e) {
      // 401 is a missing/expired session, 408 and 429 are "try later" — all
      // three keep the events. Any other 4xx means the server will never
      // accept this batch, and retrying it forever would wedge the log behind
      // a payload it hates until the cap evicted everything queued behind it.
      // Drop it and keep the pipeline moving: a wedged diagnostic log reports
      // nothing at all, which is the state we are trying to leave.
      final poisoned = e.statusCode >= 400 &&
          e.statusCode < 500 &&
          e.statusCode != 401 &&
          e.statusCode != 408 &&
          e.statusCode != 429;
      debugPrint('[photo-telemetry] ${batch.length} events rejected '
          '(${e.statusCode}): ${e.message}${poisoned ? ' — discarding' : ''}');
      if (poisoned) {
        await _forget(batch);
        _failures = 0;
        _nextAttemptAt = null;
        return false;
      }
      _backOff();
      return false;
    } catch (e) {
      // Offline, timeout, dead host. The events stay exactly where they are.
      debugPrint('[photo-telemetry] could not reach the server: $e');
      _backOff();
      return false;
    }
  }

  void _backOff() {
    final i = _failures < _backoff.length ? _failures : _backoff.length - 1;
    _nextAttemptAt = DateTime.now().add(_backoff[i]);
    _failures++;
  }

  /// Oldest-first snapshot of up to [_batchSize] events, taken on the IO chain
  /// so it cannot race an append.
  Future<List<_LoggedEvent>> _takeBatch() {
    final completer = Completer<List<_LoggedEvent>>();
    _run(
      () async {
        await _ensureLoaded();
        final end = _events.length < _batchSize ? _events.length : _batchSize;
        completer.complete(_events.sublist(0, end));
      },
      onError: () => completer.complete(const []),
    );
    return completer.future;
  }

  /// Drops [batch] from memory and rewrites the file. By id, not by index:
  /// events recorded while the batch was on the wire have already been
  /// appended, and a [_trim] may have shifted everything along.
  Future<void> _forget(List<_LoggedEvent> batch) {
    final completer = Completer<void>();
    _run(
      () async {
        final gone = batch.map((e) => e.localId).toSet();
        _events.removeWhere((e) => gone.contains(e.localId));
        await _writeAll();
        completer.complete();
      },
      onError: completer.complete,
    );
    return completer.future;
  }

  // --- local log ---

  /// Application Support, not Documents — the same reasoning as the upload
  /// queue: `UIFileSharingEnabled` exposes the whole Documents tree, and this
  /// is internal plumbing an agent should never see, let alone delete.
  Future<File> _file() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$_fileName');
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _file();
      if (!await file.exists()) return;
      for (final line in await file.readAsLines()) {
        if (line.trim().isEmpty) continue;
        final event = _LoggedEvent.fromLine(line);
        if (event != null) _events.add(event);
      }
      if (_events.length > _maxEvents) await _trim();
    } catch (e) {
      // Unreadable log — start clean. Diagnostics must never be the thing that
      // breaks a launch.
      debugPrint('[photo-telemetry] could not read the local log: $e');
      _events.clear();
    }
  }

  /// Appends one line, flushed to disk. `flush: true` is the whole point: the
  /// definition of done is ten photos surviving a force-kill seconds after the
  /// shutter, and an event sitting in an OS write buffer does not survive that.
  Future<void> _append(_LoggedEvent event) async {
    final file = await _file();
    await file.writeAsString(
      '${event.toLine()}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  /// Rewrites the log from memory via a temp file and a rename, so a kill
  /// mid-rewrite leaves the previous complete log rather than half of one.
  /// Worst case we replay events the server already has, and it dedupes them.
  Future<void> _writeAll() async {
    final file = await _file();
    if (_events.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      '${_events.map((e) => e.toLine()).join('\n')}\n',
      flush: true,
    );
    await tmp.rename(file.path);
  }

  /// Enforces [_maxEvents], oldest first.
  Future<void> _trim() async {
    final excess = _events.length - _maxEvents;
    if (excess <= 0) return;
    _events.removeRange(0, excess);
    debugPrint('[photo-telemetry] log full — dropped $excess oldest events');
    await _writeAll();
  }

  String _nextLocalId() {
    _seq++;
    return '${DateTime.now().microsecondsSinceEpoch}_$_seq';
  }

  /// Chains [action] onto the IO queue, absorbing any failure. A telemetry
  /// write that throws must leave the app exactly as it found it.
  void _run(Future<void> Function() action, {void Function()? onError}) {
    _io = _io.then((_) => action()).catchError((Object e) {
      debugPrint('[photo-telemetry] local log write failed: $e');
      onError?.call();
    });
  }
}
