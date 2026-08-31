import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'image_upload.dart';

/// A photo on its way to the upload queue, plus whatever we know about how it
/// was captured.
///
/// [sensorRotation] is the only trustworthy fallback we have when a file's EXIF
/// `Orientation` tag is missing or invalid: it is the device's own report of how
/// far its camera sensor is mounted from upright, read from the `camera` plugin
/// at the moment of capture. It is set only for in-app captures — photos coming
/// from `image_picker` (OS camera app or gallery) carry no such reading, so it
/// stays null and we never guess.
class CapturedPhoto {
  final File file;

  /// Clockwise degrees the raw pixels must be rotated to sit upright, from the
  /// capture-time sensor reading. Null when unknown (all `image_picker` paths).
  final int? sensorRotation;

  /// The photo's identity for the whole pipeline: the server's idempotency
  /// key (`client_upload_id`) *and* the id every diagnostic event is filed
  /// under.
  ///
  /// Allocated **here**, at capture, rather than by the queue at enqueue time.
  /// That is the point: an id that only exists once a photo reaches the queue
  /// cannot describe a photo that never got there, and photos dying between
  /// the camera and the queue is the failure this pipeline could not see. From
  /// the shutter onwards the photo has a name, so its absence is a fact rather
  /// than an inference from a gap in a sequence.
  final String uploadId;

  CapturedPhoto(this.file, {this.sensorRotation, String? uploadId})
      : uploadId = uploadId ?? newUploadId();

  static int _idSeq = 0;

  /// Monotonic-per-session id. Same shape the queue has always generated, so
  /// keys from before and after this change sort and read alike.
  static String newUploadId() {
    _idSeq++;
    return '${DateTime.now().microsecondsSinceEpoch}_$_idSeq';
  }
}

/// How [processImageForUpload] decided which way is up.
enum PhotoOrientationSource {
  /// The file carried a valid EXIF `Orientation` (1-8). Pixels baked to match.
  exif,

  /// EXIF was absent or invalid, and the caller supplied a capture-time sensor
  /// reading, which we applied.
  sensor,

  /// EXIF was absent or invalid and no trusted fallback existed. Pixels were
  /// left alone AND the original (bad) tag was preserved, so the server keeps
  /// whatever signal it has. This is the case worth logging.
  unknown,
}

/// Outcome of a single [processImageForUpload] run.
class ImageProcessResult {
  /// False when the file couldn't be decoded/written — caller should upload the
  /// original rather than drop the photo.
  final bool ok;

  /// True when we declined to decode because the source exceeds
  /// [ImageUploadConfig.maxDecodePixels]. Distinct from a plain failure: the
  /// file is fine, we simply refused to spend the memory, and the original is
  /// uploaded for the server to normalise and downscale.
  final bool oversized;

  final PhotoOrientationSource source;

  /// The raw EXIF `Orientation` value as found, null when the tag was absent.
  /// Values outside 1-8 are the defect this file exists to absorb.
  final int? exifOrientation;

  /// Degrees clockwise actually baked into the pixels.
  final int appliedRotation;

  const ImageProcessResult({
    required this.ok,
    this.oversized = false,
    this.source = PhotoOrientationSource.unknown,
    this.exifOrientation,
    this.appliedRotation = 0,
  });

  static const failed = ImageProcessResult(ok: false);
  static const tooLarge = ImageProcessResult(ok: false, oversized: true);
}

/// Parameters for [processImageForUpload], sent to a background isolate.
class ImageProcessArgs {
  final String srcPath;
  final String destPath;
  final int maxEdge;
  final int quality;

  /// Clockwise degrees to apply when — and only when — the file's EXIF
  /// `Orientation` is absent or outside the valid 1-8 range. Null means "no
  /// trusted fallback"; the pixels and the bad tag are then both left as-is.
  final int? fallbackRotation;

  /// Refuse to decode a source larger than this many pixels. See
  /// [ImageUploadConfig.maxDecodePixels].
  final int maxDecodePixels;

  const ImageProcessArgs({
    required this.srcPath,
    required this.destPath,
    required this.maxEdge,
    required this.quality,
    required this.maxDecodePixels,
    this.fallbackRotation,
  });
}

