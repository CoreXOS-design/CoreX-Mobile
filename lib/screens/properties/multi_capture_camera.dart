import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme.dart';
import '../../utils/device_rotation.dart';
import '../../utils/image_processing.dart';

/// Full-screen, in-app camera with multi-capture, native lens switching
/// (0.6x ultrawide / 1x / 2x / 3x — whichever the device exposes), digital
/// zoom and flash. Photos accumulate; the user taps Done to review and
/// confirm before the queue is returned.
///
/// Each returned photo carries the sensor orientation reported by the device at
/// the moment it was taken. That reading is what makes this screen immune to the
/// OEM firmware bug that ships JPEGs with a missing or invalid (0) EXIF
/// Orientation tag over sideways pixels — we never have to trust the file's own
/// metadata to know which way is up.
///
/// ORIENTATION: this screen pins its UI to portrait, which on Android also
/// blinds the `camera` plugin — it derives device orientation from the display,
/// so it saw "upright" however the phone was tilted and wrote every landscape
/// shot sideways into a portrait frame under EXIF Orientation 1. The physical
/// orientation now comes from [DeviceRotation] (the accelerometer) and is
/// applied per shot. iOS already reads the hardware orientation itself, so
/// there we simply stop overriding it.
class MultiCaptureCamera extends StatefulWidget {
  const MultiCaptureCamera({super.key});

  static Future<List<CapturedPhoto>> open(BuildContext context) async {
    final result = await Navigator.of(context).push<List<CapturedPhoto>>(
      MaterialPageRoute(builder: (_) => const MultiCaptureCamera()),
    );
    return result ?? [];
  }

  @override
  State<MultiCaptureCamera> createState() => _MultiCaptureCameraState();
}

class _LensPreset {
  /// The physical camera this preset uses.
  final CameraDescription camera;
  /// Target digital zoom to apply on that camera when this preset is selected.
  final double targetZoom;
  String label;
  _LensPreset({
    required this.camera,
    required this.targetZoom,
    required this.label,
  });
}

