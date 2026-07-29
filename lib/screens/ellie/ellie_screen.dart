import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';
import '../../widgets/ui/content_width.dart';

import '../../providers/auth_provider.dart';
import '../../services/ai_api.dart';
import '../../services/api_service.dart';
import '../../services/ellie_voice_recorder.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../utils/app_time.dart';
import '../../widgets/ai/ai_badge.dart';
import '../../widgets/corex/corex_bottom_nav.dart';
import '../../widgets/ellie/ellie_result_sheet.dart';
import '../calendar_screen.dart';

class EllieScreen extends StatefulWidget {
  const EllieScreen({super.key});

  @override
  State<EllieScreen> createState() => _EllieScreenState();
}

class _EllieScreenState extends State<EllieScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final EllieVoiceRecorder _recorder = EllieVoiceRecorder();
  final AiApi _api = AiApi();
  late final AnimationController _pulse;
  _Phase _phase = _Phase.idle;
  String? _lastTranscript;

  /// Null until the first status read completes.
  MicPermission? _mic;
  bool _askingMic = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addObserver(this);
    _refreshMic();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Picks up access granted from the Settings app without needing a restart.
    if (state == AppLifecycleState.resumed) _refreshMic();
  }

  /// Reads current access without ever prompting.
  Future<void> _refreshMic() async {
    final status = await _recorder.permissionStatus();
    if (!mounted || status == _mic) return;
    setState(() => _mic = status);
  }

  /// Resolves microphone access as a step of its own.
  ///
  /// The system alert cancels the touch that triggered it, so a press-and-hold
  /// that also asks for permission can never record — it always releases at
  /// ~0 ms and is discarded as an accidental tap. Grant first, record on the
  /// next press.
  Future<void> _askForMic() async {
    if (_askingMic) return;
    _askingMic = true;
    try {
      final result = await _recorder.ensurePermission();
      if (!mounted) return;
      setState(() => _mic = result);
      final messenger = ScaffoldMessenger.of(context);
      switch (result) {
        case MicPermission.granted:
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Microphone on — hold the mic and speak.'),
            ),
          );
        case MicPermission.denied:
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Ellie needs the microphone to hear you.'),
            ),
          );
        case MicPermission.permanentlyDenied:
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                  'Microphone access is off for CoreX. Turn it on in Settings.'),
              duration: Duration(seconds: 6),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: EllieVoiceRecorder.openSettings,
              ),
            ),
          );
      }
    } finally {
      _askingMic = false;
    }
  }

  bool _pointerDown = false;

  Future<void> _onPointerDown() async {
    if (_phase != _Phase.idle || _pointerDown) return;
    if (_mic != MicPermission.granted) {
      await _askForMic();
      return;
    }
    _pointerDown = true;
    final ok = await _recorder.start(onAutoStop: () {
      if (!mounted) return;
      _finishRecording();
    });
    if (!ok) {
      _pointerDown = false;
      // Access can be revoked from Settings while the screen is open — resync
      // so the button reverts to its enable state instead of failing silently.
      await _refreshMic();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mic == MicPermission.granted
              ? "Couldn't start recording — check nothing else is using the mic."
              : 'Microphone access is off for CoreX.'),
          action: _mic == MicPermission.granted
              ? null
              : const SnackBarAction(
                  label: 'Settings',
                  onPressed: EllieVoiceRecorder.openSettings,
                ),
        ),
      );
      return;
    }
    if (!mounted) return;
    // If the user already lifted before recording actually started, send now.
    if (!_pointerDown) {
      await _finishRecording();
      return;
    }
    setState(() => _phase = _Phase.recording);
  }

  Future<void> _onPointerUp() async {
    if (!_pointerDown) return;
    _pointerDown = false;
    if (_phase != _Phase.recording) return;
    await _finishRecording();
  }

  bool _finishing = false;

  Future<void> _finishRecording() async {
    // Guard against the release gesture and the auto-stop timer both firing.
    if (_finishing) return;
    _finishing = true;
    try {
      await _runFinish();
    } finally {
      _finishing = false;
    }
  }

  Future<void> _runFinish() async {
    EllieClip clip;
    try {
      clip = await _recorder.stop();
    } catch (e) {
      _resetWithError('Recording failed: $e');
      return;
    }
    if (!mounted) return;
    switch (clip.status) {
      case EllieClipStatus.tooShort:
        setState(() => _phase = _Phase.idle);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Hold to talk — press and hold the mic')),
        );
        return;
      case EllieClipStatus.empty:
        _resetWithError(
            "Didn't catch that — hold the mic and speak after the tone");
        return;
      case EllieClipStatus.ok:
        break;
    }
    final file = clip.file!;
    setState(() => _phase = _Phase.thinking);
    try {
      final result = await _api.sendVoice(file);
      if (!mounted) return;
      // Empty/short transcript with no recognised intent: the clip didn't
      // carry usable speech. Nudge gently rather than popping a result sheet.
      if (result.unknown && result.transcript.trim().length < 2) {
        setState(() => _phase = _Phase.idle);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "Didn't catch that — hold the mic and speak after the tone"),
          ),
        );
        return;
      }
      setState(() {
        _phase = _Phase.idle;
        _lastTranscript = result.transcript;
      });
      await EllieResultSheet.show(
        context,
        result: result,
        onOpenEvent: () {
          DateTime? when;
          final ev = result.event;
          final raw = ev?['event_date']?.toString();
          if (raw != null && raw.isNotEmpty) {
            try {
              when = jhb(DateTime.parse(raw));
            } catch (_) {}
          }
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CalendarScreen(
                initialDate: when,
                openEventId: result.eventId,
              ),
            ),
          );
        },
        onUndo: (eventId) async {
          // Capture the messenger before the await so we don't reach across an
          // async gap with the closure's context.
          final messenger = ScaffoldMessenger.of(context);
          try {
            await _api.undoEllieEvent(eventId);
            messenger.showSnackBar(
              const SnackBar(content: Text('Undone.')),
            );
          } on ApiException catch (e) {
            messenger.showSnackBar(
              SnackBar(content: Text(e.message)),
            );
          }
        },
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _phase = _Phase.idle);
      if (e.statusCode == 403) {
        // Per-user permission denied (admin restricted this user). Not an
        // agency gate — just tell them and stop.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("You don't have permission to use Ellie voice.")),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      _resetWithError('Ellie failed: $e');
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  void _resetWithError(String msg) {
    if (!mounted) return;
    setState(() => _phase = _Phase.idle);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    // AI is available to everyone — no agency or per-user gate. Ellie voice is
    // always active for any signed-in user who reaches this screen.
    final allowed = context.watch<AuthProvider>().isLoggedIn;

    return Scaffold(
      backgroundColor: CorexTokens.pageBase(context),
      body: Container(
        decoration: BoxDecoration(gradient: CorexTokens.pageBacklight(context)),
        child: ContentSafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Text(
                      'Ellie',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: CorexTokens.textPrimary(context),
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const AiBadge(),
                  ],
                ),
              ),
              Expanded(
                child: allowed ? _activeBody() : _disabledBody(),
              ),
              CorexBottomNav(
                active: CorexNavTab.ellie,
                onTap: (tab) =>
                    corexNavigateTo(context, tab, CorexNavTab.ellie),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _activeBody() {
    final recording = _phase == _Phase.recording;
    final thinking = _phase == _Phase.thinking;
    // Treat the pre-read state as ready so the button never flashes a
    // permission prompt on a device that already granted access.
    final needsMic = _mic != null && _mic != MicPermission.granted;
    final accent = CorexAccentTheme.of(context);
    // ~470pt of fixed content (mic target, labels, transcript) does not fit a
    // landscape phone or a short iPad window. Centre it while there's room and
    // let it scroll once there isn't — Spacers would overflow instead.
    return LayoutBuilder(
      builder: (_, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              Text(
                recording
                    ? 'Listening…'
                    : (thinking
                        ? 'Thinking…'
                        : (needsMic
                            ? 'Ellie needs your microphone to hear you'
                            : 'Hold the mic and tell Ellie what to do')),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: CorexTokens.textSecondary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                needsMic
                    ? (_mic == MicPermission.permanentlyDenied
                        ? 'Turn on Microphone for CoreX in Settings, then come back.'
                        : 'Tap the mic to allow access.')
                    : 'Try: "Book a viewing with John at 12 Beach Road tomorrow at 11am"',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: CorexTokens.textTertiary(context),
                ),
              ),
              const SizedBox(height: 32),
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: thinking ? null : (_) => _onPointerDown(),
                onPointerUp: thinking ? null : (_) => _onPointerUp(),
                onPointerCancel: thinking ? null : (_) => _onPointerUp(),
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    final t = recording ? _pulse.value : 0.0;
                    final scale = 1.0 + (t * 0.1);
                    final baseColor =
                        recording ? const Color(0xFFE53935) : accent.accent;
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: recording
                                ? const [Color(0xFFE53935), Color(0xFFB71C1C)]
                                : [
                                    accent.accent,
                                    Color.lerp(accent.accent, Colors.black,
                                            0.35) ??
                                        accent.accent,
                                  ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                            BoxShadow(
                              color: baseColor.withValues(
                                  alpha: recording ? 0.5 * (1 - t) : 0.35),
                              blurRadius: 30 + (t * 20),
                              spreadRadius: recording ? 6 + (t * 8) : 4,
                            ),
                          ],
                        ),
                        child: Icon(
                          thinking
                              ? TablerIcons.loader_2
                              : (recording
                                  ? TablerIcons.microphone_2
                                  : (needsMic
                                      ? TablerIcons.microphone_off
                                      : TablerIcons.microphone)),
                          color: Colors.white,
                          size: 56,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Text(
                recording
                    ? 'Release to send'
                    : (thinking
                        ? 'Sending to Ellie…'
                        : (needsMic
                            ? (_mic == MicPermission.permanentlyDenied
                                ? 'Open Settings'
                                : 'Tap to enable')
                            : 'Hold to talk')),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: CorexTokens.textSecondary(context),
                ),
              ),
              const SizedBox(height: 32),
              if (_lastTranscript != null && _lastTranscript!.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: CorexTokens.surfaceGradient(context),
                    borderRadius: BorderRadius.circular(CorexTokens.radius),
                    border: Border.all(color: accent.accentSoft),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LAST TRANSCRIPT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: CorexTokens.textTertiary(context),
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '"${_lastTranscript!}"',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: CorexTokens.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _disabledBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(TablerIcons.microphone_off,
                size: 48, color: CorexTokens.textMuted(context)),
            const SizedBox(height: 12),
            Text(
              'Ellie voice isn\'t available on this account yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: CorexTokens.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Phase { idle, recording, thinking }
