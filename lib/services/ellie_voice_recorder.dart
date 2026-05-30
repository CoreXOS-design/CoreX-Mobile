import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Push-to-talk recorder for Ellie. AAC m4a, 16 kHz mono. Caps at 28 seconds
/// to leave headroom before the backend's 30 s hard limit.
class EllieVoiceRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;
  Timer? _maxClipTimer;

  static const Duration maxClip = Duration(seconds: 28);

  /// Requests mic permission and starts recording. Returns `true` if
  /// recording started, `false` if permission denied.
  Future<bool> start({VoidCallback? onAutoStop}) async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) return false;
    if (!await _recorder.hasPermission()) return false;

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/ellie_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 64000,
      ),
      path: path,
    );
    _path = path;

    _maxClipTimer?.cancel();
    _maxClipTimer = Timer(maxClip, () async {
      if (await _recorder.isRecording()) {
        await stop();
        if (onAutoStop != null) onAutoStop();
      }
    });
    return true;
  }

  /// Stops recording and returns the recorded file (or `null` if nothing was
  /// captured).
  Future<File?> stop() async {
    _maxClipTimer?.cancel();
    _maxClipTimer = null;
    final saved = await _recorder.stop();
    final p = saved ?? _path;
    _path = null;
    if (p == null) return null;
    final f = File(p);
    if (!await f.exists()) return null;
    return f;
  }

  Future<void> cancel() async {
    _maxClipTimer?.cancel();
    _maxClipTimer = null;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.cancel();
      }
    } catch (_) {}
    final p = _path;
    _path = null;
    if (p != null) {
      try {
        await File(p).delete();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    _maxClipTimer?.cancel();
    await _recorder.dispose();
  }
}

typedef VoidCallback = void Function();