class _MultiCaptureCameraState extends State<MultiCaptureCamera>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _initializing = true;
  String? _error;
  bool _capturing = false;

  final List<CapturedPhoto> _captured = [];
  bool _reviewing = false;

  /// Resolution ladder for stills, most wanted first.
  ///
  /// [ResolutionPreset.high] is 1280x720 — under a megapixel, far too small for
  /// listings, portal feeds and printed brochures, and the reason in-app photos
  /// arrived at a quarter of the size of gallery-picked ones.
  ///
  /// [ResolutionPreset.max] rather than `ultraHigh`, because ultraHigh does not
  /// actually reach parity: it is 3840x2160, i.e. **16:9**, so after the 2560px
  /// long-edge cap a shot lands at 2560x1440 (3.7 MP) while the same scene
  /// picked from the gallery — where image_picker fits the sensor's native 4:3
  /// into a 2560 box — lands at 2560x1920 (4.9 MP). Same long edge, a third
  /// less picture: in-app stills came out letterboxed against gallery ones, and
  /// the vertical crop is exactly what you do not want on a room interior.
  /// `max` asks for the largest frame the device offers, which is the sensor's
  /// native aspect, so the two paths finally produce the same photo.
  ///
  /// The memory objection to `max` is handled where it belongs, at the decode:
  /// see [ImageUploadConfig.maxDecodePixels]. It is also smaller than it looks
  /// — camerax's ResolutionSelector never opts into the ultra-high-resolution
  /// sensor mode (it sets no `setAllowedResolutionMode`), so a 200 MP phone
  /// offers its binned still here, not its headline number.
  ///
  /// The lower rungs are for iOS, where a session preset can genuinely fail to
  /// bind; camerax falls back internally (closestLowerThenHigher) and will
  /// rarely reach them.
  static const List<ResolutionPreset> _resolutionLadder = [
    ResolutionPreset.max,
    ResolutionPreset.ultraHigh,
    ResolutionPreset.veryHigh,
    ResolutionPreset.high,
  ];

  // Digital zoom on the active controller.
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;
  double _baseZoom = 1.0;

  FlashMode _flash = FlashMode.off;

  // Lens presets — a mix of physical-lens entries (one per back-facing
  // CameraDescription) AND digital-zoom entries on the active camera.
  // Tapping a preset either swaps the controller (different camera) or
  // just calls setZoomLevel (same camera).
  final List<_LensPreset> _lensPresets = [];
  int _activeLens = 0;
  bool _onFront = false;
  // Cached list of back-facing physical cameras, in their reported order.
  List<CameraDescription> _backCameras = const [];

  // Guards against concurrent / re-entrant camera bring-up (resume races,
  // double taps on lens/flip). While set, init paths bail out early.
  bool _initInFlight = false;
  // Guards overlapping pinch-zoom calls — only one setZoomLevel in flight.
  bool _zooming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    // The portrait lock above is what hides the phone's real orientation from
    // the camera plugin on Android, so the accelerometer has to be listening
    // for as long as this screen can take a photo.
    DeviceRotation.start();
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    DeviceRotation.stop();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      DeviceRotation.stop();
      final ctrl = _controller;
      if (ctrl == null || !ctrl.value.isInitialized) return;
      // Show a spinner (not a dead preview) and release the device.
      _controller = null;
      if (mounted) setState(() => _initializing = true);
      ctrl.dispose();
    } else if (state == AppLifecycleState.resumed) {
      DeviceRotation.start();
      // Only bring the camera back if we actually let it go.
      if (_controller == null && !_initInFlight) _initCamera();
    }
  }

  @override
  void didChangeMetrics() {
    final ctrl = _controller;
    if (ctrl != null && ctrl.value.isInitialized) {
      _applyCaptureOrientation(ctrl);
    }
  }

  /// Hands orientation back to whoever actually knows which way the phone is
  /// pointing, once per controller.
  ///
  /// This used to pin capture to portraitUp whenever the UI was portrait — which
  /// initState guarantees on every phone. That is the sideways-photo bug: a
  /// landscape scene written into a portrait frame with EXIF Orientation 1, the
  /// file insisting it was upright while the picture lay on its side.
  ///
  /// Unlocking is the whole fix on iOS, where the plugin applies
  /// `UIDevice.current.orientation` — the real hardware orientation — at
  /// capture. On Android unlocking only falls back to the display rotation,
  /// which the same portrait lock freezes, so there [_pinCaptureOrientation]
  /// sets the true orientation immediately before each shot instead.
  Future<void> _applyCaptureOrientation(CameraController ctrl) async {
    // Never unlock between _pinCaptureOrientation and takePicture. didChangeMetrics
    // fires for insets and system-UI changes too, and landing here mid-shot would
    // drop the lock we just set — handing that one photo back to the frozen
    // display rotation, which is the bug.
    if (_capturing) return;
    try {
      await ctrl.unlockCaptureOrientation();
    } catch (_) {
      // Nothing to unlock, or the controller went away mid-call.
    }
  }

  /// Pins the next capture to the way the phone is physically being held, and
  /// returns that rotation in clockwise degrees.
  ///
  /// Null means "the platform is already handling it" (iOS) or "we don't know"
  /// (sensor silent, device flat, bridge unavailable) — and a null must never be
  /// rounded to zero, because "assume upright" is exactly what shipped the
  /// sideways photos.
  Future<int?> _pinCaptureOrientation(CameraController ctrl) async {
    if (!Platform.isAndroid) return null;
    final reading = await DeviceRotation.read();
    if (reading == null) return null;
    try {
      await ctrl.lockCaptureOrientation(reading.orientation);
      return reading.degreesClockwise;
    } catch (_) {
      return null;
    }
  }

  /// Clockwise degrees needed to stand this device's raw sensor output upright,
  /// or null when we can't say for certain and must fall back to the file's EXIF.
  ///
  /// Only used when a file's own EXIF Orientation is missing or invalid — the
  /// HUAWEI/HONOR firmware defect. It is Android's own JPEG-orientation formula:
  /// the sensor's mounting angle relative to the device's natural orientation,
  /// plus how far the device itself is turned (minus, for a front camera, which
  /// counter-rotates). [deviceRotation] of null means the capture orientation is
  /// not ours to describe, so we offer nothing rather than a guess.
  int? _sensorRotationForCapture(CameraController ctrl, int? deviceRotation) {
    if (!Platform.isAndroid || deviceRotation == null) return null;
    final sensor = ctrl.description.sensorOrientation;
    final front =
        ctrl.description.lensDirection == CameraLensDirection.front;
    final total = front ? sensor - deviceRotation : sensor + deviceRotation;
    return ((total % 360) + 360) % 360;
  }

  /// Opens [camera] at the best resolution it will actually bind at.
  ///
  /// Returns an initialised controller, or null when every preset failed.
  Future<CameraController?> _openController(CameraDescription camera) async {
    for (final preset in _resolutionLadder) {
      final ctrl = CameraController(camera, preset, enableAudio: false);
      try {
        await ctrl.initialize();
        return ctrl;
      } catch (_) {
        try {
          await ctrl.dispose();
        } catch (_) {/* already gone */}
      }
    }
    return null;
  }

  Future<void> _initCamera() async {
    if (_initInFlight) return;
    _initInFlight = true;
    try {
      _cameras = await availableCameras();
      if (!mounted) return;
      if (_cameras.isEmpty) {
        setState(() {
          _initializing = false;
          _error = 'No cameras found';
        });
        return;
      }

      // Build the back-facing pool. Strict back first; fall back to
      // anything not explicitly front; last resort all cameras.
      var back = _cameras
          .where((c) => c.lensDirection == CameraLensDirection.back)
          .toList();
      if (back.isEmpty) {
        back = _cameras
            .where((c) => c.lensDirection != CameraLensDirection.front)
            .toList();
      }
      if (back.isEmpty) back = List.of(_cameras);
      _backCameras = back;

      // Pick a starting camera. Prefer a name match for "ultra" so we
      // open at the widest angle on phones that expose ultrawide as its
      // own CameraDescription (most iPhones, some Hauwei/Honor models).
      final ultraIdx = back.indexWhere(
          (c) => c.name.toLowerCase().contains('ultra'));
      final startIdx = ultraIdx >= 0 ? ultraIdx : 0;

      _lensPresets
        ..clear()
        ..add(_LensPreset(
          camera: back[startIdx],
          targetZoom: 1.0,
          label: '1x',
        ));
      _activeLens = 0;
      await _startLens(0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Camera error: $e';
      });
    } finally {
      _initInFlight = false;
    }
  }

  Future<void> _startLens(int index) async {
    // Clamp the index defensively — the preset list is rebuilt asynchronously
    // and a stale _activeLens (e.g. from back-from-front) could overflow it.
    if (_lensPresets.isEmpty) return;
    final safeIndex = index.clamp(0, _lensPresets.length - 1);
    final preset = _lensPresets[safeIndex];
    index = safeIndex;
    // Release the device before opening it again — disposing synchronously and
    // immediately re-opening races the OS and throws "camera already in use".
    final old = _controller;
    _controller = null;
    if (mounted) setState(() => _initializing = true);
    await old?.dispose();
    final ctrl = await _openController(preset.camera);
    if (ctrl == null) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Could not start camera';
      });
      return;
    }
    // The screen may have closed while the ladder was binding. dispose() has
    // already run against a null _controller, so assigning now would strand an
    // open camera device that nothing will ever release.
    if (!mounted) {
      await ctrl.dispose();
      return;
    }
    _controller = ctrl;
    try {
      await _applyCaptureOrientation(ctrl);
      final minZ = await ctrl.getMinZoomLevel();
      final maxZ = await ctrl.getMaxZoomLevel();
      // Real-estate mode: always sit at the widest available zoom on the
      // chosen lens. On phones with a logical multi-camera, minZ < 1.0
      // physically engages the ultrawide; on phones where ultrawide is a
      // separate CameraDescription we already picked it, so minZ ≈ 1.0.
      final restZoom = minZ;

      try {
        await ctrl.setFlashMode(_flash);
      } catch (_) {}

      setState(() {
        _activeLens = index;
        _onFront = false;
        _initializing = false;
        _error = null;
        _minZoom = minZ;
        _maxZoom = maxZ;
        _currentZoom = restZoom;
      });
      await ctrl.setZoomLevel(restZoom);
      _rebuildZoomPresetsFromActive();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Could not start camera';
      });
    }
  }

  /// After the active controller is initialised, rebuild the lens preset
  /// list to expose every option the user can reach:
  ///
  /// 1. Every back-facing physical CameraDescription becomes a chip — so
  ///    if the device exposes ultrawide as a separate camera (which is
  ///    why getMinZoomLevel returns 1.0 on the default lens), the user
  ///    can tap into it directly.
  /// 2. The active camera's digital zoom range adds extra chips: the
  ///    sub-1.0 minimum (engages logical-camera ultrawide on phones that
  ///    use that pattern), 1x, and 2x/5x where supported.
  void _rebuildZoomPresetsFromActive() {
    if (_backCameras.isEmpty) return;
    final activeCam =
        _controller?.description ?? _backCameras.first;
    final newPresets = <_LensPreset>[];

    // Digital sub-1.0 zoom on the active camera (logical-multicam path).
    if (_minZoom < 0.95) {
      newPresets.add(_LensPreset(
        camera: activeCam,
        targetZoom: _minZoom,
        label: '${_minZoom.toStringAsFixed(1)}x',
      ));
    }

    // One chip per physical back-facing camera.
    for (var i = 0; i < _backCameras.length; i++) {
      final cam = _backCameras[i];
      final n = cam.name.toLowerCase();
      String label;
      if (n.contains('ultra')) {
        label = '0.6x';
      } else if (n.contains('tele')) {
        label = '2x';
      } else if (i == 0) {
        label = '1x';
      } else {
        label = 'L${i + 1}';
      }
      newPresets.add(_LensPreset(
        camera: cam,
        targetZoom: cam == activeCam ? 1.0.clamp(_minZoom, _maxZoom).toDouble() : 1.0,
        label: label,
      ));
    }

    // Digital zoom extras on the active camera.
    if (_maxZoom >= 2.0 && activeCam == _backCameras.first) {
      newPresets.add(_LensPreset(
        camera: activeCam,
        targetZoom: 2.0,
        label: '2x',
      ));
    }
    if (_maxZoom >= 5.0 && activeCam == _backCameras.first) {
      newPresets.add(_LensPreset(
        camera: activeCam,
        targetZoom: 5.0,
        label: '5x',
      ));
    }

    // De-dup by label, keeping order.
    final seen = <String>{};
    final deduped = <_LensPreset>[];
    for (final p in newPresets) {
      if (seen.add(p.label)) deduped.add(p);
    }

    _lensPresets
      ..clear()
      ..addAll(deduped);

    // Set active to the entry that matches the current camera + zoom.
    int active = _lensPresets.indexWhere((p) =>
        p.camera == activeCam &&
        (p.targetZoom - _currentZoom).abs() < 0.05);
    if (active < 0) {
      active = _lensPresets.indexWhere((p) => p.camera == activeCam);
    }
    if (active < 0) active = 0;
    _activeLens = active;
    if (mounted) setState(() {});
  }

  Future<void> _setLens(int index) async {
    final ctrl = _controller;
    if (ctrl == null || _initializing) return;
    if (index < 0 || index >= _lensPresets.length) return;
    final target = _lensPresets[index];
    // Same physical camera — just adjust digital zoom.
    if (!_onFront && target.camera == ctrl.description) {
      try {
        final z = target.targetZoom.clamp(_minZoom, _maxZoom).toDouble();
        await ctrl.setZoomLevel(z);
        if (!mounted) return;
        setState(() {
          _activeLens = index;
          _currentZoom = z;
        });
      } catch (_) {/* ignore */}
      return;
    }
    // Different physical camera — restart controller on it, then the
    // post-init rebuild will refresh chips and reset _activeLens.
    if (_initInFlight) return;
    _initInFlight = true;
    setState(() => _initializing = true);
    final oldCtrl = _controller;
    _controller = null;
    // Release the device before re-opening on the new lens.
    await oldCtrl?.dispose();
    final newCtrl = await _openController(target.camera);
    if (newCtrl == null) {
      _initInFlight = false;
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Could not switch lens';
      });
      return;
    }
    // See _startLens: assigning after dispose() has run strands the device.
    if (!mounted) {
      _initInFlight = false;
      await newCtrl.dispose();
      return;
    }
    _controller = newCtrl;
    try {
      await _applyCaptureOrientation(newCtrl);
      final minZ = await newCtrl.getMinZoomLevel();
      final maxZ = await newCtrl.getMaxZoomLevel();
      try {
        await newCtrl.setFlashMode(_flash);
      } catch (_) {}
      // Land at the widest zoom on the new lens (real-estate default).
      await newCtrl.setZoomLevel(minZ);
      if (!mounted) return;
      setState(() {
        _onFront = false;
        _initializing = false;
        _error = null;
        _minZoom = minZ;
        _maxZoom = maxZ;
        _currentZoom = minZ;
      });
      _rebuildZoomPresetsFromActive();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Could not switch lens';
      });
    } finally {
      _initInFlight = false;
    }
  }

  Future<void> _switchCamera() async {
    if (_initInFlight) return;
    final front = _cameras
        .where((c) => c.lensDirection == CameraLensDirection.front)
        .toList();
    if (front.isEmpty) return;
    if (!_onFront) {
      _initInFlight = true;
      setState(() => _initializing = true);
      final oldCtrl = _controller;
      _controller = null;
      // Release the back camera before opening the front one.
      await oldCtrl?.dispose();
      final ctrl = await _openController(front.first);
      if (ctrl == null) {
        _initInFlight = false;
        if (!mounted) return;
        setState(() {
          _initializing = false;
          _error = 'Could not start front camera';
        });
        return;
      }
      // See _startLens: assigning after dispose() has run strands the device.
      if (!mounted) {
        _initInFlight = false;
        await ctrl.dispose();
        return;
      }
      _controller = ctrl;
      try {
        await _applyCaptureOrientation(ctrl);
        final minZ = await ctrl.getMinZoomLevel();
        final maxZ = await ctrl.getMaxZoomLevel();
        if (!mounted) return;
        setState(() {
          _onFront = true;
          _initializing = false;
          _minZoom = minZ;
          _maxZoom = maxZ;
          _currentZoom = 1.0.clamp(minZ, maxZ).toDouble();
        });
        await ctrl.setZoomLevel(_currentZoom);
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _initializing = false;
          _error = 'Could not start front camera';
        });
      } finally {
        _initInFlight = false;
      }
    } else {
      // Back from front. _activeLens may index a stale preset list; _startLens
      // clamps it and shows its own spinner.
      await _startLens(_activeLens);
    }
  }

  Future<void> _cycleFlash() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    final next = switch (_flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      FlashMode.always => FlashMode.torch,
      FlashMode.torch => FlashMode.off,
    };
    try {
      await ctrl.setFlashMode(next);
      if (!mounted) return;
      setState(() => _flash = next);
    } catch (_) {}
  }

  IconData _flashIcon() => switch (_flash) {
        FlashMode.off => Icons.flash_off_rounded,
        FlashMode.auto => Icons.flash_auto_rounded,
        FlashMode.always => Icons.flash_on_rounded,
        FlashMode.torch => Icons.highlight_rounded,
      };

  void _onScaleStart(ScaleStartDetails _) {
    _baseZoom = _currentZoom;
  }

  Future<void> _onScaleUpdate(ScaleUpdateDetails details) async {
    final ctrl = _controller;
    if (ctrl == null) return;
    // Drop overlapping gestures — only one setZoomLevel in flight at a time so
    // we don't queue a burst of calls against the camera.
    if (_zooming) return;
    final newZoom =
        (_baseZoom * details.scale).clamp(_minZoom, _maxZoom).toDouble();
    if (newZoom == _currentZoom) return;
    _zooming = true;
    setState(() => _currentZoom = newZoom);
    try {
      await ctrl.setZoomLevel(newZoom);
    } catch (_) {
      // ignore — controller may have been swapped/disposed mid-gesture
    } finally {
      _zooming = false;
    }
    if (!mounted) return;
  }

  Future<void> _takePicture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      // Read and apply the physical orientation per shot, not per controller —
      // the user turns the phone between photos, and on Android nothing else
      // will notice.
      final deviceRotation = await _pinCaptureOrientation(ctrl);
      final xFile = await ctrl.takePicture();
      if (Platform.isAndroid && deviceRotation == null) {
        // Not benign, and not debug-only: with no reading we cannot lock, so
        // CameraX falls back to getDefaultDisplayRotation() — the value the
        // portrait lock freezes at 0. That is exactly the sideways-photo bug,
        // and _sensorRotationForCapture offers nothing to rescue it downstream.
        // Only reachable when the phone has been flat since the screen opened.
        debugPrint('Capture: device rotation unknown (accelerometer has not '
            'reported) — photo may be written sideways');
      }
      if (kDebugMode) {
        // The tilt is knowable only here, at capture. Say what we read and what
        // we did with it, so a sideways photo can be traced to the reading that
        // produced it instead of guessed at from the file afterwards.
        debugPrint(
          'Capture: device rotation '
          '${deviceRotation == null ? 'unknown (platform-handled)' : '$deviceRotation° CW'}'
          ', sensor ${ctrl.description.sensorOrientation}°'
          ', preview ${ctrl.value.previewSize}',
        );
      }
      if (!mounted) return;
      setState(() {
        _captured.add(CapturedPhoto(
          File(xFile.path),
          sensorRotation: _sensorRotationForCapture(ctrl, deviceRotation),
        ));
        _capturing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _capturing = false);
    }
  }

  void _removeAt(int index) {
    setState(() => _captured.removeAt(index));
    if (_captured.isEmpty) {
      setState(() => _reviewing = false);
    }
  }

  void _confirm() => Navigator.of(context).pop(_captured);
  void _cancel() => Navigator.of(context).pop(<CapturedPhoto>[]);

  @override
  Widget build(BuildContext context) {
    if (_reviewing) return _buildReview();
    return _buildCamera();
  }

  Widget _buildCamera() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: _cancel,
                  ),
                  IconButton(
                    icon: Icon(_flashIcon(), color: Colors.white),
                    onPressed: _cycleFlash,
                    tooltip: 'Flash',
                  ),
                  const Spacer(),
                  if (_captured.isNotEmpty)
                    Text(
                      '${_captured.length} taken',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 14),
                    ),
                  const Spacer(),
                  if (_cameras.any(
                      (c) => c.lensDirection == CameraLensDirection.front))
                    IconButton(
                      icon: const Icon(Icons.flip_camera_ios,
                          color: Colors.white),
                      onPressed: _switchCamera,
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: _initializing
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: Colors.white))
                  : _error != null
                      ? Center(
                          child: Text(_error!,
                              style: const TextStyle(color: Colors.white70)))
                      : Builder(
                          builder: (context) {
                            final ctrl = _controller;
                            // previewSize can be null briefly after init (and
                            // on some emulators/devices never resolves). Don't
                            // dereference it with `!` — that hard-crashes the
                            // whole screen. Fall back to a spinner until it's
                            // ready, and use a sane default aspect if missing.
                            if (ctrl == null ||
                                !ctrl.value.isInitialized) {
                              return const Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.white));
                            }
                            // previewSize is reported in sensor (landscape)
                            // orientation. Swap it only when we're actually
                            // laid out portrait — iPad ignores the
                            // setPreferredOrientations lock in initState, so
                            // this screen really can be landscape.
                            final preview = ctrl.value.previewSize;
                            final sensorW = preview?.width ?? 1280.0;
                            final sensorH = preview?.height ?? 720.0;
                            final isPortrait =
                                MediaQuery.orientationOf(context) ==
                                    Orientation.portrait;
                            final pw = isPortrait ? sensorH : sensorW;
                            final ph = isPortrait ? sensorW : sensorH;
                            return GestureDetector(
                          onScaleStart: _onScaleStart,
                          onScaleUpdate: _onScaleUpdate,
                          child: Stack(
                            alignment: Alignment.bottomCenter,
                            children: [
                              ClipRect(
                                child: OverflowBox(
                                  alignment: Alignment.center,
                                  child: FittedBox(
                                    fit: BoxFit.cover,
                                    child: SizedBox(
                                      width: pw,
                                      height: ph,
                                      child: CameraPreview(ctrl),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 16,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_currentZoom > _minZoom + 0.05 &&
                                        _maxZoom > _minZoom + 0.05)
                                      Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '${_currentZoom.toStringAsFixed(1)}x',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    if (!_onFront && _lensPresets.length > 1)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius:
                                              BorderRadius.circular(28),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: List.generate(
                                            _lensPresets.length,
                                            (i) {
                                              final p = _lensPresets[i];
                                              final active = i == _activeLens;
                                              return GestureDetector(
                                                onTap: () => _setLens(i),
                                                child: Container(
                                                  margin: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 4),
                                                  width: 40,
                                                  height: 40,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: active
                                                        ? AppTheme.brand
                                                        : Colors.black38,
                                                  ),
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    p.label,
                                                    style: TextStyle(
                                                      color: active
                                                          ? Colors.white
                                                          : Colors.white70,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                            );
                          },
                        ),
            ),
            Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: _captured.isNotEmpty
                        ? GestureDetector(
                            onTap: () => setState(() => _reviewing = true),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(_captured.last.file,
                                  cacheWidth: 150, fit: BoxFit.cover),
                            ),
                          )
                        : null,
                  ),
                  GestureDetector(
                    onTap: _takePicture,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 100),
                          width: _capturing ? 56 : 60,
                          height: _capturing ? 56 : 60,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: _captured.isNotEmpty
                        ? TextButton(
                            onPressed: () =>
                                setState(() => _reviewing = true),
                            // Zero padding + shrink-wrapped tap target: the
                            // default TextButton padding leaves under 32px of
                            // text width in this 56px slot, which wraps "Done"
                            // onto two lines.
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(56, 56),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text('Done',
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.visible,
                                style: TextStyle(
                                    color: AppTheme.brand,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15)),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReview() {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBackground,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _reviewing = false),
        ),
        title: Text(
            '${_captured.length} photo${_captured.length == 1 ? '' : 's'}'),
        actions: [
          TextButton(
            onPressed: _confirm,
            child: Text('Confirm',
                style: TextStyle(
                    color: AppTheme.brand,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: _captured.length,
        itemBuilder: (_, i) {
          return Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radius),
                child: Image.file(_captured[i].file,
                    cacheWidth: 300, fit: BoxFit.cover),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => _removeAt(i),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(Icons.close,
                        color: Colors.white, size: 16),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
