import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// State of a queued photo.
///
/// `uploading` is transient — it exists so the gallery can badge the photo
/// currently on the wire. It is never written to the store: a process killed
/// mid-request must come back as `pending`, not stuck forever in a state
/// nothing will ever move it out of.
enum PendingUploadState { pending, uploading, failed }

/// One photo waiting to upload to a property, and the **complete intent** for
/// that upload.
///
/// This is the record the drainer replays verbatim. Everything the POST needs
/// lives here — the file, the property, the idempotency key and the room the
/// agent had selected when they took the shot — precisely so that nothing at
/// flush time has to reach out to a screen to reconstruct it. A queued upload
/// that replays without its [roomTag] was the 2026-08-28 incident: 27 photos
/// landed on the server with `room_tag` absent because the tag lived only in
/// the upload sheet's state, and the sheet had moved on.
///
/// [path] points at a copy the queue owns (under Application Support), not the
/// volatile OS cache path `image_picker` handed back, so the bytes survive an
/// app restart. [roomTag] gets the same durability, because a tag that outlives
/// only the current screen is not a tag at all.
class PendingUpload {
  /// Stable per-photo id. Doubles as the persisted key.
  final String id;

  final int propertyId;
  final String path;

  /// Idempotency key sent as `client_upload_id`. Persisted in its own right
  /// rather than derived from [id] at send time, so a replay after a restart
  /// presents the *same* key the first attempt did and the server can dedupe.
  final String clientUploadId;

  /// The room the agent had selected when this photo was queued. `null` means
  /// "upload untagged" — a deliberate choice, not a missing value.
  ///
  /// Mutable only through [UploadQueue.setRoomTag], and only ever from an
  /// explicit agent action (re-filing a photo whose room no longer exists).
  /// The drainer never writes it.
  String? roomTag;

  PendingUploadState state;
  String? error;
  final int createdAt;

  /// Upload attempts made so far, across sessions. Surfaced so a photo that
  /// has been failing all morning reads differently from one that just landed
  /// in the queue.
  int attempts;

  PendingUpload({
    required this.id,
    required this.propertyId,
    required this.path,
    required this.clientUploadId,
    required this.roomTag,
    this.state = PendingUploadState.pending,
    this.error,
    required this.createdAt,
    this.attempts = 0,
  });

  File get file => File(path);

  Map<String, dynamic> toJson() => {
        'id': id,
        'property_id': propertyId,
        'path': path,
        'client_upload_id': clientUploadId,
        'room_tag': roomTag,
        // `uploading` is in-flight only; persist it as pending so a kill
        // mid-request leaves a photo the drainer will pick up again.
        'state': (state == PendingUploadState.failed ? 'failed' : 'pending'),
        'error': error,
        'created_at': createdAt,
        'attempts': attempts,
      };

