import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabler_icons/tabler_icons.dart';

import 'package:corex_mobile/screens/home/home_screen.dart';
import 'package:corex_mobile/theme/corex_accent_theme.dart';
import 'package:corex_mobile/theme/corex_tokens.dart';
import 'package:corex_mobile/widgets/client/client_bottom_nav.dart';
import 'package:corex_mobile/widgets/corex/corex_ellie_card.dart';
import 'package:corex_mobile/widgets/corex/corex_home_header.dart';
import 'package:corex_mobile/widgets/corex/corex_module_tile.dart';

/// Regression guards for the short-phone Home layout: with the Next
/// appointment hero in its tall state the Workspace grid used to be cut off
/// at the bottom, because the tiles couldn't go below 92 px and the page
/// doesn't scroll. The grid may now squeeze tiles down to the compact floor,
/// and Home drops Ellie's daily line on short windows.
void main() {
  Widget pump(Widget child, {Brightness brightness = Brightness.dark}) {
    return MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        extensions: [
          const CorexAccentTheme(
            accent: Color(0xFF0EA5E9),
            accentMoney: Color(0xFFE8B86D),
          ),
          brightness == Brightness.dark
              ? CorexTokens.darkPalette
              : CorexTokens.lightPalette,
        ],
      ),
      home: Scaffold(body: child),
    );
  }

  group('CorexModuleTile compact', () {
    testWidgets('fits at every height from the compact floor up',
        (tester) async {
      for (var h = kHomeModuleTileCompactHeight;
          h <= kHomeModuleTileMaxHeight;
          h += 2) {
        await tester.pumpWidget(pump(
          SizedBox(
            width: 160,
            height: h,
            child: CorexModuleTile(
              icon: TablerIcons.target_arrow,
              label: 'Portal Leads',
              subtitle: '4 unread',
              dot: true,
              useMoneyAccent: true,
              onTap: () {},
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'overflowed at ${h}px');
        expect(find.text('Portal Leads'), findsOneWidget,
            reason: 'label lost at ${h}px');
      }
    });

    testWidgets('a 2x2 grid at the compact floor fits a 360px screen',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(pump(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: GridView(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: kHomeModuleTileCompactHeight,
            ),
            children: [
              for (final l in ['Properties', 'Contacts', 'Core Matches', 'Portal Leads'])
                CorexModuleTile(
                  icon: TablerIcons.users,
                  label: l,
                  onTap: () {},
                ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Portal Leads'), findsOneWidget);
    });
  });

  group('CorexEllieCard', () {
    testWidgets('drops the daily line when showQuote is false', (tester) async {
      await tester.pumpWidget(pump(
        SizedBox(
          width: 354,
          child: CorexEllieCard(
            onTap: () {},
            date: DateTime(2026, 9, 27),
            showQuote: false,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Meet Ellie'), findsOneWidget);
      expect(find.text('ELLIE · DAILY'), findsNothing);
    });
  });

  group('Client shell', () {
    testWidgets('bottom nav labels only the active tab and lays out at 360px',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      for (final tab in ClientNavTab.values) {
        await tester.pumpWidget(pump(Align(
          alignment: Alignment.bottomCenter,
          child: ClientBottomNav(active: tab, onTap: (_) {}),
        )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'with $tab active');
      }
      // Profile active: only its label is visible.
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Home'), findsNothing);
    });

    testWidgets('home header renders an initials button and the greeting',
        (tester) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(pump(
          Padding(
            padding: const EdgeInsets.all(18),
            child: CorexHomeHeader(
              agencyName: 'Mobile Agency Demo',
              greeting: 'Good afternoon, Thandi',
              onMenuTap: () {},
              actions: [
                CorexHeaderButton(label: 'TM', tooltip: 'Profile', onTap: () {}),
                CorexHeaderButton(
                    icon: TablerIcons.bell,
                    tooltip: 'Notifications',
                    badge: 24,
                    onTap: () {}),
              ],
            ),
          ),
          brightness: brightness,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'in $brightness');
        expect(find.text('TM'), findsOneWidget);
        expect(find.text('24'), findsOneWidget);
        expect(find.text('Good afternoon, Thandi'), findsOneWidget);
      }
    });
  });
}
