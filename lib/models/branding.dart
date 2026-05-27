import 'package:flutter/material.dart';

/// Branding contract from CoreX OS — four roles plus optional logo.
/// Source endpoints:
///   GET /api/v1/branding/{slug}   (pre-login)
///   GET /api/v1/logged-user       (post-login, branding block)
class Branding {
  final String? logoUrl;
  final Color sidebar;
  final Color icon;
  final Color defaultColor;
  final Color button;
  final Color money;

  const Branding({
    this.logoUrl,
    required this.sidebar,
    required this.icon,
    required this.defaultColor,
    required this.button,
    required this.money,
  });

  /// Hard-coded fallback used on first launch and on request failure.
  static const Branding fallback = Branding(
    sidebar: Color(0xFF0EA5E9),
    icon: Color(0xFF0EA5E9),
    defaultColor: Color(0xFF0B2A4A),
    button: Color(0xFF0EA5E9),
    money: Color(0xFFE8B86D),
  );

  factory Branding.fromJson(Map<String, dynamic> json) {
    final colors = (json['colors'] as Map?) ?? const {};
    return Branding(
      logoUrl: json['logo_url'] as String?,
      sidebar: _parseHex(colors['sidebar'], fallback.sidebar),
      icon: _parseHex(colors['icon'], fallback.icon),
      defaultColor: _parseHex(colors['default'], fallback.defaultColor),
      button: _parseHex(colors['button'], fallback.button),
      money: _parseHex(colors['money'], fallback.money),
    );
  }

  /// WCAG luminance-based on-color picker. Returns black/white.
  static Color onColor(Color bg) {
    final l = bg.computeLuminance();
    return l > 0.5 ? Colors.black : Colors.white;
  }

  Color get onSidebar => onColor(sidebar);
  Color get onIcon => onColor(icon);
  Color get onDefault => onColor(defaultColor);
  Color get onButton => onColor(button);
}

Color _parseHex(dynamic value, Color fallback) {
  if (value is! String) return fallback;
  var s = value.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 6) s = 'FF$s';
  if (s.length != 8) return fallback;
  final n = int.tryParse(s, radix: 16);
  return n == null ? fallback : Color(n);
}

/// ThemeExtension that exposes the four CoreX brand roles to any widget via
/// `Theme.of(context).extension<BrandColors>()` or [BrandColors.of].
@immutable
class BrandColors extends ThemeExtension<BrandColors> {
  final Color sidebar;
  final Color icon;
  final Color defaultColor;
  final Color button;
  final Color money;

  const BrandColors({
    required this.sidebar,
    required this.icon,
    required this.defaultColor,
    required this.button,
    required this.money,
  });

  factory BrandColors.fromBranding(Branding b) => BrandColors(
        sidebar: b.sidebar,
        icon: b.icon,
        defaultColor: b.defaultColor,
        button: b.button,
        money: b.money,
      );

  static BrandColors of(BuildContext context) =>
      Theme.of(context).extension<BrandColors>() ??
      BrandColors.fromBranding(Branding.fallback);

  Color get onSidebar => Branding.onColor(sidebar);
  Color get onIcon => Branding.onColor(icon);
  Color get onDefault => Branding.onColor(defaultColor);
  Color get onButton => Branding.onColor(button);

  @override
  BrandColors copyWith({
    Color? sidebar,
    Color? icon,
    Color? defaultColor,
    Color? button,
    Color? money,
  }) =>
      BrandColors(
        sidebar: sidebar ?? this.sidebar,
        icon: icon ?? this.icon,
        defaultColor: defaultColor ?? this.defaultColor,
        button: button ?? this.button,
        money: money ?? this.money,
      );

  @override
  BrandColors lerp(ThemeExtension<BrandColors>? other, double t) {
    if (other is! BrandColors) return this;
    return BrandColors(
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      icon: Color.lerp(icon, other.icon, t)!,
      defaultColor: Color.lerp(defaultColor, other.defaultColor, t)!,
      button: Color.lerp(button, other.button, t)!,
      money: Color.lerp(money, other.money, t)!,
    );
  }
}
