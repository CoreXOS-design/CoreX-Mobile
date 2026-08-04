import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:corex_mobile/utils/image_processing.dart';

/// Orientation normalisation at capture time.
///
/// The production defect: HUAWEI/HONOR handsets write an EXIF `Orientation` of
/// `0` (outside the valid 1-8 range) — or omit the tag entirely — over a pixel
/// buffer that is still in the sensor's sideways orientation. The server's
/// thumbnailer drops EXIF without rotating, so anything relying on the tag
/// lands sideways on the web.
///
/// These tests build that exact file shape synthetically, then assert both that
/// it gets corrected when we have a trustworthy signal AND that devices which
/// were never broken are not double-rotated.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('corex_orient'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// A 64x32 landscape JPEG: left half red, right half blue. Rotating it 90°
  /// clockwise must put red on top and blue on the bottom of a 32x64 portrait
  /// image — which is what makes the rotation *direction* observable, not just
  /// the fact that some rotation happened.
  ///
  /// [orientation] is written verbatim, including the invalid `0`; pass null to
  /// omit the tag the way the HONOR handset does. A `Make` tag is always
  /// written so the fixture carries a real EXIF block like a camera file would.
  String writeSideways(String name, {int? orientation}) {
    final image = img.Image(width: 64, height: 32);
    for (final p in image) {
      if (p.x < 32) {
        p.setRgb(220, 20, 20);
      } else {
        p.setRgb(20, 20, 220);
      }
    }
    image.exif.imageIfd.make = 'HUAWEI';
    if (orientation != null) {
      image.exif.imageIfd.orientation = orientation;
    }
    final path = '${tmp.path}/$name';
    File(path).writeAsBytesSync(img.encodeJpg(image, quality: 95));
    return path;
  }

  img.Image decode(String path) =>
      img.decodeImage(File(path).readAsBytesSync())!;

  /// The written file's orientation tag. Must come from the raw bytes —
  /// `decodeImage` nulls the tag as it decodes.
  int? writtenOrientation(String path) =>
      img.decodeJpgExif(File(path).readAsBytesSync())?.imageIfd.orientation;

  /// JPEG is lossy, so compare by dominant channel rather than exact RGB.
  void expectRedAt(img.Image i, int x, int y, {required bool red}) {
    final p = i.getPixel(x, y);
    final label = red ? 'red' : 'blue';
    expect(
      red ? p.r > p.b : p.b > p.r,
      isTrue,
      reason: 'expected $label at ($x,$y), got r=${p.r} g=${p.g} b=${p.b}',
    );
  }

  /// Red on top / blue on bottom in a portrait frame — the corrected result.
  void expectUpright(img.Image i) {
    expect(i.width, 32);
    expect(i.height, 64);
    expectRedAt(i, 16, 8, red: true);
    expectRedAt(i, 16, 56, red: false);
  }

  test('the fixtures reproduce the defect: a valid tag is honoured on decode, '
      'an invalid 0 is not', () {
    // Guards the premise of every test below. `img.decodeImage` rotates for a
    // valid tag all by itself and then clears it, which is why the pipeline
    // reads orientation from the raw bytes instead of the decoded image.
    final valid = File(writeSideways('v.jpg', orientation: 6)).readAsBytesSync();
    expect(img.decodeJpgExif(valid)!.imageIfd.orientation, 6);
    expect(img.decodeImage(valid)!.width, 32, reason: 'decoder rotated it');

    final broken = File(writeSideways('b.jpg', orientation: 0)).readAsBytesSync();
    expect(img.decodeJpgExif(broken)!.imageIfd.orientation, 0);
    expect(img.decodeImage(broken)!.width, 64,
        reason: 'nothing rotates it — this is the production defect');
  });

  group('the HUAWEI/HONOR defect', () {
    test('invalid Orientation 0 is corrected by the sensor reading', () async {
      final src = writeSideways('huawei.jpg', orientation: 0);
      final dest = '${tmp.path}/out.jpg';

      final result = await processImageForUpload(
        srcPath: src,
        destPath: dest,
        maxEdge: 512,
        fallbackRotation: 90,
      );

      expect(result.ok, isTrue);
      expect(result.source, PhotoOrientationSource.sensor);
      expect(result.exifOrientation, 0);
      expect(result.appliedRotation, 90);

      expectUpright(decode(dest));
      // Stamped upright so nothing downstream rotates it a second time.
      expect(writtenOrientation(dest), 1);
    });

    test('a missing Orientation tag is corrected by the sensor reading',
        () async {
      final src = writeSideways('honor.jpg');
      final dest = '${tmp.path}/out.jpg';

      final result = await processImageForUpload(
        srcPath: src,
        destPath: dest,
        maxEdge: 512,
        fallbackRotation: 90,
      );

      expect(result.ok, isTrue);
      expect(result.source, PhotoOrientationSource.sensor);
      expect(result.exifOrientation, isNull);
      expectUpright(decode(dest));
    });

    test('without a trustworthy signal the pixels and the bad tag are left '
        'alone, so the server keeps whatever signal it has', () async {
      final src = writeSideways('unknown.jpg', orientation: 0);
      final dest = '${tmp.path}/out.jpg';

      final result = await processImageForUpload(
        srcPath: src,
        destPath: dest,
        maxEdge: 512,
      );

      expect(result.ok, isTrue);
      expect(result.source, PhotoOrientationSource.unknown);
      expect(result.appliedRotation, 0);

      final out = decode(dest);
      expect(out.width, 64);
      expect(out.height, 32);
      // Crucially NOT stamped to 1 — we must not tell the server these pixels
      // are upright when we could not verify it.
      expect(writtenOrientation(dest), 0);
    });
  });

  group('devices that were never broken', () {
    test('a valid Orientation 6 is baked, not double-rotated', () async {
      final src = writeSideways('iphone.jpg', orientation: 6);
      final dest = '${tmp.path}/out.jpg';

      final result = await processImageForUpload(
        srcPath: src,
        destPath: dest,
        maxEdge: 512,
        // A sensor reading is present but must be ignored: valid EXIF wins.
        fallbackRotation: 180,
      );

      expect(result.ok, isTrue);
      expect(result.source, PhotoOrientationSource.exif);
      expect(result.appliedRotation, 90);

      expectUpright(decode(dest));
      expect(writtenOrientation(dest), 1);
    });

    test('Orientation 1 is left as-is', () async {
      final src = writeSideways('samsung.jpg', orientation: 1);
      final dest = '${tmp.path}/out.jpg';

      final result = await processImageForUpload(
        srcPath: src,
        destPath: dest,
        maxEdge: 512,
        fallbackRotation: 90,
      );

      expect(result.ok, isTrue);
      expect(result.source, PhotoOrientationSource.exif);
      expect(result.appliedRotation, 0);

      final out = decode(dest);
      expect(out.width, 64);
      expect(out.height, 32);
      expectRedAt(out, 8, 16, red: true);
      expectRedAt(out, 56, 16, red: false);
    });
  });

  test('downscaling still applies, measured after rotation', () async {
    final image = img.Image(width: 800, height: 400);
    for (final p in image) {
      p.setRgb(10, 200, 10);
    }
    image.exif.imageIfd.orientation = 0;
    final src = '${tmp.path}/big.jpg';
    File(src).writeAsBytesSync(img.encodeJpg(image, quality: 90));
    final dest = '${tmp.path}/out.jpg';

    final result = await processImageForUpload(
      srcPath: src,
      destPath: dest,
      maxEdge: 200,
      fallbackRotation: 90,
    );

    expect(result.ok, isTrue);
    final out = decode(dest);
    expect(out.width, 100);
    expect(out.height, 200);
  });

  test('an undecodable file reports failure so the caller uploads the original',
      () async {
    final src = '${tmp.path}/not-an-image.jpg';
    File(src).writeAsStringSync('this is not a JPEG');

    final result = await processImageForUpload(
      srcPath: src,
      destPath: '${tmp.path}/out.jpg',
    );

    expect(result.ok, isFalse);
  });
}
