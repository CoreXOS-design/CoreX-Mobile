import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final src = img.decodePng(File('assets/images/corex_logo.png').readAsBytesSync())!;
  // Create a canvas where the logo occupies ~50% (so splash shows it smaller).
  final size = (src.width / 0.3).round();
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  // Transparent background
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
  final dx = ((size - src.width) / 2).round();
  final dy = ((size - src.height) / 2).round();
  img.compositeImage(canvas, src, dstX: dx, dstY: dy);
  File('assets/images/corex_logo_splash.png')
      .writeAsBytesSync(img.encodePng(canvas));
  print('Wrote ${size}x$size splash with logo at ${src.width}x${src.height}');
}
