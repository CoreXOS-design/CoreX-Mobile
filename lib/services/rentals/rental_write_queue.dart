import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/uuid.dart';
import 'rentals_http.dart';

/// ISO 8601 with the phone's UTC offset (`2026-10-25T09:14:03+02:00`) — the
/// shape the server stores as `captured_at`. Dart's own `toIso8601String`
/// drops the offset on a local time, which the server would read as UTC.
String isoWithOffset(DateTime t) {
  final local = t.toLocal();
  final off = local.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final h = off.inHours.abs().toString().padLeft(2, '0');
  final m = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-'
      '${two(local.day)}T${two(local.hour)}:${two(local.minute)}:'
      '${two(local.second)}$sign$h:$m';
}

enum QueuedWriteState { pending, sending, failed }

/// One write waiting to reach the server, and the **complete intent** for it.
///
/// Like [PendingUpload] for gallery photos: everything the request needs is in
/// here — the path, the fields, the queue's own copy of each file and the
/// idempotency key minted at the tap — so a replay days later, after any
/// number of restarts, sends exactly what the person meant.
class QueuedRentalWrite {
  final String id;
  final RentalsAudience audience;

  /// Who was signed in when this was queued. Only drained while that same
  /// session is active, so one person's queued work is never sent with the
  /// next person's token.
  final String sessionKey;

  final String method;

  /// Relative to `/api/v1`. May contain `{ref:<localId>}`, replaced at send
  /// time with the server id an earlier queued write came back with (an
  /// observation's photo is queued before the observation has an id).
  final String path;

  final bool multipart;
  final Map<String, dynamic> fields;

  /// field name → path of the queue-owned copy.
  final Map<String, String> files;

  /// Minted once at the tap and resent unchanged on every retry.
  final String idempotencyKey;

  /// False for the few writes that are queue-safe by nature and take no key.
  final bool sendKey;

  /// What the person sees in the queue ("Photo for Bedroom 1 · Ceiling").
  final String label;

  /// What this write belongs to (e.g. `inspection:358`), so a screen can count
  /// what it still has unsent — the server's `pending_client_items`.
  final String? group;

  /// A write that must succeed first (its id feeds `{ref:...}`).
  final String? dependsOn;

  QueuedWriteState state;
  String? error;
  int attempts;
  int nextAttemptAt;
  final int createdAt;

  QueuedRentalWrite({
    required this.id,
    required this.audience,
    required this.sessionKey,
    required this.method,
    required this.path,
    required this.multipart,
    required this.fields,
    required this.files,
    required this.idempotencyKey,
    required this.sendKey,
    required this.label,
    required this.group,
    required this.dependsOn,
    this.state = QueuedWriteState.pending,
    this.error,
    this.attempts = 0,
    this.nextAttemptAt = 0,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'audience': audience.wire,
        'session_key': sessionKey,
        'method': method,
        'path': path,
        'multipart': multipart,
        'fields': fields,
        'files': files,
        'idempotency_key': idempotencyKey,
        'send_key': sendKey,
        'label': label,
        'group': group,
        'depends_on': dependsOn,
        // `sending` is in-flight only: a kill mid-request must come back as
        // pending, or nothing would ever move it again.
        'state': state == QueuedWriteState.failed ? 'failed' : 'pending',
        'error': error,
        'attempts': attempts,
        'next_attempt_at': nextAttemptAt,
        'created_at': createdAt,
      };

  static QueuedRentalWrite? fromJson(Map<String, dynamic> j) {
    final aud = RentalsAudience.fromWire(j['audience'] as String?);
    if (aud == null) return null;
    return QueuedRentalWrite(
      id: j['id'] as String,
      audience: aud,
      sessionKey: (j['session_key'] ?? '').toString(),
      method: (j['method'] ?? 'POST').toString(),
      path: j['path'] as String,
      multipart: j['multipart'] == true,
      fields: Map<String, dynamic>.from((j['fields'] as Map?) ?? const {}),
      files: Map<String, String>.from((j['files'] as Map?) ?? const {}),
      idempotencyKey: j['idempotency_key'] as String,
      sendKey: j['send_key'] != false,
      label: (j['label'] ?? '').toString(),
      group: j['group'] as String?,
      dependsOn: j['depends_on'] as String?,
      state: j['state'] == 'failed'
          ? QueuedWriteState.failed
          : QueuedWriteState.pending,
      error: j['error'] as String?,
      attempts: (j['attempts'] as num?)?.toInt() ?? 0,
      nextAttemptAt: (j['next_attempt_at'] as num?)?.toInt() ?? 0,
      createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
    );
  }
}

/// What happened to a [RentalWriteQueue.submit].
sealed class SubmitOutcome {
  const SubmitOutcome();
}

/// The server has it. [body] is its answer (`duplicate: true` on a replay).
class SubmitSent extends SubmitOutcome {
  final Map<String, dynamic> body;
  const SubmitSent(this.body);
}

/// No signal (or the server is down): it is saved on the phone and will send
/// itself. The person can carry on.
class SubmitQueued extends SubmitOutcome {
  final String reason;
  const SubmitQueued(this.reason);
}

/// The server said no (422/403/404/409). Not retried; show [error].
class SubmitRefused extends SubmitOutcome {
  final RentalsApiException error;
  const SubmitRefused(this.error);
}

/// The record was withdrawn or archived meanwhile; dropped.
class SubmitArchived extends SubmitOutcome {
  final String message;
  const SubmitArchived(this.message);
}

/// Durable queue for rentals writes made where the signal is bad: fault
/// reports, notes, work-order photos, and a whole inspection walkthrough.
///
/// The rules come from the server contract:
///  * 2xx (incl. `duplicate: true`) → done, remove.
///  * 410 `archived` → drop it (and anything waiting on it), tell the person.
///  * 422 / 404 / 403 / a named 409 → never retried; kept as failed with the
///    server's sentence until the person retries or discards it.
///  * 5xx, network, 429, 409 "still being sent" → retry with backoff, same key.
///
/// Draining is serial and oldest-first, so an observation always goes before
/// its photos. Per [feedback_loop_storm_guards], retries back off to a ceiling
/// and a failing item never spins.
class RentalWriteQueue extends ChangeNotifier {
  RentalWriteQueue._();
  static final RentalWriteQueue instance = RentalWriteQueue._();