  factory PendingUpload.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String;
    return PendingUpload(
      id: id,
      propertyId: (j['property_id'] as num).toInt(),
      path: j['path'] as String,
      // Items written before the key was persisted separately used the id as
      // the idempotency key, so that is the correct migration value: a photo
      // queued by the old build and replayed by this one still dedupes.
      clientUploadId: (j['client_upload_id'] as String?) ?? id,
      roomTag: j['room_tag'] as String?,
      state: j['state'] == 'failed'
          ? PendingUploadState.failed
          : PendingUploadState.pending,
      error: j['error'] as String?,
      createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
      attempts: (j['attempts'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Durable, cross-session queue of property photos waiting to upload.
///
/// Picked images live in the OS cache and can be evicted at any time; on
/// [enqueue] we copy the bytes into an app-owned directory so a queued or
/// failed photo survives the upload sheet closing, the app being backgrounded,
/// or a full restart. The metadata — including the room tag — is mirrored into
/// SharedPreferences on every change.
///
/// Nothing here uploads: draining is [UploadService]'s job. The queue's only
/// contract is that what goes in comes back out unchanged, however long that
/// takes and however many times the app is killed in between.
///
/// It is a [ChangeNotifier] so the gallery can render pending photos and their
/// badges without polling — the count an agent sees has to match the count they
/// shot, and it can only do that if the queue says when it changes.
class UploadQueue extends ChangeNotifier {
  UploadQueue._();
  static final UploadQueue instance = UploadQueue._();

  static const String _prefsKey = 'property_upload_queue_v1';
  static const String _dirName = 'upload_queue';

  final List<PendingUpload> _items = [];
  Future<void>? _loading;
  int _seq = 0;

  /// Application Support, not Documents.
  ///
  /// Info.plist sets `UIFileSharingEnabled` so downloaded files show up under
  /// Files › On My iPhone › CoreX OS. That exposes the *whole* Documents tree,
  /// and this queue is internal plumbing: agents would see an `upload_queue`
  /// folder of raw property photos and could delete one mid-flight. Application
  /// Support is excluded from file sharing, so the queue stays private while
  /// downloads stay visible.
  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Loads the store once, and — importantly — makes concurrent callers await
  /// the *same* load.
  ///
  /// The drainer and the upload sheet both hit the queue on startup, often in
  /// the same frame. A plain `if (_loaded) return; _loaded = true;` latch lets
  /// the second caller sail past the `await` and observe an empty queue, which
  /// on a foreground flush reads as "nothing to upload" for a queue that is
  /// actually full. Memoising the future removes the window entirely.
  Future<void> _ensureLoaded() {
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final e in decoded) {
        if (e is Map) {
          final item = PendingUpload.fromJson(Map<String, dynamic>.from(e));
          // Drop metadata whose backing file has vanished (e.g. the user
          // cleared app storage) rather than showing a broken thumbnail.
          if (await item.file.exists()) {
            _items.add(item);
          }
        }
      }
    } catch (_) {
      // Corrupt store — start clean rather than break the upload sheet.
      _items.clear();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(_items.map((e) => e.toJson()).toList()),
      );
    } catch (_) {
      // Best-effort; a failed metadata write just means this change isn't
      // durable, not that the in-memory queue is wrong.
    }
  }

  /// Persist, then tell the UI. Every mutation goes through here so no caller
  /// can change the queue without the gallery's count following it.
  Future<void> _commit() async {
    await _persist();
    notifyListeners();
  }

  String _nextId() {
    _seq++;
    return '${DateTime.now().microsecondsSinceEpoch}_$_seq';
  }

  PendingUpload? _find(String id) {
    for (final e in _items) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Items for [propertyId], oldest first. Returns the live instances, so
  /// callers can mutate state through the mark* methods and see it reflected.
  Future<List<PendingUpload>> itemsFor(int propertyId) async {
    await _ensureLoaded();
    return _items.where((e) => e.propertyId == propertyId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Every queued item across all properties, oldest first — what the drainer
  /// works through. Agents shoot one property then drive to the next, so a
  /// flush that only ever looked at the property currently on screen would
  /// strand the previous one indefinitely.
  Future<List<PendingUpload>> allItems() async {
    await _ensureLoaded();
    return List<PendingUpload>.from(_items)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Synchronous view for `build` methods, which cannot await. Empty until the
  /// first [itemsFor] / [allItems] has loaded the store; [notifyListeners]
  /// rebuilds the UI when it does.
  List<PendingUpload> cachedItemsFor(int propertyId) =>
      _items.where((e) => e.propertyId == propertyId).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// Copies [source] into durable storage and records the full upload intent.
  ///
  /// [roomTag] is captured here, at queue time, from the selection that was
  /// live when the photo was taken — and is never recomputed afterwards.
  Future<PendingUpload> enqueue({
    required int propertyId,
    required File source,
    required String? roomTag,
  }) async {
    await _ensureLoaded();
    final id = _nextId();
    final dir = await _dir();
    final dot = source.path.lastIndexOf('.');
    final ext = dot >= 0 ? source.path.substring(dot) : '.jpg';
    final dest = File('${dir.path}/$id$ext');
    await source.copy(dest.path);
    final item = PendingUpload(
      id: id,
      propertyId: propertyId,
      path: dest.path,
      clientUploadId: id,
      roomTag: roomTag,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _items.add(item);
    await _commit();
    return item;
  }

  /// Marks [id] as on the wire. In-memory only — see [PendingUploadState].
  Future<void> markUploading(String id) async {
    await _ensureLoaded();
    final item = _find(id);
    if (item == null) return;
    item.state = PendingUploadState.uploading;
    item.attempts++;
    notifyListeners();
  }

  Future<void> markFailed(String id, String error) async {
    await _ensureLoaded();
    final item = _find(id);
    if (item == null) return;
    item.state = PendingUploadState.failed;
    item.error = error;
    await _commit();
  }

  Future<void> markPending(String id) async {
    await _ensureLoaded();
    final item = _find(id);
    if (item == null) return;
    item.state = PendingUploadState.pending;
    item.error = null;
    await _commit();
  }

  /// Re-files a queued photo under a different room.
  ///
  /// The *only* sanctioned write to [PendingUpload.roomTag] after enqueue, and
  /// it exists for one case: a photo queued under a tag the property no longer
  /// offers, which can never upload as-is. It must stay an explicit,
  /// per-photo agent action — a bulk rewrite driven by whatever chip happens to
  /// be selected is exactly how a batch ends up filed under the wrong room, or
  /// under none.
  Future<void> setRoomTag(String id, String? roomTag) async {
    await _ensureLoaded();
    final item = _find(id);
    if (item == null) return;
    item.roomTag = roomTag;
    await _commit();
  }

  /// Removes an item and deletes its backing file. Called on success (the
  /// photo made it to the server) or when the user discards it.
  Future<void> remove(String id) async {
    await _ensureLoaded();
    final item = _find(id);
    if (item == null) return;
    _items.remove(item);
    try {
      if (await item.file.exists()) await item.file.delete();
    } catch (_) {}
    await _commit();
  }
}
