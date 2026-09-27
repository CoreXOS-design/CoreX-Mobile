import 'package:flutter/material.dart';

import '../theme/corex_tokens.dart';
import '../widgets/corex/corex_monogram.dart';

/// Animated app-open splash.
///
/// Sequence:
///   1. The monogram settles in — fade plus a small scale-up
///   2. Wordmark and tagline rise behind it
///   3. A determinate-looking progress bar fills, then [onFinished]
///
/// Replaces the earlier letter-by-letter reveal of "CoreX": at 64 px the
/// staggered glyphs read as the app stuttering rather than as an animation,
/// and it left the brand mark off the one screen guaranteed to be seen.
class SplashScreen extends StatefulWidget {
  final VoidCallback onFinished;

  const SplashScreen({super.key, required this.onFinished});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _markFade;
  late final Animation<double> _markScale;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    );

    _markFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.00, 0.35, curve: Curves.easeOut),
    );
    _markScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.00, 0.45, curve: Curves.easeOutCubic),
      ),
    );

    _textFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.25, 0.60, curve: Curves.easeOut),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.25, 0.60, curve: Curves.easeOutCubic),
      ),
    );

    _progress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.30, 1.00, curve: Curves.easeInOut),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CorexTokens.pageBase(context),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(gradient: CorexTokens.pageBacklight(context)),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Column(
                children: [
                  const Spacer(flex: 3),
                  FadeTransition(
                    opacity: _markFade,
                    child: ScaleTransition(
                      scale: _markScale,
                      child: const CorexMonogram(size: 96),
                    ),
                  ),
                  const SizedBox(height: 26),
                  FadeTransition(
                    opacity: _textFade,
                    child: SlideTransition(
                      position: _textSlide,
                      child: Column(
                        children: [
                          Text(
                            'CoreX',
                            style: TextStyle(
                              color: CorexTokens.textPrimary(context),
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'YOUR REAL ESTATE OS',
                            style: TextStyle(
                              color: CorexTokens.textSecondary(context),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(flex: 4),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(44, 0, 44, 40),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _progress.value,
                            minHeight: 4,
                            backgroundColor: CorexTokens.surfaceTop(context),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Opacity(
                          opacity: _textFade.value,
                          child: Text(
                            'Powering your property universe',
                            style: TextStyle(
                              color: CorexTokens.textSecondary(context),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