  static const String _prefsKey = 'rental_write_queue_v1';
  static const String _resultsKey = 'rental_write_queue_results_v1';
  static const String _dirName = 'rental_queue';
  static const Duration _maxBackoff = Duration(minutes: 10);

  final RentalsHttp _http = RentalsHttp.instance;
  final List<QueuedRentalWrite> _items = [];

  /// local id → server id, for `{ref:...}`. Kept after the item leaves so a
  /// dependent queued later still resolves.
  final Map<String, int> _results = {};

  Future<void>? _loading;
  bool _draining = false;
  bool _drainAgain = false;
  Timer? _wake;
  String? _sessionKey;

  /// Plain sentences for the person: something was dropped because its record
  /// was archived, or the server refused it. Screens show and clear these.
  final ValueNotifier<String?> notice = ValueNotifier<String?>(null);

  /// Bumped after every write the server accepted, so open screens can
  /// refresh what they show.
  final ValueNotifier<int> sent = ValueNotifier<int>(0);

  static const String _lastSessionKey = 'rental_write_queue_last_session_v1';

  /// Set from the auth layer whenever who is signed in changes. `null` while
  /// nobody is: nothing drains, nothing is lost.
  void setSession(String? key) {
    if (_sessionKey == key) return;
    _sessionKey = key;
    notifyListeners();
    if (key != null) {
      unawaited(SharedPreferences.getInstance()
          .then((p) => p.setString(_lastSessionKey, key))
          .catchError((_) => false));
      kick();
    }
  }

  /// Someone is signed in but their id is not known yet — an offline cold
  /// start, where the profile call could not run. Carry on as whoever was
  /// last signed in on this phone, so work queued in a dead spot is neither
  /// stamped with nobody nor lost.
  Future<void> resumeLastSession() async {
    if (_sessionKey != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = prefs.getString(_lastSessionKey);
      if (key != null && _sessionKey == null) setSession(key);
    } catch (_) {}
  }

  String? get sessionKey => _sessionKey;

