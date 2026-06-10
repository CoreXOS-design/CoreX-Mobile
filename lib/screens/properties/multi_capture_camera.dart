import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme.dart';

/// Full-screen, in-app camera with multi-capture, native lens switching
/// (0.6x ultrawide / 1x / 2x / 3x — whichever the device exposes), digital
/// zoom and flash. Photos accumulate; the user taps Done to review and
/// confirm before the queue is returned.
class MultiCaptureCamera extends StatefulWidget {
  const MultiCaptureCamera({super.key});

  static Future<List<File>> open(BuildContext context) async {
    final result = await Navigator.of(context).push<List<File>>(
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

  final List<File> _captured = [];
  bool _reviewing = false;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      ctrl.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
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
    }
  }

  Future<void> _startLens(int index) async {
    final preset = _lensPresets[index];
    _controller?.dispose();
    final ctrl =
        CameraController(preset.camera, ResolutionPreset.high, enableAudio: false);
    _controller = ctrl;
    try {
      await ctrl.initialize();
      if (!mounted) return;
      try {
        await ctrl.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {}
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
    setState(() => _initializing = true);
    _controller?.dispose();
    final newCtrl =
        CameraController(target.camera, ResolutionPreset.high, enableAudio: false);
    _controller = newCtrl;
    try {
      await newCtrl.initialize();
      if (!mounted) return;
      try {
        await newCtrl.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {}
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
    }
  }

  Future<void> _switchCamera() async {
    final front = _cameras
        .where((c) => c.lensDirection == CameraLensDirection.front)
        .toList();
    if (front.isEmpty) return;
    setState(() => _initializing = true);
    if (!_onFront) {
      _controller?.dispose();
      final ctrl =
          CameraController(front.first, ResolutionPreset.high, enableAudio: false);
      _controller = ctrl;
      try {
        await ctrl.initialize();
        try {
          await ctrl.lockCaptureOrientation(DeviceOrientation.portraitUp);
        } catch (_) {}
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
      }
    } else {
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
    final newZoom =
        (_baseZoom * details.scale).clamp(_minZoom, _maxZoom).toDouble();
    if (newZoom == _currentZoom) return;
    setState(() => _currentZoom = newZoom);
    await ctrl.setZoomLevel(newZoom);
  }

  Future<void> _takePicture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final xFile = await ctrl.takePicture();
      if (!mounted) return;
      setState(() {
        _captured.add(File(xFile.path));
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
  void _cancel() => Navigator.of(context).pop(<File>[]);

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
                    )
                  else
                    Text(
                      'lenses: ${_backCameras.length} · zoom ${_minZoom.toStringAsFixed(1)}–${_maxZoom.toStringAsFixed(1)}x',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
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
                      : GestureDetector(
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
                                      width: _controller!
                                          .value.previewSize!.height,
                                      height: _controller!
                                          .value.previewSize!.width,
                                      child: CameraPreview(_controller!),
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
                              child: Image.file(_captured.last,
                                  fit: BoxFit.cover),
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
                    child: _captured.isNotEmpty
                        ? TextButton(
                            onPressed: () =>
                                setState(() => _reviewing = true),
                            child: Text('Done',
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
                child: Image.file(_captured[i], fit: BoxFit.cover),
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
