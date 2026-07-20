import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Parameters for [processImageForUpload], sent to a background isolate.
class ImageProcessArgs {
  final String srcPath;
  final String destPath;
  final int maxEdge;
  final int quality;
  const ImageProcessArgs({
    required this.srcPath,
    required this.destPath,
    required this.maxEdge,
    required this.quality,
  });
}

/// Decodes [ImageProcessArgs.srcPath], **bakes the EXIF orientation into the
/// pixels**, downscales the longest edge to [ImageProcessArgs.maxEdge], and
/// writes a normal-orientation JPEG to [ImageProcessArgs.destPath].
///
/// Baking is the important part: the server re-encodes thumbnails and drops any
/// EXIF Orientation flag, so a JPEG whose pixels are unrotated but rely on that
/// flag renders sideways on the web. We physically rotate the pixels and emit a
/// JPEG with no orientation flag (i.e. orientation = 1 / normal).
///
/// Returns `true` on success. On any failure (e.g. an undecodable format such
/// as an iOS HEIC the picker didn't transcode) it returns `false` so the caller
/// can fall back to uploading the original rather than dropping the photo.
///
/// Runs the CPU-heavy decode/resize/encode in a background isolate via
/// [compute] so it never janks the UI.
Future<bool> processImageForUpload({
  required String srcPath,
  required String destPath,
  int maxEdge = 2560,
  int quality = 82,
}) {
  return compute(
    _processImageInIsolate,
    ImageProcessArgs(
      srcPath: srcPath,
      destPath: destPath,
      maxEdge: maxEdge,
      quality: quality,
    ),
  );
}

/// Top-level entry point for [compute]. Must not touch Flutter/UI state.
bool _processImageInIsolate(ImageProcessArgs a) {
  try {
    final bytes = File(a.srcPath).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return false;

    // Rotate pixels to match the EXIF orientation, then the result carries no
    // orientation flag — upright regardless of what the server does.
    var image = img.bakeOrientation(decoded);

    // Downscale so the longest edge is at most [maxEdge]. copyResize keeps the
    // aspect ratio when only one dimension is given.
    final longest = image.width >= image.height ? image.width : image.height;
    if (longest > a.maxEdge) {
      image = image.width >= image.height
          ? img.copyResize(image, width: a.maxEdge)
          : img.copyResize(image, height: a.maxEdge);
    }

    File(a.destPath).writeAsBytesSync(img.encodeJpg(image, quality: a.quality));
    return true;
  } catch (_) {
    return false;
  }
}