  Future<void> _ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final e in decoded) {
            if (e is! Map) continue;
            final item =
                QueuedRentalWrite.fromJson(Map<String, dynamic>.from(e));
            if (item != null) _items.add(item);
          }
        }
      }
      final res = prefs.getString(_resultsKey);
      if (res != null) {
        final m = jsonDecode(res);
        if (m is Map) {
          m.forEach((k, v) {
            if (v is num) _results[k.toString()] = v.toInt();
          });
        }
      }
    } catch (_) {
      _items.clear();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(_items.map((e) => e.toJson()).toList()));
      // Kept after the queue empties: a photo taken later against an
      // observation that already synced still resolves its `{ref:...}`.
      // Bounded so it cannot grow forever (insertion order = oldest first).
      while (_results.length > 1000) {
        _results.remove(_results.keys.first);
      }
      await prefs.setString(_resultsKey, jsonEncode(_results));
    } catch (_) {}
  }

  Future<void> _commit() async {
    await _persist();
    notifyListeners();
  }

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Every item of the signed-in session, oldest first.
  List<QueuedRentalWrite> get items => _items
      .where((e) => e.sessionKey == _sessionKey)
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// What [group] still holds unsent — failed ones included, since the server
  /// does not have them either.
  int pendingCount(String group) =>
      _items.where((e) => e.group == group && e.sessionKey == _sessionKey).length;

  List<QueuedRentalWrite> itemsIn(String group) =>
      items.where((e) => e.group == group).toList();

  /// The server id a queued write came back with, once it has.
  int? resultFor(String localId) => _results[localId];

  /// Queues a write and makes one attempt straight away.
  ///
  /// [files] map field → a file the caller owns (e.g. image_picker's cache
  /// path); the queue copies each one, because the OS may evict the original
  /// before a retry.
  Future<({String id, SubmitOutcome outcome})> submit({
    required RentalsAudience audience,
    required String path,
    required String label,
    Map<String, dynamic> fields = const {},
    Map<String, String> files = const {},
    bool multipart = false,
    String method = 'POST',
    String? group,
    String? dependsOn,
    bool sendKey = true,
    String? idempotencyKey,
  }) async {
    final id = await enqueue(
      audience: audience,
      path: path,
      label: label,
      fields: fields,
      files: files,
      multipart: multipart || files.isNotEmpty,
      method: method,
      group: group,
      dependsOn: dependsOn,
      sendKey: sendKey,
      idempotencyKey: idempotencyKey,
    );
    final item = _find(id);
    if (item == null) {
      return (id: id, outcome: const SubmitQueued('Saved on this phone.'));
    }
    if (item.dependsOn != null && !_isResolved(item.dependsOn!)) {
      return (
        id: id,
        outcome: const SubmitQueued(
            'Saved on this phone. It will send after the item it belongs to.'),
      );
    }
    final outcome = await _attempt(item);
    return (id: id, outcome: outcome);
  }

  /// Queues without an immediate attempt; returns the local id.
  Future<String> enqueue({
    required RentalsAudience audience,
    required String path,
    required String label,
    Map<String, dynamic> fields = const {},
    Map<String, String> files = const {},
    bool multipart = false,
    String method = 'POST',
    String? group,
    String? dependsOn,
    bool sendKey = true,
    String? idempotencyKey,
  }) async {
    await _ensureLoaded();
    final id = uuidV4();
    final owned = <String, String>{};
    var n = 0;
    final dir = files.isEmpty ? null : await _dir();
    for (final e in files.entries) {
      final src = File(e.value);
      final dot = e.value.lastIndexOf('.');
      final ext = dot >= 0 ? e.value.substring(dot) : '.jpg';
      final dest = File('${dir!.path}/${id}_${n++}$ext');
      await src.copy(dest.path);
      owned[e.key] = dest.path;
    }
    _items.add(QueuedRentalWrite(
      id: id,
      audience: audience,
      sessionKey: _sessionKey ?? '',
      method: method,
      path: path,
      multipart: multipart || owned.isNotEmpty,
      fields: Map<String, dynamic>.from(fields),
      files: owned,
      idempotencyKey: idempotencyKey ?? uuidV4(),
      sendKey: sendKey,
      label: label,
      group: group,
      dependsOn: dependsOn,
      createdAt: DateTime.now().microsecondsSinceEpoch,
    ));
    await _commit();
    return id;
  }

  QueuedRentalWrite? _find(String id) {
    for (final e in _items) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// A dependency is resolved once the server gave it an id. One that is no
  /// longer queued and left no id was dropped, which [_dropDependents] handles.
  bool _isResolved(String localId) => _results.containsKey(localId);

  /// Person-driven: try a failed item again (same key, so a write that did
  /// land is answered as a duplicate rather than made twice).
  Future<void> retry(String id) async {
    await _ensureLoaded();
    final item = _find(id);
    if (item == null) return;
    item
      ..state = QueuedWriteState.pending
      ..error = null
      ..nextAttemptAt = 0;
    await _commit();
    kick();
  }

  /// Person-driven: give up on an item (and anything waiting on it).
  Future<void> discard(String id) async {
    await _ensureLoaded();
    final item = _find(id);
    if (item == null) return;
    await _remove(item);
    await _dropDependents(id);
    await _commit();
  }

  Future<void> _remove(QueuedRentalWrite item) async {
    _items.remove(item);
    for (final p in item.files.values) {
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> _dropDependents(String parentId) async {
    final deps = _items.where((e) => e.dependsOn == parentId).toList();
    for (final d in deps) {
      await _remove(d);
      await _dropDependents(d.id);
    }
  }

  /// Off in unit tests, so bookkeeping can be exercised without any request.
  @visibleForTesting
  bool autoDrain = true;

  /// Wakes the drainer (app start, resume, after a sign-in, after a submit).
  void kick() {
    if (!autoDrain) return;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    await _ensureLoaded();
    if (_draining) {
      _drainAgain = true;
      return;
    }
    _draining = true;
    try {
      do {
        _drainAgain = false;
        while (true) {
          final next = _nextDue();
          if (next == null) break;
          final outcome = await _attempt(next);
          // A transient failure means the network or server is down; trying
          // the rest now would only fail the same way. Wait for the backoff.
          if (outcome is SubmitQueued) break;
        }
      } while (_drainAgain);
    } finally {
      _draining = false;
      _scheduleWake();
    }
  }

  QueuedRentalWrite? _nextDue() {
    if (_sessionKey == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final e in items) {
      if (e.state != QueuedWriteState.pending) continue;
      if (e.nextAttemptAt > now) continue;
      if (e.dependsOn != null && !_isResolved(e.dependsOn!)) continue;
      return e;
    }
    return null;
  }

  void _scheduleWake() {
    _wake?.cancel();
    final waiting = items
        .where((e) => e.state == QueuedWriteState.pending)
        .map((e) => e.nextAttemptAt)
        .toList();
    if (waiting.isEmpty) return;
    final soonest = waiting.reduce(min);
    final delay = soonest - DateTime.now().millisecondsSinceEpoch;
    _wake = Timer(
        Duration(milliseconds: delay.clamp(1000, _maxBackoff.inMilliseconds)),
        kick);
  }

  String _resolvePath(String path) {
    return path.replaceAllMapped(RegExp(r'\{ref:([0-9a-f-]+)\}'), (m) {
      final id = _results[m.group(1)!];
      return id?.toString() ?? m.group(0)!;
    });
  }

  Future<SubmitOutcome> _attempt(QueuedRentalWrite item) async {
    if (item.state == QueuedWriteState.sending) {
      return const SubmitQueued('Already sending.');
    }
    item
      ..state = QueuedWriteState.sending
      ..attempts += 1;
    notifyListeners();

    final path = _resolvePath(item.path);
    final fields = Map<String, dynamic>.from(item.fields);
    if (item.sendKey) fields['client_idempotency_key'] = item.idempotencyKey;
    final key = item.sendKey ? item.idempotencyKey : null;

    try {
      for (final p in item.files.values) {
        if (!await File(p).exists()) {
          throw RentalsApiException(422,
              'The photo for "${item.label}" is no longer on this phone.');
        }
      }
      final Map<String, dynamic> body;
      if (item.multipart) {
        body = await _http.multipart(item.audience, path,
            fields: fields,
            files: [
              for (final e in item.files.entries) RentalsFilePart(e.key, e.value)
            ],
            idempotencyKey: key);
      } else if (item.method == 'PUT') {
        body = await _http.put(item.audience, path, body: fields);
      } else {
        body = await _http.post(item.audience, path,
            body: fields, idempotencyKey: key);
      }
      final serverId = body['id'];
      if (serverId is num) _results[item.id] = serverId.toInt();
      await _remove(item);
      await _commit();
      sent.value++;
      return SubmitSent(body);
    } on RentalsApiException catch (e) {
      if (e.isArchived) {
        await _remove(item);
        await _dropDependents(item.id);
        await _commit();
        final msg = '"${item.label}" was not sent: it was withdrawn or '
            'archived in the meantime.';
        notice.value = msg;
        return SubmitArchived(msg);
      }
      if (e.isTransient || e.statusCode == 401) {
        // 401: the session is being re-established; keep the item, back off.
        final wait = _backoff(item.attempts);
        item
          ..state = QueuedWriteState.pending
          ..error = e.message
          ..nextAttemptAt = DateTime.now().add(wait).millisecondsSinceEpoch;
        await _commit();
        _scheduleWake();
        return SubmitQueued(e.isNetwork
            ? 'Saved on this phone. It will send when you have signal.'
            : 'Saved on this phone. It will be tried again shortly.');
      }
      item
        ..state = QueuedWriteState.failed
        ..error = e.message;
      await _commit();
      return SubmitRefused(e);
    } catch (e) {
      final wait = _backoff(item.attempts);
      item
        ..state = QueuedWriteState.pending
        ..error = e.toString()
        ..nextAttemptAt = DateTime.now().add(wait).millisecondsSinceEpoch;
      await _commit();
      _scheduleWake();
      return const SubmitQueued('Saved on this phone. It will be tried again.');
    }
  }

  /// 5s, 10s, 20s … capped at [_maxBackoff], with jitter so a fleet of phones
  /// coming back into signal together doesn't arrive in lockstep.
  static Duration _backoff(int attempts) {
    final base = 5000 * pow(2, (attempts - 1).clamp(0, 10)).toInt();
    final capped = min(base, _maxBackoff.inMilliseconds);
    final jitter = Random().nextInt(max(1, capped ~/ 5));
    return Duration(milliseconds: capped + jitter);
  }
}
