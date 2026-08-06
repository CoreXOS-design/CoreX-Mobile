import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/property_drive.dart' show splitFileName;

/// Where a downloaded file landed, plus copy for the confirmation snackbar.
class SavedFile {
  /// Absolute path on disk — hand this to the "Open" action.
  final String path;

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
Future<SavedFile> saveDownloadedFile({
  required Uint8List bytes,
  required String fileName,
}) async {
  final name = _safeName(fileName);

  if (Platform.isAndroid) {
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
