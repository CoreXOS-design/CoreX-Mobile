import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:google_fonts/google_fonts.dart';
import '../services/debug_log.dart';
import '../theme.dart';

/// Animated app-open splash.
///
/// Sequence:
///   1. Letters of "CoreX" rise + fade in one by one (staggered)
///   2. Underline draws beneath them
///   3. Tagline rises in, then [onFinished]
class SplashScreen extends StatefulWidget {
  final VoidCallback onFinished;

  const SplashScreen({super.key, required this.onFinished});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _glowFade;
  late final Animation<double> _underlineSweep;
  late final Animation<double> _taglineFade;
  late final Animation<Offset> _taglineSlide;

  static const String _word = 'CoreX';

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    );

    _glowFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.20, 0.70, curve: Curves.easeOut),
    );

    _underlineSweep = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.55, 0.85, curve: Curves.easeOutCubic),
    );

    _taglineFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.70, 1.00, curve: Curves.easeOut),
    );
    _taglineSlide = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.70, 1.00, curve: Curves.easeOutCubic),
      ),
    );

    _controller.forward().whenComplete(() async {
      await Future.delayed(const Duration(milliseconds: 350));
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Per-letter staggered fade+slide. Each letter gets a 0.12-wide window,
  // starting 0.06 apart, within the controller's [0..1] timeline.
  Animation<double> _letterFade(int i, int total) {
    final start = 0.05 + i * 0.07;
    final end = (start + 0.22).clamp(0.0, 1.0);
    return CurvedAnimation(
      parent: _controller,
      curve: Interval(start, end, curve: Curves.easeOut),
    );
  }

  Animation<Offset> _letterSlide(int i, int total) {
    final start = 0.05 + i * 0.07;
    final end = (start + 0.22).clamp(0.0, 1.0);
    return Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgTop = isDark ? AppTheme.darkBackground : AppTheme.lightBackground;
    final bgBottom = isDark ? AppTheme.darkSurface : AppTheme.lightSurface2;
    final baseColor = isDark
        ? AppTheme.darkTextPrimary.withValues(alpha: 0.92)
        : AppTheme.lightTextPrimary.withValues(alpha: 0.92);
    final taglineColor =
        isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    final letterStyle = GoogleFonts.spaceGrotesk(
      fontSize: 64,
      fontWeight: FontWeight.w600,
      letterSpacing: -1.2,
      height: 1.0,
      color: baseColor,
    );

    return Scaffold(
      body: Stack(children: [
        AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [bgTop, bgBottom],
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 110,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Subtle radial glow — much softer than before
                        Opacity(
                          opacity: _glowFade.value * 0.22,
                          child: Container(
                            width: 280,
                            height: 180,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  AppTheme.brand.withValues(alpha: 0.35),
                                  AppTheme.brand.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Per-letter reveal
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            for (int i = 0; i < _word.length; i++)
                              FadeTransition(
                                opacity: _letterFade(i, _word.length),
                                child: SlideTransition(
                                  position: _letterSlide(i, _word.length),
                                  child: Text(_word[i], style: letterStyle),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Underline draw-in
                  SizedBox(
                    width: 180,
                    height: 2,
                    child: Align(
                      alignment: Alignment.center,
                      child: FractionallySizedBox(
                        widthFactor: _underlineSweep.value,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            gradient: LinearGradient(
                              colors: [
                                const Color(0x000EA5E9),
                                AppTheme.brand.withValues(alpha: 0.7),
                                const Color(0x000EA5E9),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  FadeTransition(
                    opacity: _taglineFade,
                    child: SlideTransition(
                      position: _taglineSlide,
                      child: Text(
                        'Powering your property universe',
                        style: GoogleFonts.inter(
                          color: taglineColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 2.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      const Positioned.fill(child: _DebugLogPanel()),
      ]),
    );
  }
}

class _DebugLogPanel extends StatelessWidget {
  const _DebugLogPanel();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(maxHeight: 260),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('debug log',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                  TextButton(
                    onPressed: () async {
                      await Clipboard.setData(
                          ClipboardData(text: DebugLog.instance.dump()));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('log copied'),
                                duration: Duration(seconds: 1)));
                      }
                    },
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: const Text('copy',
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ],
              ),
              Flexible(
                child: ValueListenableBuilder<List<String>>(
                  valueListenable: DebugLog.instance.entries,
                  builder: (context, lines, _) {
                    return SingleChildScrollView(
                      reverse: true,
                      child: Text(
                        lines.join('\n'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontFamily: 'monospace',
                            height: 1.3),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
