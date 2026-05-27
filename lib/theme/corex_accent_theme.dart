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
