import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'models/branding.dart';
import 'theme/corex_accent_theme.dart';
import 'theme/corex_tokens.dart';

class AppTheme {
  /// Active branding for the legacy `AppTheme.brand` / `AppTheme.brandDark`
  /// accessors. Updated by [BrandingProvider] every time agency branding
  /// changes so pre-existing screens that haven't migrated to
  /// [BrandColors.of(context)] still re-theme automatically.
  static Branding _activeBranding = Branding.fallback;

  static void updateActiveBranding(Branding b) {
    _activeBranding = b;
  }

  static Color get brand => _activeBranding.button;
  static Color get brandDark => _activeBranding.defaultColor;

  // --- Radius scale -------------------------------------------------------
  // Aligned with the 2026-05-25 CoreX redesign tokens.
  static const double radius = 14.0;
  static const double radiusSmall = 10.0;
  static const double radiusLarge = 20.0;
  static const double radiusButton = 12.0;
  static const double radiusChip = 999.0;

  // --- Dark palette (aligned with CorexTokens) ---------------------------
  static const Color darkBackground = Color(0xFF0A0F1C);
  static const Color darkSurface = Color(0xFF131A2A);
  static const Color darkSurface2 = Color(0xFF1B2440);
  static const Color darkBorder = Color(0x0AFFFFFF);
  static const Color darkTextPrimary = Color(0xFFF5F7FB);
  static const Color darkTextSecondary = Color(0xFF8B9AB5);
  static const Color darkTextMuted = Color(0xFF5C6B85);

  // --- Light palette ------------------------------------------------------
  static const Color lightBackground = Color(0xFFFAFAF7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurface2 = Color(0xFFF2F4F9);
  static const Color lightBorder = Color(0x14000000);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF64748B);
  static const Color lightTextMuted = Color(0xFF9CA3AF);

  // --- Theme-aware accessors ---------------------------------------------
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color background(BuildContext context) =>
      isDark(context) ? darkBackground : lightBackground;
  static Color surface(BuildContext context) =>
      isDark(context) ? darkSurface : lightSurface;
  static Color surface2(BuildContext context) =>
      isDark(context) ? darkSurface2 : lightSurface2;
  static Color borderColor(BuildContext context) =>
      isDark(context) ? darkBorder : lightBorder;
  static Color textPrimary(BuildContext context) =>
      isDark(context) ? darkTextPrimary : lightTextPrimary;
  static Color textSecondary(BuildContext context) =>
      isDark(context) ? darkTextSecondary : lightTextSecondary;
  static Color textMuted(BuildContext context) =>
      isDark(context) ? darkTextMuted : lightTextMuted;

  /// Standard soft drop-shadow for cards and surfaces.
  static List<BoxShadow> softShadow(BuildContext context) {
    final dark = isDark(context);
    return [
      BoxShadow(
        color: dark
            ? Colors.black.withValues(alpha: 0.45)
            : Colors.black.withValues(alpha: 0.05),
        blurRadius: 24,
        spreadRadius: -4,
        offset: const Offset(0, 8),
      ),
    ];
  }

  /// Colored halo — used on hero CTAs, logos, active tabs. Pass a brand
  /// colour. Intensity tunes alpha for restraint vs. drama.
  static List<BoxShadow> brandGlow(
    Color color, {
    double intensity = 0.45,
    double blur = 32,
    double spread = -4,
    Offset offset = const Offset(0, 8),
  }) =>
      [
        BoxShadow(
          color: color.withValues(alpha: intensity),
          blurRadius: blur,
          spreadRadius: spread,
          offset: offset,
        ),
        BoxShadow(
          color: color.withValues(alpha: intensity * 0.45),
          blurRadius: blur * 2,
          spreadRadius: spread - 4,
          offset: Offset(offset.dx, offset.dy * 1.5),
        ),
      ];