/// Decodes [ImageProcessArgs.srcPath], **bakes the orientation into the
/// pixels**, downscales the longest edge to [ImageProcessArgs.maxEdge], and
/// writes an upright JPEG to [ImageProcessArgs.destPath].
///
/// Baking is the important part, and for this app's own camera it is the
/// *only* part.
///
/// The server runs `ImageOrientationNormalizer` at ingest and does rescue
/// EXIF-bearing files, so it is easy to assume it covers us. It does not. Its
/// device heuristic fires only on a known `Make`, an invalid or absent
/// `Orientation`, **and a portrait-shaped canvas** — and our shots arrive in a
/// 2560x1920 landscape buffer with no tag, which carries no information
/// distinguishing a rotated portrait from a real landscape. The server refuses
/// to guess there, correctly. Most of our files also carry no `Make` at all,
/// putting them out of reach of the heuristic entirely, and the normaliser is
/// JPEG-only, so a HEIC gets nothing.
///
/// [ImageProcessArgs.fallbackRotation] — the capture-time sensor reading — is
/// therefore the only thing standing between this camera and sideways photos.
///
/// Orientation is resolved in strict priority order:
///
///  1. **Valid EXIF (1-8)** — `img.decodeImage` already rotates the pixels for
///     these while decoding (see the note below); we just stamp the tag to 1 so
///     every downstream reader knows the pixels are correct and must not be
///     turned again.
///  2. **[ImageProcessArgs.fallbackRotation]** — used only when EXIF gives no
///     usable answer. This is the device's own sensor reading from an in-app
///     capture, not a guess.
///  3. **Neither** — leave the pixels alone and put the original bad tag back.
///     We do not guess a rotation from an absent tag, and we deliberately do not
///     stamp a "1" we can't stand behind, so the server keeps whatever signal it
///     has. [ImageProcessResult.source] reports this so the caller can log it.
///
/// NOTE ON READING THE TAG: the orientation must be read from the raw bytes with
/// [img.decodeJpgExif], never from the decoded image. `img.decodeImage` applies
/// orientation 2-8 itself while decoding and then *nulls the tag*, so a
/// post-decode read always reports "absent" — which would silently push every
/// well-behaved device down the fallback branch and rotate it a second time.
///
/// Runs the CPU-heavy decode/rotate/resize/encode in a background isolate via
/// [compute] so it never janks the UI.
Future<ImageProcessResult> processImageForUpload({
  required String srcPath,
  required String destPath,
  int maxEdge = 2560,
  int quality = 82,
  int? fallbackRotation,
  int maxDecodePixels = ImageUploadConfig.maxDecodePixels,
}) {
  return compute(
    _processImageInIsolate,
    ImageProcessArgs(
      srcPath: srcPath,
      destPath: destPath,
      maxEdge: maxEdge,
      quality: quality,
      maxDecodePixels: maxDecodePixels,
      fallbackRotation: fallbackRotation,
    ),
  );
}

/// Top-level entry point for [compute]. Must not touch Flutter/UI state.
ImageProcessResult _processImageInIsolate(ImageProcessArgs a) {
  try {
    final bytes = File(a.srcPath).readAsBytesSync();

    // Cheap header probe before committing to a full decode. The camera is
    // opened at the highest resolution the device will give us (to match the
    // aspect ratio and detail of a gallery pick), and on a few Android sensors
    // that is large enough that materialising it would be a memory-kill risk.
    // Reading the header costs a marker scan; decoding costs hundreds of MB.
    final info = img.findDecoderForData(bytes)?.startDecode(bytes);
    if (info != null && info.width * info.height > a.maxDecodePixels) {
      return ImageProcessResult.tooLarge;
    }

    // Read the tag from the raw bytes FIRST — decoding consumes it.
    final srcIfd = img.decodeJpgExif(bytes)?.imageIfd;
    final int? rawOrientation =
        (srcIfd != null && srcIfd.hasOrientation) ? srcIfd.orientation : null;
    // 1-8 are the only values the EXIF spec defines. The HUAWEI/HONOR defect
    // writes 0 (or nothing at all) onto pixels that genuinely need rotating, so
    // an out-of-range tag must be treated as "no information", never as 1.
    final validExif =
        rawOrientation != null && rawOrientation >= 1 && rawOrientation <= 8;

    final decoded = img.decodeImage(bytes);
    if (decoded == null) return ImageProcessResult.failed;

    img.Image image;
    PhotoOrientationSource source;
    var applied = 0;
    // The Orientation tag to write on the way out. Deliberately not applied
    // until after the resize: copyResize bakes — and then *nulls* — any tag
    // that isn't 1, which would silently discard the value the `unknown` branch
    // exists to hand back.
    int? finalOrientation;

    if (validExif) {
      // decodeImage already turned the pixels upright. Stamp the tag rather
      // than leave it absent, so an absent tag downstream unambiguously means
      // "nobody has vouched for these pixels".
      image = decoded;
      finalOrientation = 1;
      source = PhotoOrientationSource.exif;
      applied = _degreesForOrientation(rawOrientation);
    } else if (a.fallbackRotation != null) {
      final degrees = a.fallbackRotation! % 360;
      image = degrees == 0 ? decoded : img.copyRotate(decoded, angle: degrees);
      finalOrientation = 1;
      source = PhotoOrientationSource.sensor;
      applied = degrees;
    } else {
      // Nothing we can stand behind. Leave the pixels alone and put the
      // original tag back (the decoder nulls it) so the server still sees
      // whatever the device wrote and can apply its own safety net.
      image = decoded;
      finalOrientation = rawOrientation;
      source = PhotoOrientationSource.unknown;
    }

    // Downscale so the longest edge is at most [maxEdge]. copyResize keeps the
    // aspect ratio when only one dimension is given.
    final longest = image.width >= image.height ? image.width : image.height;
    if (longest > a.maxEdge) {
      image = image.width >= image.height
          ? img.copyResize(image, width: a.maxEdge)
          : img.copyResize(image, height: a.maxEdge);
    }

    image.exif.imageIfd.orientation = finalOrientation;
    // Make IFD0's own dimensions describe the frame we are about to write.
    // Rotating and resizing carry the source EXIF block through untouched, so
    // without this the file keeps declaring the size it had before we turned it
    // — the "EXIF says 1280x720, frame is 720x1280" contradiction that made the
    // sideways uploads impossible to reason about after the fact.
    image.exif.imageIfd.imageWidth = image.width;
    image.exif.imageIfd.imageHeight = image.height;

    File(a.destPath).writeAsBytesSync(img.encodeJpg(image, quality: a.quality));
    return ImageProcessResult(
      ok: true,
      source: source,
      exifOrientation: rawOrientation,
      appliedRotation: applied,
    );
  } catch (_) {
    return ImageProcessResult.failed;
  }
}

