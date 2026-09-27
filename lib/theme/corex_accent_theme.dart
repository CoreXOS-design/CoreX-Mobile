import 'package:flutter/material.dart';

import '../models/branding.dart';

/// ThemeExtension that exposes per-agency accent + money colors plus their
/// derived alpha steps. Every CoreX* widget reads from here — none accept a
/// raw [Color] for the accent.
///
/// Sourced from the agency [Branding]: `accent = branding.button`,
/// `accentMoney = branding.money`. Falls back to [Branding.fallback] when
/// the extension isn't present.
@immutable
class CorexAccentTheme extends ThemeExtension<CorexAccentTheme> {
  final Color accent;
  final Color accentMoney;

  const CorexAccentTheme({required this.accent, required this.accentMoney});

  factory CorexAccentTheme.fromBranding(Branding b) =>
      CorexAccentTheme(accent: b.button, accentMoney: b.money);

  factory CorexAccentTheme.defaults() =>
      CorexAccentTheme.fromBranding(Branding.fallback);

  Color get accentSoft => accent.withValues(alpha: 0.15);
  Color get accentGlow => accent.withValues(alpha: 0.25);
  Color get accentBorder => accent.withValues(alpha: 0.40);
  Color get moneySoft => accentMoney.withValues(alpha: 0.15);
  Color get moneyGlow => accentMoney.withValues(alpha: 0.30);

  /// The accent, darkened just enough to be legible as TEXT on a light
  /// surface. The raw accent is tuned for dark backgrounds — the default
  /// sky `#0EA5E9` only reaches 2.4:1 on white, well under AA.
  ///
  /// Darkens in HSL so the agency keeps its hue: a brand that already
  /// passes comes back untouched. Use it for text and icons on a light
  /// surface; keep [accent] for fills, where the on-colour does the work.
  Color get accentText => _readableOnLight(accent);

  /// [accentMoney] is a pale gold by default — around 1.7:1 on white — so it
  /// needs the same treatment wherever it carries text rather than a fill.
  Color get moneyText => _readableOnLight(accentMoney);

  /// Black or white, whichever is legible on a filled [accentMoney] chip.
  Color get onMoney =>
      accentMoney.computeLuminance() > 0.5 ? Colors.black : Colors.white;

  static Color _readableOnLight(Color c) {
    if (_contrastOnWhite(c) >= 4.5) return c;
    var hsl = HSLColor.fromColor(c);
    // ~24 steps to reach black in the worst case; bounded so a pathological
    // brand colour can't spin here.
    while (hsl.lightness > 0.04) {
      hsl = hsl.withLightness((hsl.lightness - 0.04).clamp(0.0, 1.0));
      final next = hsl.toColor();
      if (_contrastOnWhite(next) >= 4.5) return next;
    }
    return hsl.toColor();
  }

  static double _contrastOnWhite(Color c) => 1.05 / (c.computeLuminance() + 0.05);

  static CorexAccentTheme of(BuildContext context) =>
      Theme.of(context).extension<CorexAccentTheme>() ??
      CorexAccentTheme.defaults();

  @override
  CorexAccentTheme copyWith({Color? accent, Color? accentMoney}) =>
      CorexAccentTheme(
        accent: accent ?? this.accent,
        accentMoney: accentMoney ?? this.accentMoney,
      );

  @override
  CorexAccentTheme lerp(ThemeExtension<CorexAccentTheme>? other, double t) {
    if (other is! CorexAccentTheme) return this;
    return CorexAccentTheme(
      accent: Color.lerp(accent, other.accent, t)!,
      accentMoney: Color.lerp(accentMoney, other.accentMoney, t)!,
    );
  }
}