  /// Subtle top-to-bottom gradient used on standard cards/tiles. In dark
  /// mode it adds a faint highlight at the top edge — fakes a light source.
  static Gradient cardGradient(BuildContext context) {
    final dark = isDark(context);
    if (dark) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1B2440), Color(0xFF131A2A)],
      );
    }
    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFFFFFF), Color(0xFFF7F8FB)],
    );
  }

  /// Brand-tinted gradient for hero surfaces (greeting card, etc).
  /// Source colour is read from active branding so each tenant gets its own
  /// halo without any hardcoded blue.
  static Gradient heroGradient(BuildContext context, Color brand) {
    final dark = isDark(context);
    if (dark) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(darkSurface, brand, 0.18)!,
          Color.lerp(darkSurface, brand, 0.04)!,
        ],
      );
    }
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        brand.withValues(alpha: 0.10),
        brand.withValues(alpha: 0.03),
      ],
    );
  }

  // --------------- ThemeData builders -----------------------------------

  static ThemeData dark(Branding branding) => _buildTheme(
        brightness: Brightness.dark,
        branding: branding,
        background: darkBackground,
        surface: darkSurface,
        surface2: darkSurface2,
        border: darkBorder,
        textPrimary: darkTextPrimary,
        textSecondary: darkTextSecondary,
      );

  static ThemeData light(Branding branding) => _buildTheme(
        brightness: Brightness.light,
        branding: branding,
        background: lightBackground,
        surface: lightSurface,
        surface2: lightSurface2,
        border: lightBorder,
        textPrimary: lightTextPrimary,
        textSecondary: lightTextSecondary,
      );

  static ThemeData get darkTheme => dark(Branding.fallback);
  static ThemeData get lightTheme => light(Branding.fallback);

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Branding branding,
    required Color background,
    required Color surface,
    required Color surface2,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final base =
        brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light();

    final body = GoogleFonts.interTextTheme(base.textTheme);
    final display = GoogleFonts.plusJakartaSansTextTheme(base.textTheme);

    final mergedText = body.copyWith(
      displayLarge: display.displayLarge?.copyWith(
          fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -1.0),
      displayMedium: display.displayMedium?.copyWith(
          fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.8),
      displaySmall: display.displaySmall?.copyWith(
          fontWeight: FontWeight.w700, color: textPrimary, letterSpacing: -0.6),
      headlineLarge: display.headlineLarge?.copyWith(
          fontWeight: FontWeight.w700, color: textPrimary, letterSpacing: -0.5),
      headlineMedium: display.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700, color: textPrimary, letterSpacing: -0.4),
      headlineSmall: display.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700, color: textPrimary, letterSpacing: -0.3),
      titleLarge: display.titleLarge?.copyWith(
          fontWeight: FontWeight.w700, color: textPrimary, letterSpacing: -0.2),
      titleMedium: body.titleMedium
          ?.copyWith(fontWeight: FontWeight.w600, color: textPrimary),
      bodyLarge: body.bodyLarge?.copyWith(color: textPrimary, height: 1.4),
      bodyMedium: body.bodyMedium?.copyWith(color: textPrimary, height: 1.4),
    );

    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: branding.button,
        onPrimary: branding.onButton,
        secondary: branding.icon,
        onSecondary: branding.onIcon,
        surface: surface,
        onSurface: textPrimary,
        error: const Color(0xFFEF4444),
        onError: Colors.white,
      ),
      textTheme: mergedText,
      cardTheme: CardThemeData(
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(radius)),
          side: BorderSide(color: border),
        ),
        elevation: 0,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: branding.button,
          foregroundColor: branding.onButton,
          textStyle: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusButton),
          ),
          minimumSize: const Size(double.infinity, 56),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          backgroundColor: surface2,
          side: BorderSide.none,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusButton),
          ),
          minimumSize: const Size(double.infinity, 56),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: branding.button,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.7)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusButton),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusButton),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusButton),
          borderSide: BorderSide(color: branding.icon, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      ),
      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(6),
        thumbColor: WidgetStateProperty.all(
          brightness == Brightness.dark
              ? darkTextSecondary
              : lightTextSecondary,
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[
        BrandColors.fromBranding(branding),
        CorexAccentTheme.fromBranding(branding),
        brightness == Brightness.light
            ? CorexTokens.lightPalette
            : CorexTokens.darkPalette,
      ],
    );
  }
}
