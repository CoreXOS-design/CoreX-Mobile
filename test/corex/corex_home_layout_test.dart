import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabler_icons/tabler_icons.dart';

import 'package:corex_mobile/screens/home/home_screen.dart';
import 'package:corex_mobile/theme/corex_accent_theme.dart';
import 'package:corex_mobile/theme/corex_tokens.dart';
import 'package:corex_mobile/widgets/corex/corex_bottom_nav.dart';
import 'package:corex_mobile/widgets/corex/corex_ellie_card.dart';
import 'package:corex_mobile/widgets/corex/corex_module_tile.dart';

/// Layout guards for the Studio home restyle.
///
/// The nav puts one intrinsically-sized pill next to four Expanded icons, and
/// the workspace grid runs on a fixed aspect ratio — both overflow quietly on
/// a narrow screen or a large text scale if the numbers drift.
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

  group('CorexBottomNav', () {
    // "Calendar" is the longest label, so it's the worst case for the pill.
    for (final tab in CorexNavTab.values) {
      testWidgets(
          'lays out without overflow with $tab active on a 360px screen',
          (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          pump(Align(
            alignment: Alignment.bottomCenter,
            child: CorexBottomNav(active: tab, onTap: (_) {}),
          )),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('labels only the active tab', (tester) async {
      await tester.pumpWidget(
        pump(CorexBottomNav(active: CorexNavTab.home, onTap: (_) {})),
      );
      await tester.pump();

      expect(find.text('Home'), findsOneWidget);
      // The other four collapse to icons, reachable by their Semantics label
      // rather than visible text.
      expect(find.text('Calendar'), findsNothing);
      expect(find.text('Me'), findsNothing);
    });

    testWidgets('survives a 1.6x text scale', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: pump(Align(
            alignment: Alignment.bottomCenter,
            child: CorexBottomNav(active: CorexNavTab.calendar, onTap: (_) {}),
          )),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('CorexModuleTile', () {
    testWidgets('a 2-up grid of tiles fits its aspect ratio', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(pump(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: GridView(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              // The floor the grid clamps to — the tightest a tile ever gets.
              mainAxisExtent: kHomeModuleTileMinHeight,
            ),
            children: [
              CorexModuleTile(
                icon: TablerIcons.building_skyscraper,
                label: 'Properties',
                onTap: () {},
              ),
              CorexModuleTile(
                icon: TablerIcons.target_arrow,
                label: 'Portal Leads',
                subtitle: '4 unread',
                dot: true,
                useMoneyAccent: true,
                onTap: () {},
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Squeezed to the floor, the tile drops its count line to stay inside
      // its box — the label is the part that has to survive.
      expect(find.text('Portal Leads'), findsOneWidget);
      expect(find.text('4 unread'), findsNothing);
    });

    testWidgets('keeps the count line when it has room', (tester) async {
      await tester.pumpWidget(pump(
        SizedBox(
          width: 160,
          height: kHomeModuleTileMaxHeight,
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

      expect(tester.takeException(), isNull);
      expect(find.text('4 unread'), findsOneWidget);
    });

    // Home gives the grid whatever height is left, so a tile can be handed
    // anything from the floor upwards. It must fit at every one of them —
    // the grid is NeverScrollable, so an overflow has nowhere to go.
    testWidgets('fits at every height between the floor and the ceiling',
        (tester) async {
      for (var h = kHomeModuleTileMinHeight;
          h <= kHomeModuleTileMaxHeight;
          h += 4) {
        await tester.pumpWidget(pump(
          SizedBox(
            width: 160,
            height: h,
            // The worst case: the one tile that carries a count line.
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
      }
    });

    testWidgets('omits the count line when there is no real number',
        (tester) async {
      await tester.pumpWidget(pump(
        SizedBox(
          width: 160,
          height: 112,
          child: CorexModuleTile(
            icon: TablerIcons.users,
            label: 'Contacts',
            onTap: () {},
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('Contacts'), findsOneWidget);
      // One Text in the tile — the label. No placeholder subtitle.
      expect(
          find.descendant(
            of: find.byType(CorexModuleTile),
            matching: find.byType(Text),
          ),
          findsOneWidget);
    });
  });

  group('CorexEllieCard', () {
    testWidgets('renders the daily quote in both brightnesses', (tester) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(pump(
          SizedBox(
            width: 354,
            child: CorexEllieCard(
              onTap: () {},
              date: DateTime(2026, 9, 27),
            ),
          ),
          brightness: brightness,
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'in $brightness');
        expect(find.text('Meet Ellie'), findsOneWidget);
        expect(find.text('ELLIE · DAILY'), findsOneWidget);
      }
    });
  });
}
