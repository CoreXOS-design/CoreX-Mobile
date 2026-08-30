import 'dart:io';

import 'package:flutter/services.dart';

/// One reading of how the phone is physically being held.
class DeviceRotationReading {
  /// The orientation in the `camera` plugin's own convention — the value to
  /// hand to `CameraController.lockCaptureOrientation`.
  final DeviceOrientation orientation;

  /// Clockwise degrees the device is turned from its natural position
  /// (0/90/180/270), in `OrientationEventListener` terms. This is the
  /// `deviceOrientation` term of Android's JPEG-orientation formula,
  /// `(sensorOrientation + deviceOrientation) % 360` for a back camera.
  final int degreesClockwise;

  const DeviceRotationReading({
    required this.orientation,
    required this.degreesClockwise,
  });
}

/// The accelerometer's view of which way up the phone is, on Android.
///
/// The `camera` plugin cannot answer this while a screen pins the UI to
/// portrait. Its Android device orientation is derived from
/// `Configuration.orientation` and `Display.getRotation()`, both frozen by that
/// lock, so it reports portraitUp however the phone is held — and writes every
/// landscape shot as a landscape scene turned 90 degrees into a portrait frame,
/// stamped EXIF Orientation 1. Unlocking the capture orientation does not help
/// either: `takePicture` then targets `getDefaultDisplayRotation()`, which the
/// same lock holds at 0.
///
/// iOS needs none of this — camera_avfoundation reads
/// `UIDevice.current.orientation`, which follows the hardware regardless of the
/// interface lock — so every call here is a no-op off Android.
class DeviceRotation {
  DeviceRotation._();

  static const MethodChannel _channel = MethodChannel('corex/device_rotation');

  /// Begins listening to the accelerometer. Cheap, but not free — pair every
  /// call with [stop].
  static Future<void> start() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('start');
    } catch (_) {
      // Bridge missing or sensor unavailable; [read] will report "don't know".
    }
  }

  /// Stops listening.
  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {/* nothing to release */}
  }

  /// The current reading, or null when we genuinely cannot say — the sensor has
  /// never reported (the device has been lying flat since the screen opened),
  /// or the bridge is unavailable.
  ///
  /// The bridge keeps the last real reading across a [stop]/[start] cycle, so
  /// null narrows to "we have never once known", not "we don't know right now".
  ///
  /// Null means "unknown" and must never be treated as "upright": that
  /// substitution is the whole bug this exists to end.
  static Future<DeviceRotationReading?> read() async {
    if (!Platform.isAndroid) return null;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('read');
      if (raw == null) return null;
      final degrees = raw['rotation'];
      final name = raw['orientation'];
      if (degrees is! int || name is! String) return null;
      final orientation = _orientationFor(name);
      if (orientation == null) return null;
      return DeviceRotationReading(
        orientation: orientation,
        degreesClockwise: degrees,
      );
    } catch (_) {
      return null;
    }
  }

  static DeviceOrientation? _orientationFor(String name) => switch (name) {
        'portraitUp' => DeviceOrientation.portraitUp,
        'portraitDown' => DeviceOrientation.portraitDown,
        'landscapeLeft' => DeviceOrientation.landscapeLeft,
        'landscapeRight' => DeviceOrientation.landscapeRight,
        _ => null,
      };
}
