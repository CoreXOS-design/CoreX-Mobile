import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corex_mobile/theme/corex_accent_theme.dart';
import 'package:corex_mobile/widgets/corex/corex_primary_button.dart';
import 'package:corex_mobile/widgets/corex/corex_ellie_teaser.dart';
import 'package:corex_mobile/widgets/corex/corex_bottom_nav.dart';

/// Proves the redesign is genuinely API-driven: pump the widgets under a
/// CorexAccentTheme with a purple accent. The primary button's gradient,
/// the Ellie teaser's border, and the active nav item's icon all must be
/// purple. None of them are allowed to be teal (the fallback).
void main() {
  const purple = Color(0xFF7C3AED);

  Widget pump(Widget child) {
    return MaterialApp(
      theme: ThemeData(
        extensions: const [
          CorexAccentTheme(accent: purple, accentMoney: Color(0xFFE8B86D)),
        ],
      ),
      home: Scaffold(body: child),
    );
  }

  testWidgets('CorexPrimaryButton picks up purple accent from theme',
      (tester) async {
    await tester.pumpWidget(pump(
      CorexPrimaryButton(label: 'Go', onPressed: () {}),
    ));
    await tester.pump();

    final ink = tester.widget<Ink>(find.byType(Ink).first);
    final deco = ink.decoration as BoxDecoration;
    final gradient = deco.gradient as LinearGradient;

    // Every gradient stop must read as purple-family: blue > red > green.
    // Teal would have green > red, so this assertion rejects the teal fallback.
    for (final c in gradient.colors) {
      expect(c.b > c.r, isTrue, reason: 'lost purple, got $c');
      expect(c.r > c.g, isTrue, reason: 'lost purple, got $c');
    }
  });

  testWidgets('CorexEllieTeaser border resolves to purple', (tester) async {
    await tester.pumpWidget(pump(CorexEllieTeaser(onTap: () {})));
    await tester.pump();

    final containers = tester.widgetList<Ink>(find.byType(Ink));
    final ellie = containers.firstWhere(
      (i) => (i.decoration as BoxDecoration?)?.border != null,
    );
    final deco = ellie.decoration as BoxDecoration;
    final border = deco.border as Border;
    expect(border.top.color.r, purple.r);
    expect(border.top.color.g, purple.g);
    expect(border.top.color.b, purple.b);
  });

  testWidgets('CorexBottomNav active tab uses purple accent', (tester) async {
    await tester.pumpWidget(pump(
      CorexBottomNav(active: CorexNavTab.home, onTap: (_) {}),
    ));
    await tester.pump();

    // The Home label is rendered with the accent color when active.
    final homeText = tester.widget<Text>(find.text('Home'));
    expect(homeText.style!.color!.r, purple.r);
    expect(homeText.style!.color!.g, purple.g);
    expect(homeText.style!.color!.b, purple.b);
  });

  // `accentText` / `moneyText` exist so light surfaces stay legible WITHOUT
  // falling back to a fixed brand colour — an earlier pass hardcoded navy
  // here and silently dropped per-agency theming.
  group('readable-on-light accent variants', () {
    double contrastOnWhite(Color c) => 1.05 / (c.computeLuminance() + 0.05);

    test('leaves an accent that already passes AA untouched', () {
      const theme =
          CorexAccentTheme(accent: purple, accentMoney: Color(0xFFE8B86D));
      expect(contrastOnWhite(purple), greaterThanOrEqualTo(4.5));
      expect(theme.accentText, purple);
    });

    test('darkens a mid-tone accent until it clears AA, keeping its hue', () {
      // The default CoreX sky: ~2.4:1 on white, nowhere near legible.
      const sky = Color(0xFF0EA5E9);
      const theme =
          CorexAccentTheme(accent: sky, accentMoney: Color(0xFFE8B86D));

      expect(contrastOnWhite(sky), lessThan(4.5));
      expect(contrastOnWhite(theme.accentText), greaterThanOrEqualTo(4.5));

      // Same hue family — darkened, not swapped for a different colour.
      final original = HSLColor.fromColor(sky);
      final adjusted = HSLColor.fromColor(theme.accentText);
      expect((adjusted.hue - original.hue).abs(), lessThan(2.0));
      expect(adjusted.lightness, lessThan(original.lightness));
    });

    test('darkens the pale money gold, which is far below AA on white', () {
      const gold = Color(0xFFE8B86D);
      const theme = CorexAccentTheme(accent: purple, accentMoney: gold);

      expect(contrastOnWhite(gold), lessThan(2.0));
      expect(contrastOnWhite(theme.moneyText), greaterThanOrEqualTo(4.5));
    });

    test('onMoney picks legible digits for light and dark money colours', () {
      const paleGold = CorexAccentTheme(
          accent: purple, accentMoney: Color(0xFFE8B86D));
      const darkMoney = CorexAccentTheme(
          accent: purple, accentMoney: Color(0xFF14532D));

      expect(paleGold.onMoney, Colors.black);
      expect(darkMoney.onMoney, Colors.white);
    });
  });
}

