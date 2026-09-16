import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import 'image_cache.dart';

/// Marker prefix of the one-line cache self-test printed after the first
/// frame. The Codemagic simulator smoke step greps the launch log for it, so
/// the two must stay in step — see [ImageCacheDiagnostics.logStartupSelfTest].
const String kImageCacheMarker = 'COREX_IMAGE_CACHE';

/// A point-in-time look at the photo cache, gathered by
/// [ImageCacheDiagnostics.inspect]. Everything is best-effort: a field that
/// couldn't be read is reported as absent/zero and the reason lands in [error]
/// rather than throwing, because this is read from Settings and from app
/// start, and neither may fail over a diagnostics probe.
class ImageCacheReport {
  final String fileDir;
  final bool fileDirExists;

  /// Across every store — thumbnails plus full-size.
  final int fileCount;
  final int fileBytes;

  /// The full-size store alone (`CoreXImageCache.fullKey`). Bounded by
  /// [CoreXImageCache.fullObjectCap]; if this is what's big, someone has been
  /// opening a lot of photos full-screen, which is fine and self-limiting.
  final int fullFileCount;
  final int fullFileBytes;
  final String dbPath;
  final bool dbExists;
  final int dbBytes;
  final bool tempWritable;
  final int memImages;
  final int memBytes;
  final int memMaxBytes;
  final List<String> recentFailures;
  final String? error;

  const ImageCacheReport({
    required this.fileDir,
    required this.fileDirExists,
    required this.fileCount,
    required this.fileBytes,
    this.fullFileCount = 0,
    this.fullFileBytes = 0,
    required this.dbPath,
    required this.dbExists,
    required this.dbBytes,
    required this.tempWritable,
    required this.memImages,
    required this.memBytes,
    required this.memMaxBytes,
    required this.recentFailures,
    this.error,
  });

  bool get healthy =>
      error == null && tempWritable && (fileCount == 0 || fileDirExists);

  String get summary => '$fileCount files · ${formatBytes(fileBytes)}';

  /// Single greppable line, key=value so it survives log tooling and can be
  /// pasted back from a TestFlight tester's clipboard.
  String toLogLine() => '$kImageCacheMarker '
      'ok=$healthy files=$fileCount bytes=$fileBytes '
      'full_files=$fullFileCount full_bytes=$fullFileBytes '
      'dir_exists=$fileDirExists '
      'writable=$tempWritable db_exists=$dbExists db_bytes=$dbBytes '
      'mem_images=$memImages mem_bytes=$memBytes mem_max=$memMaxBytes '
      'failures=${recentFailures.length} '
      'os=${Platform.operatingSystem} ${Platform.operatingSystemVersion} '
      'dir=$fileDir db=$dbPath'
      '${error == null ? '' : ' error=${jsonSafe(error!)}'}';

  static String formatBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String jsonSafe(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
}

/// Read-side visibility into `cached_network_image` / `flutter_cache_manager`
/// on the device this build is actually running on.
///
/// The cache is only ever exercised here on an Android emulator; iOS builds
/// come out of Codemagic. This is the substitute for attaching a debugger to
/// an iPhone: the startup line proves the storage plumbing (path_provider,
/// sqflite, a writable temp dir) works on that OS, and the Settings tile
/// shows a tester whether photos are really landing on disk and which URLs
/// failed to load.
class ImageCacheDiagnostics {
  ImageCacheDiagnostics._();

  static const int _maxFailures = 20;
  static final List<String> _failures = [];

  /// Newest first, capped at [_maxFailures]. Fed by [recordFailure] from every
  /// `CachedNetworkImage.errorListener` in the app.
  static List<String> get recentFailures => List.unmodifiable(_failures);

  static void recordFailure(String url, Object error) {
    final name = url.split('/').last;
    final when = DateTime.now().toIso8601String().substring(11, 19);
    _failures.insert(0, '$when $name — ${_shortError(error)}');
    if (_failures.length > _maxFailures) _failures.removeLast();
    if (kDebugMode) debugPrint('[imageCache] load failed: $name — $error');
  }

  static String _shortError(Object e) {
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }

  static Future<ImageCacheReport> inspect() async {
    String fileDir = '?';
    String dbPath = '?';
    var fileDirExists = false;
    var fileCount = 0;
    var fileBytes = 0;
    var fullFileCount = 0;
    var fullFileBytes = 0;
    var dbExists = false;
    var dbBytes = 0;
    var tempWritable = false;
    String? error;

    try {
      final temp = await getTemporaryDirectory();
      fileDir = '${temp.path}/${CoreXImageCache.key}';
      fileDirExists = await Directory(fileDir).exists();
      // Both stores: thumbnails (the working set) and the small full-size
      // one, reported separately so a tester can see which is growing.
      for (final k in CoreXImageCache.keys) {
        final dir = Directory('${temp.path}/$k');
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(recursive: true)) {
          if (entity is! File) continue;
          int len;
          try {
            len = await entity.length();
          } catch (_) {
            len = 0;
          }
          fileCount++;
          fileBytes += len;
          if (k == CoreXImageCache.fullKey) {
            fullFileCount++;
            fullFileBytes += len;
          }
        }
      }

      final probe = File('${temp.path}/corex_cache_probe.tmp');
      try {
        await probe.writeAsString('ok', flush: true);
        tempWritable = await probe.readAsString() == 'ok';
      } finally {
        try {
          if (await probe.exists()) await probe.delete();
        } catch (_) {}
      }
    } catch (e) {
      error = 'temp: $e';
    }

    try {
      final support = await getApplicationSupportDirectory();
      dbPath = '${support.path}/${CoreXImageCache.key}.db';
      final db = File(dbPath);
      dbExists = await db.exists();
      if (dbExists) dbBytes = await db.length();
    } catch (e) {
      error = error == null ? 'support: $e' : '$error; support: $e';
    }

    final mem = PaintingBinding.instance.imageCache;
    return ImageCacheReport(
      fileDir: fileDir,
      fileDirExists: fileDirExists,
      fileCount: fileCount,
      fileBytes: fileBytes,
      fullFileCount: fullFileCount,
      fullFileBytes: fullFileBytes,
      dbPath: dbPath,
      dbExists: dbExists,
      dbBytes: dbBytes,
      tempWritable: tempWritable,
      memImages: mem.currentSize,
      memBytes: mem.currentSizeBytes,
      memMaxBytes: mem.maximumSizeBytes,
      recentFailures: recentFailures,
      error: error,
    );
  }

  /// Drops every cached photo file, its index, and the in-memory decoded
  /// images. The next gallery open re-downloads — that's the point when a
  /// tester wants to see the cache fill from empty.
  static Future<void> clear() async {
    await CoreXImageCache.clear();
    final mem = PaintingBinding.instance.imageCache;
    mem.clear();
    mem.clearLiveImages();
    _failures.clear();
  }

  /// Prints [ImageCacheReport.toLogLine] once. Runs in every build mode —
  /// it's one line and the file walk is bounded by the cache's own object
  /// cap — and never throws, since it runs from the post-first-frame callback
  /// where an exception would read as a failed launch.
  static Future<void> logStartupSelfTest() async {
    try {
      final report = await inspect();
      debugPrint(report.toLogLine());
    } catch (e) {
      debugPrint(
          '$kImageCacheMarker ok=false error=${ImageCacheReport.jsonSafe('$e')}');
    }
  }
}
