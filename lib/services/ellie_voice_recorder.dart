import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Outcome of a finished push-to-talk gesture.
enum EllieClipStatus {
  /// A usable clip was captured.
  ok,

  /// The button was released before [EllieVoiceRecorder.minHold] elapsed.
  /// Nothing was recorded long enough to send — prompt the agent to hold.
  tooShort,

  /// Recording produced no file (cancelled, denied, or zero bytes).
  empty,
}

/// Result of [EllieVoiceRecorder.stop].
class EllieClip {
  final EllieClipStatus status;
  final File? file;
  const EllieClip(this.status, [this.file]);
}

/// Microphone access as the UI needs to reason about it.
enum MicPermission {
  granted,

  /// Declined, but asking again is still possible (Android).
  denied,

  /// The OS will not prompt again — only Settings can turn it back on.
  /// iOS reports this after a single "Don't Allow", because it never re-asks.
  permanentlyDenied,
}

/// Push-to-talk recorder for Ellie. AAC m4a, 16 kHz mono. Caps at 28 seconds
/// to leave headroom before the backend's 30 s hard limit.
///
/// Browser DSP (echo cancellation, noise suppression, auto gain) is left OFF so
/// the backend receives the raw mic signal — those features strip soft and
/// accented speech and are a leading cause of empty transcripts. Whisper does
/// its own denoising server-side.
class EllieVoiceRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;
  DateTime? _startedAt;
  Timer? _maxClipTimer;

  static const Duration maxClip = Duration(seconds: 28);

  /// Minimum press duration before a clip is worth sending. Releases quicker
  /// than this are treated as accidental taps and discarded.
  static const Duration minHold = Duration(milliseconds: 400);

  /// Grace period after the agent releases the button before the stream is
  /// actually cut, so the tail of the last word isn't clipped.
  static const Duration stopTailDelay = Duration(milliseconds: 300);

  static MicPermission _map(PermissionStatus s) {
    if (s.isGranted || s.isLimited) return MicPermission.granted;
    if (s.isPermanentlyDenied || s.isRestricted) {
      return MicPermission.permanentlyDenied;
    }
    return MicPermission.denied;
  }

  /// Current microphone access. Never shows a system prompt — safe to call on
  /// screen build / app resume.
  Future<MicPermission> permissionStatus() async =>
      _map(await Permission.microphone.status);

  /// Shows the system microphone prompt if it hasn't been answered yet.
  ///
  /// This is deliberately NOT part of [start]: the system alert cancels
  /// whatever touch triggered it, so a press-and-hold that also asks for
  /// permission can never produce a recording. Resolve access first, record on
  /// the next press.
  Future<MicPermission> ensurePermission() async {
    final current = await permissionStatus();
    if (current != MicPermission.denied) return current;
    return _map(await Permission.microphone.request());
  }

  /// Opens the OS settings page for this app so access can be re-enabled.
  static Future<bool> openSettings() => openAppSettings();

  /// Starts recording. Returns `false` if the microphone isn't granted (call
  /// [ensurePermission] first) or if the audio session refused to start.
  Future<bool> start({VoidCallback? onAutoStop}) async {
    // Single source of truth. Asking `record` for permission as well would
    // fire a second, independent request against the same OS permission and
    // can spuriously report "denied" while the first one is still settling.
    if (await permissionStatus() != MicPermission.granted) return false;

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/ellie_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 64000,
          // Capture the raw mic signal — these strip soft/accented speech.
          echoCancel: false,
          noiseSuppress: false,
          autoGain: false,
          // VOICE_RECOGNITION avoids the aggressive voice-comm AGC/NS that the
          // default source applies on many devices, which is the mobile
          // equivalent of disabling the browser DSP constraints.
          androidConfig: AndroidRecordConfig(
            audioSource: AndroidAudioSource.voiceRecognition,
          ),
        ),
        path: path,
      );
    } catch (_) {
      // Audio session refused to start (another app holds the mic, or we were
      // backgrounded mid-call). Leave no half-armed state behind.
      _path = null;
      _startedAt = null;
      return false;
    }
    _path = path;
    _startedAt = DateTime.now();

    _maxClipTimer?.cancel();
    // Don't stop here — let the finish path own the single stop() (with its
    // tail delay). We only nudge the caller to wrap up.
    _maxClipTimer = Timer(maxClip, () {
      if (onAutoStop != null) onAutoStop();
    });
    return true;
  }

  /// Stops recording and returns the captured clip.
  ///
  /// Releases shorter than [minHold] are reported as [EllieClipStatus.tooShort]
  /// and the (near-empty) blob is discarded rather than sent.
  Future<EllieClip> stop() async {
    _maxClipTimer?.cancel();
    _maxClipTimer = null;
    final startedAt = _startedAt;
    _startedAt = null;

    final held = startedAt == null
        ? Duration.zero
        : DateTime.now().difference(startedAt);
    if (held < minHold) {
      await cancel();
      return const EllieClip(EllieClipStatus.tooShort);
    }

    // Let the tail of the last word land before we cut the stream.
    await Future.delayed(stopTailDelay);

    final saved = await _recorder.stop();
    final p = saved ?? _path;
    _path = null;
    if (p == null) return const EllieClip(EllieClipStatus.empty);
    final f = File(p);
    if (!await f.exists()) return const EllieClip(EllieClipStatus.empty);
    return EllieClip(EllieClipStatus.ok, f);
  }

  Future<void> cancel() async {
    _maxClipTimer?.cancel();
    _maxClipTimer = null;
    _startedAt = null;
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
    // Drop any temp clip that was never consumed by stop() (which clears _path
    // and hands the file to the caller) so recordings don't accumulate on disk.
    final p = _path;
    _path = null;
    if (p != null) {
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await _recorder.dispose();
  }
}

typedef VoidCallback = void Function();