/// Clockwise degrees an EXIF orientation implies, for reporting only — the
/// mirrored values (2/4/5/7) also flip, which [img.bakeOrientation] handles.
int _degreesForOrientation(int orientation) => switch (orientation) {
      3 || 4 => 180,
      5 || 6 => 90,
      7 || 8 => 270,
      _ => 0,
    };

/// A photo that has been downscaled and turned upright, ready to upload.
class PreparedPhoto {
  final File file;

  /// True when [file] is a temp file we created; the caller must delete it once
  /// the bytes are safely elsewhere (durable queue or a completed upload).
  final bool isTemp;

  /// Null when processing failed and [file] is the untouched original.
  final ImageProcessResult? result;

  const PreparedPhoto({required this.file, required this.isTemp, this.result});
}

int _prepSeq = 0;

/// Downscales [photo] and bakes its orientation into the pixels, ready for
/// upload.
///
/// Every capture path goes through this. A photo that skips it and carries no
/// usable EXIF `Orientation` — everything the in-app camera produces — has
/// nothing left to tell the server which way is up and lands on its side; the
/// server's fallback heuristic needs a portrait-shaped canvas, and these
/// arrive landscape. A photo that skips it *with* good EXIF is fine: the
/// server normalises orientation at ingest and caps the long edge at the same
/// 2560px we do.
///
/// Never throws and never drops a photo: on any failure it returns the original
/// file with `isTemp: false`.
/// [destPath] overrides where the processed copy is written. Pass one when the
/// result must be durable — a photo queued at the shutter is baked *after* it
/// is already in the queue, so its processed bytes have to land in storage the
/// queue owns rather than in a temp file the OS may evict. Callers that pass it
/// own the file: [PreparedPhoto.isTemp] comes back false, because deleting it
/// would delete the photo.
Future<PreparedPhoto> prepareForUpload(
  CapturedPhoto photo, {
  String? destPath,
}) async {
  Directory? tmpDir;
  if (destPath == null) {
    try {
      tmpDir = await getTemporaryDirectory();
    } catch (_) {
      return PreparedPhoto(file: photo.file, isTemp: false);
    }
  }

  try {
    final dest = destPath ??
        '${tmpDir!.path}/corex_prep_'
            '${DateTime.now().microsecondsSinceEpoch}_${_prepSeq++}.jpg';
    final result = await processImageForUpload(
      srcPath: photo.file.path,
      destPath: dest,
      maxEdge: ImageUploadConfig.maxEdge,
      quality: ImageUploadConfig.quality,
      fallbackRotation: photo.sensorRotation,
    );
    if (result.oversized) {
      // Deliberate, not a failure: hand the original over and let the server's
      // ImageOrientationNormalizer bake the EXIF and PropertyImageStorer cap it
      // at the same 2560px. Costs uplink on this one photo; the alternative was
      // several hundred MB of decode on the phone.
      debugPrint(
        'Image processing: source exceeds the decode budget — uploading the '
        'original for the server to normalise (${photo.file.path})',
      );
      return PreparedPhoto(file: photo.file, isTemp: false);
    }
    if (!result.ok) return PreparedPhoto(file: photo.file, isTemp: false);

    if (result.source == PhotoOrientationSource.unknown) {
      // Same discipline as the server's "left as-is" warning: a device that
      // writes neither a valid tag nor reaches us through the in-app camera
      // can still upload sideways, and that must not go unnoticed again.
      debugPrint(
        'Image orientation: EXIF tag ${result.exifOrientation ?? 'absent'} is '
        'not usable and no capture-time sensor reading was available — pixels '
        'left as-is, photo may upload sideways (${photo.file.path})',
      );
    }
    return PreparedPhoto(
        file: File(dest), isTemp: destPath == null, result: result);
  } catch (_) {
    return PreparedPhoto(file: photo.file, isTemp: false);
  }
}
