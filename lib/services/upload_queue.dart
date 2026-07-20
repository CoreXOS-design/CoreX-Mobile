import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// State of a queued photo. `uploading` is transient and lives only in the
/// UI — the persisted store only ever holds `pending` or `failed`.
enum PendingUploadState { pending, failed }

/// One photo waiting to upload to a property. The [path] points at a copy the
/// queue owns (under the app documents dir), not the volatile OS cache path
/// `image_picker` handed back — so the file survives app restarts.
class PendingUpload {
  final String id;
  final int propertyId;
  final String path;
  String? roomTag;
  PendingUploadState state;
  String? error;
  final int createdAt;

  PendingUpload({
    required this.id,
    required this.propertyId,
    required this.path,
    required this.roomTag,
    this.state = PendingUploadState.pending,
    this.error,
    required this.createdAt,
  });

  File get file => File(path);

  Map<String, dynamic> toJson() => {
        'id': id,
        'property_id': propertyId,
        'path': path,
        'room_tag': roomTag,
        'state': state.name,
        'error': error,
        'created_at': createdAt,
      };

  factory PendingUpload.fromJson(Map<String, dynamic> j) => PendingUpload(
        id: j['id'] as String,
        propertyId: (j['property_id'] as num).toInt(),
        path: j['path'] as String,
        roomTag: j['room_tag'] as String?,
        state: PendingUploadState.values.firstWhere(
          (s) => s.name == j['state'],
          orElse: () => PendingUploadState.pending,
        ),
        error: j['error'] as String?,
        createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
      );
}

/// Durable, cross-session queue of property photos waiting to upload.
///
/// Picked images live in the OS cache and can be evicted at any time; on
/// [enqueue] we copy the bytes into an app-owned directory so a queued or
/// failed photo survives the upload sheet closing, the app being backgrounded,
/// or a full restart. The lightweight metadata is mirrored into
/// SharedPreferences on every change.
///
/// Nothing here uploads on its own — the gallery sheet drains the queue while
/// it is open — but nothing is lost between sessions, so an interrupted batch
/// reappears and can be resumed later.
class UploadQueue {
  UploadQueue._();
  static final UploadQueue instance = UploadQueue._();

  static const String _prefsKey = 'property_upload_queue_v1';
  static const String _dirName = 'upload_queue';

  final List<PendingUpload> _items = [];
  bool _loaded = false;
  int _seq = 0;

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
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

  /// Copies [source] into durable storage and records it as pending.
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
      roomTag: roomTag,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _items.add(item);
    await _persist();
    return item;
  }

  Future<void> markFailed(String id, String error) async {
    await _ensureLoaded();
    final item = _find(id);
    if (item == null) return;
    item.state = PendingUploadState.failed;
    item.error = error;
    await _persist();
  }

  Future<void> markPending(String id) async {
    await _ensureLoaded();
    final item = _find(id);
    if (item == null) return;
    item.state = PendingUploadState.pending;
    item.error = null;
    await _persist();
  }

  Future<void> setRoomTag(String id, String? roomTag) async {
    await _ensureLoaded();
    final item = _find(id);
    if (item == null) return;
    item.roomTag = roomTag;
    await _persist();
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
    await _persist();
  }
}
