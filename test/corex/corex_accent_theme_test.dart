import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:corex_mobile/providers/feature_flags_provider.dart';
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
    // CorexBottomNav reads FeatureFlagsProvider (to gate the Ellie tab), so the
    // provider must sit above the MaterialApp in the test tree.
    return ChangeNotifierProvider(
      create: (_) => FeatureFlagsProvider(),
      child: MaterialApp(
        theme: ThemeData(
          extensions: const [
            CorexAccentTheme(accent: purple, accentMoney: Color(0xFFE8B86D)),
          ],
        ),
        home: Scaffold(body: child),
      ),
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
}

