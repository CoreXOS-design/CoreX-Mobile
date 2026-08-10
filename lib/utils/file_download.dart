import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/property_drive.dart' show splitFileName;

const MethodChannel _files = MethodChannel('corex/files');

/// Where a downloaded file landed, plus copy for the confirmation snackbar.
class SavedFile {
  /// Absolute path on disk, or empty when the file only exists as a MediaStore
  /// entry. Use [openSavedFile] rather than reading this directly.
  final String path;

  /// `content://` URI for files written through MediaStore. Null on iOS and on
  /// the plain-file fallback paths.
  final String? contentUri;

  /// Final name on disk, which may differ from the requested one when a file
  /// of that name was already there.
  final String fileName;

  /// Human-readable home for the file: "Downloads", "Files › CoreX OS", …
  /// Used in the snackbar so the agent knows where to look for it later.
  final String locationLabel;

  const SavedFile({
    required this.path,
    required this.fileName,
    required this.locationLabel,
    this.contentUri,
  });
}

/// Thrown when the bytes couldn't be written anywhere at all.
class FileSaveException implements Exception {
  final String message;
  const FileSaveException(this.message);
  @override
  String toString() => message;
}

/// Writes [bytes] to the device without asking the agent anything.
///
/// The point is that a download is a download: no save-as dialog, no file
/// manager, no picker. Where "the device" is differs by platform, so the
/// returned [SavedFile.locationLabel] carries the wording for the snackbar
/// rather than the caller guessing.
///
/// * Android — the public `Download` folder, the same place the browser puts
///   things. Falls back to the app's own external folder if scoped storage
///   refuses (Android 10 without legacy storage, odd OEM volume layouts).
/// * iOS — the app's Documents folder, which `UIFileSharingEnabled` in
///   Info.plist surfaces under Files › On My iPhone › CoreX OS. iOS has no
///   shared Downloads folder for apps to write into, so this is as close as
///   the sandbox allows.
///
/// [mimeType] is recorded on the MediaStore entry so other apps know what the
/// file is; it never decides whether the save succeeds.
Future<SavedFile> saveDownloadedFile({
  required Uint8List bytes,
  required String fileName,
  String? mimeType,
}) async {
  final name = _safeName(fileName);

  if (Platform.isAndroid) {
    // MediaStore first. A plain File write into /storage/emulated/0/Download
    // succeeds on Android 11+ but leaves no MediaStore row, and the Files and
    // Downloads apps list rows rather than directory contents — so the file is
    // saved and invisible, which reads to the user as a failed download.
    // Inserting through MediaStore indexes it on the way in and hands back a
    // content:// URI that ACTION_VIEW can open without any permission.
    final viaMediaStore = await _saveToDownloadsViaMediaStore(
      bytes: bytes,
      fileName: name,
      mimeType: mimeType,
    );
    if (viaMediaStore != null) return viaMediaStore;

    // Below API 29, or MediaStore refused: fall back to the plain write.
    final downloads = await _androidDownloads();
    if (downloads != null) {
      // Only this path may prompt: pre-Android-10 needs WRITE_EXTERNAL_STORAGE
      // to write outside the sandbox. Everywhere else is app-private.
      final file = await _write(downloads, name, bytes, mayAskPermission: true);
      if (file != null) {
        return SavedFile(
          path: file.path,
          fileName: _basename(file.path),
          locationLabel: 'Downloads',
        );
      }
    }
    final external = await getExternalStorageDirectory();
    if (external != null) {
      final file = await _write(external, name, bytes);
      if (file != null) {
        return SavedFile(
          path: file.path,
          fileName: _basename(file.path),
          locationLabel: 'the CoreX folder on this device',
        );
      }
    }
  }

  final documents = await getApplicationDocumentsDirectory();
  final file = await _write(documents, name, bytes);
  if (file == null) {
    throw const FileSaveException("Couldn't save that file to this device.");
  }
  return SavedFile(
    path: file.path,
    fileName: _basename(file.path),
    locationLabel: Platform.isIOS ? 'Files › On My iPhone › CoreX OS' : 'the app folder',
  );
}

/// Inserts the bytes into the public Downloads collection via MediaStore.
///
/// Null means "not done, use the fallback" rather than "failed": the platform
/// side answers null below API 29, where the collection doesn't exist, and on
/// any insert the resolver refuses. A genuine save error still throws.
Future<SavedFile?> _saveToDownloadsViaMediaStore({
  required Uint8List bytes,
  required String fileName,
  String? mimeType,
}) async {
  try {
    final result = await _files.invokeMapMethod<String, dynamic>(
      'saveToDownloads',
      {
        'bytes': bytes,
        'fileName': fileName,
        // A Content-Type can carry parameters (`application/pdf; charset=…`)
        // that MediaStore won't take as a MIME type.
        'mimeType': mimeType?.split(';').first.trim(),
      },
    );
    final uri = result?['uri'] as String?;
    if (uri == null || uri.isEmpty) return null;
    return SavedFile(
      path: '',
      contentUri: uri,
      fileName: (result?['fileName'] as String?) ?? fileName,
      locationLabel: 'Downloads',
    );
  } on PlatformException catch (e) {
    debugPrint('[download] MediaStore save failed: ${e.code} ${e.message}');
    return null;
  } on MissingPluginException {
    // Host doesn't carry the bridge (an older build, or a platform we don't
    // register it on) — the plain write below still works.
    return null;
  }
}

