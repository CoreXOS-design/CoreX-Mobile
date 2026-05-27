import 'package:flutter/material.dart';

/// Platform tokens for the CoreX mobile redesign.
///
/// Resolves dark or light palette via `Theme.of(context).brightness`. The
/// palette itself is exposed as the [CorexPalette] ThemeExtension which is
/// installed on both `AppTheme.dark` and `AppTheme.light`. These tokens are
/// brightness-themed, never tenant-themed — per-agency accent + money colors
/// still live on [CorexAccentTheme].
class CorexTokens {
  CorexTokens._();

  // ── Dark palette (default) ────────────────────────────────────────────
  static const _darkPageBase = Color(0xFF0A0F1C);
  static const _darkPageTopTint = Color(0xFF16243F);
  static const _darkSurfaceTop = Color(0xFF1B2440);
  static const _darkSurfaceBase = Color(0xFF131A2A);
  static const _darkTextPrimary = Color(0xFFF5F7FB);
  static const _darkTextSecondary = Color(0xFF8B9AB5);
  static const _darkTextTertiary = Color(0xFF5C6B85);
  static const _darkTextMuted = Color(0xFF3D4660);

  // ── Light palette ─────────────────────────────────────────────────────
  // Page is intentionally a few shades cooler/darker than the surfaces so
  // white cards have visible contrast against the background.
  static const _lightPageBase = Color(0xFFE4EAF3);
  static const _lightPageTopTint = Color(0xFFD3DCEA);
  static const _lightSurfaceTop = Color(0xFFFFFFFF);
  static const _lightSurfaceBase = Color(0xFFF6F8FC);
  static const _lightTextPrimary = Color(0xFF0B1426);
  static const _lightTextSecondary = Color(0xFF4A5878);
  static const _lightTextTertiary = Color(0xFF7B8AA6);
  static const _lightTextMuted = Color(0xFFB0BACB);

  // ── Brightness-independent semantic colors ────────────────────────────
  static const successDelta = Color(0xFF6BD968);

  // ── Numeric tokens ────────────────────────────────────────────────────
  static const radius = 14.0;
  static const radiusButton = 12.0;

  // ── Context-aware accessors ───────────────────────────────────────────
  static CorexPalette _p(BuildContext c) => CorexPalette.of(c);

  static Color pageBase(BuildContext c) => _p(c).pageBase;
  static Color pageTopTint(BuildContext c) => _p(c).pageTopTint;
  static Color surfaceTop(BuildContext c) => _p(c).surfaceTop;
  static Color surfaceBase(BuildContext c) => _p(c).surfaceBase;
  static Color textPrimary(BuildContext c) => _p(c).textPrimary;
  static Color textSecondary(BuildContext c) => _p(c).textSecondary;
  static Color textTertiary(BuildContext c) => _p(c).textTertiary;
  static Color textMuted(BuildContext c) => _p(c).textMuted;

  static LinearGradient surfaceGradient(BuildContext c) {
    final p = _p(c);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [p.surfaceTop, p.surfaceBase],
    );
  }

  static RadialGradient pageBacklight(BuildContext c) {
    final p = _p(c);
    return RadialGradient(
      center: const Alignment(0, -1),
      radius: 1.1,
      colors: [p.pageTopTint, p.pageBase],
      stops: const [0, 0.55],
    );
  }

  // Palette instances used by AppTheme to install the extension.
  static const CorexPalette darkPalette = CorexPalette(
    pageBase: _darkPageBase,
    pageTopTint: _darkPageTopTint,
    surfaceTop: _darkSurfaceTop,
    surfaceBase: _darkSurfaceBase,
    textPrimary: _darkTextPrimary,
    textSecondary: _darkTextSecondary,
    textTertiary: _darkTextTertiary,
    textMuted: _darkTextMuted,
  );

  static const CorexPalette lightPalette = CorexPalette(
    pageBase: _lightPageBase,
    pageTopTint: _lightPageTopTint,
    surfaceTop: _lightSurfaceTop,
    surfaceBase: _lightSurfaceBase,
    textPrimary: _lightTextPrimary,
    textSecondary: _lightTextSecondary,
    textTertiary: _lightTextTertiary,
    textMuted: _lightTextMuted,
  );
}

/// ThemeExtension carrying the brightness-resolved CoreX palette.
@immutable
class CorexPalette extends ThemeExtension<CorexPalette> {
  final Color pageBase;
  final Color pageTopTint;
  final Color surfaceTop;
  final Color surfaceBase;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textMuted;

  const CorexPalette({
    required this.pageBase,
    required this.pageTopTint,
    required this.surfaceTop,
    required this.surfaceBase,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textMuted,
  });

  static CorexPalette of(BuildContext context) =>
      Theme.of(context).extension<CorexPalette>() ?? CorexTokens.darkPalette;

  @override
  CorexPalette copyWith({
    Color? pageBase,
    Color? pageTopTint,
    Color? surfaceTop,
    Color? surfaceBase,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textMuted,
  }) =>
      CorexPalette(
        pageBase: pageBase ?? this.pageBase,
        pageTopTint: pageTopTint ?? this.pageTopTint,
        surfaceTop: surfaceTop ?? this.surfaceTop,
        surfaceBase: surfaceBase ?? this.surfaceBase,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textTertiary: textTertiary ?? this.textTertiary,
        textMuted: textMuted ?? this.textMuted,
      );

  @override
  CorexPalette lerp(ThemeExtension<CorexPalette>? other, double t) {
    if (other is! CorexPalette) return this;
    return CorexPalette(
      pageBase: Color.lerp(pageBase, other.pageBase, t)!,
      pageTopTint: Color.lerp(pageTopTint, other.pageTopTint, t)!,
      surfaceTop: Color.lerp(surfaceTop, other.surfaceTop, t)!,
      surfaceBase: Color.lerp(surfaceBase, other.surfaceBase, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
    );
  }
}