/// `(extension, mimeType)` read from the leading magic bytes.
///
/// Defaults to PNG when nothing matches: every caller so far is saving a
/// server-rendered PNG, and a wrong-but-plausible extension still lands in the
/// gallery, whereas an empty one doesn't get indexed at all.
({String ext, String mime}) imageFormatOf(Uint8List bytes) {
  bool startsWith(List<int> magic, [int offset = 0]) {
    if (bytes.length < offset + magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[offset + i] != magic[i]) return false;
    }
    return true;
  }

  if (startsWith([0x89, 0x50, 0x4E, 0x47])) return (ext: 'png', mime: 'image/png');
  if (startsWith([0xFF, 0xD8, 0xFF])) return (ext: 'jpg', mime: 'image/jpeg');
  if (startsWith([0x47, 0x49, 0x46])) return (ext: 'gif', mime: 'image/gif');
  // RIFF....WEBP
  if (startsWith([0x52, 0x49, 0x46, 0x46]) &&
      startsWith([0x57, 0x45, 0x42, 0x50], 8)) {
    return (ext: 'webp', mime: 'image/webp');
  }
  return (ext: 'png', mime: 'image/png');
}

/// Album subfolder under `Pictures/` that saved images go into.
///
/// Not cosmetic: OEM galleries build their album list from directories, and
/// several (Honor/Huawei especially) never show images written to the root of
/// `Pictures/`. A named folder is what makes the image appear at all.
const String galleryAlbum = 'CoreX';

/// Saves an image into the device gallery. Returns false when the platform
/// bridge isn't available, so the caller can fall back.
///
/// Android only — [fileName] must already carry its extension.
Future<bool> saveImageToGallery({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String album = galleryAlbum,
}) async {
  if (!Platform.isAndroid) return false;
  try {
    final uri = await _files.invokeMethod<String>(
      'saveToGallery',
      {
        'bytes': bytes,
        'fileName': fileName,
        'mimeType': mimeType,
        'album': album,
      },
    );
    return uri != null && uri.isNotEmpty;
  } on MissingPluginException {
    return false;
  }
}

/// Opens a file that [saveDownloadedFile] just wrote. False when nothing on the
/// device claims the type.
///
/// MediaStore-backed files go out as a `content://` URI with a per-intent read
/// grant, which needs no permission. Everything else falls to open_filex.
Future<bool> openSavedFile(SavedFile file, {String? mimeType}) async {
  final bare = mimeType?.split(';').first.trim();
  final uri = file.contentUri;

  if (Platform.isAndroid && uri != null) {
    try {
      final ok = await _files.invokeMethod<bool>(
        'openUri',
        {'uri': uri, 'mimeType': bare},
      );
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint('[download] open failed: ${e.code} ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  if (file.path.isEmpty) return false;
  final result = await OpenFilex.open(file.path, type: bare);
  return result.type == ResultType.done;
}

/// The public Downloads folder, or null when this device doesn't expose one.
///
/// The literal paths cover every mainstream device; the derivation below
/// catches OEMs that mount the primary volume somewhere else, by cutting the
/// app's own external path (`…/Android/data/<pkg>/files`) back to the volume
/// root.
Future<Directory?> _androidDownloads() async {
  for (final path in const [
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Downloads',
    '/sdcard/Download',
  ]) {
    final dir = Directory(path);
    if (await dir.exists()) return dir;
  }

  final external = await getExternalStorageDirectory();
  if (external != null) {
    final cut = external.path.indexOf('/Android/');
    if (cut > 0) {
      final dir = Directory('${external.path.substring(0, cut)}/Download');
      if (await dir.exists()) return dir;
    }
  }
  return null;
}

/// Writes into [dir], returning null rather than throwing so the caller can
/// fall through to the next-best location.
Future<File?> _write(
  Directory dir,
  String fileName,
  Uint8List bytes, {
  bool mayAskPermission = false,
}) async {
  try {
    return await _writeUnique(dir, fileName, bytes);
  } on FileSystemException {
    if (!mayAskPermission) return null;
    // On Android 13+ this maps to a permission that no longer exists and comes
    // back denied — so ask once, never loop, and let the caller fall back.
    final status = await Permission.storage.request();
    if (!status.isGranted) return null;
    try {
      return await _writeUnique(dir, fileName, bytes);
    } on FileSystemException {
      return null;
    }
  }
}

/// Never overwrites: a second download of `Mandate.pdf` becomes
/// `Mandate (1).pdf`, matching what a browser does.
Future<File> _writeUnique(
  Directory dir,
  String fileName,
  Uint8List bytes,
) async {
  if (!await dir.exists()) await dir.create(recursive: true);

  final parts = splitFileName(fileName);
  final suffix = parts.ext.isEmpty ? '' : '.${parts.ext}';
  var file = File('${dir.path}/$fileName');
  var n = 1;
  while (await file.exists()) {
    file = File('${dir.path}/${parts.base} ($n)$suffix');
    n++;
  }
  return file.writeAsBytes(bytes, flush: true);
}

/// Strips anything that would let a server-supplied filename escape the
/// directory we chose, or that the filesystem won't take.
String _safeName(String fileName) {
  final cleaned = fileName
      .replaceAll(RegExp(r'[\\/]+'), '_')
      .replaceAll(RegExp(r'[\x00-\x1f<>:"|?*]'), '')
      .replaceAll(RegExp(r'^\.+'), '')
      .trim();
  return cleaned.isEmpty ? 'download' : cleaned;
}

String _basename(String path) {
  final cut = path.lastIndexOf(Platform.pathSeparator);
  return cut < 0 ? path : path.substring(cut + 1);
}
