import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corex_mobile/screens/coming_soon_screen.dart';
import 'package:corex_mobile/screens/splash_screen.dart';
import 'package:corex_mobile/widgets/corex/corex_scaffold.dart';
import 'package:corex_mobile/widgets/ui/auth_scaffold.dart';
import 'package:corex_mobile/widgets/ui/content_width.dart';

/// iPad Air 11" (M3) — the device App Review tested on.
const Size kIpadLandscape = Size(1180, 820);
const Size kIpadPortrait = Size(820, 1180);

/// Smallest screen we still support, where vertical overflow is likeliest.
const Size kSmallPhoneLandscape = Size(667, 375);

Future<void> _pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pump();
}

/// Width of the laid-out content column.
double _widthOf(WidgetTester tester, Finder finder) =>
    tester.getSize(finder.first).width;

void main() {
  group('content is measured, not stretched, on a wide viewport', () {
    testWidgets('AuthScaffold caps its column at the form width',
        (tester) async {
      await _pumpAt(
        tester,
        kIpadLandscape,
        const AuthScaffold(
          title: 'Sign in',
          subtitle: 'Enter the email your agent has on file',
          child: TextField(key: Key('field')),
        ),
      );

      // Regression: this used to be a bare ConstrainedBox, which is silently
      // discarded under the tight width a scroll view passes down, leaving the
      // whole auth form stretched across the iPad.
      final fieldWidth = _widthOf(tester, find.byKey(const Key('field')));
      expect(fieldWidth, lessThanOrEqualTo(ContentWidth.formWidth));
    });

    testWidgets('AuthScaffold still fills a phone width', (tester) async {
      await _pumpAt(
        tester,
        const Size(390, 844),
        const AuthScaffold(
          title: 'Sign in',
          child: TextField(key: Key('field')),
        ),
      );

      // 390 minus the scaffold's 28pt horizontal padding on each side.
      expect(_widthOf(tester, find.byKey(const Key('field'))), 390 - 56);
    });

    testWidgets('CorexScaffold caps its body at the page width',
        (tester) async {
      await _pumpAt(
        tester,
        kIpadLandscape,
        const CorexScaffold(
          title: 'Property',
          body: SizedBox.expand(child: ColoredBox(color: Colors.red)),
        ),
      );

      expect(
        _widthOf(tester, find.byType(SizedBox).last),
        lessThanOrEqualTo(ContentWidth.page),
      );
    });

    testWidgets('ContentWidth is a no-op below its cap', (tester) async {
      await _pumpAt(
        tester,
        const Size(390, 844),
        const ContentWidth(child: SizedBox(key: Key('c'), height: 10)),
      );
      // Loose constraints — the child keeps its own width rather than being
      // forced to the cap.
      expect(tester.getSize(find.byKey(const Key('c'))).width, lessThan(390));
    });
  });

  group('no overflow at review-device sizes', () {
    // A RenderFlex overflow raises a FlutterError, which fails the test —
    // these pumps are the assertion.
    for (final entry in {
      'iPad landscape': kIpadLandscape,
      'iPad portrait': kIpadPortrait,
      'small phone landscape': kSmallPhoneLandscape,
    }.entries) {
      testWidgets('SplashScreen lays out at ${entry.key}', (tester) async {
        await _pumpAt(tester, entry.value, SplashScreen(onFinished: () {}));
      });

      testWidgets('ComingSoonScreen lays out at ${entry.key}', (tester) async {
        await _pumpAt(
          tester,
          entry.value,
          const ComingSoonScreen(
            feature: 'Ellie',
            description: 'Your AI assistant for CoreX',
          ),
        );
      });

      testWidgets('CorexScaffold lays out at ${entry.key}', (tester) async {
        await _pumpAt(
          tester,
          entry.value,
          CorexScaffold(
            title: 'A rather long property title that must ellipsize',
            body: ListView(
              children: List.generate(
                30,
                (i) => ListTile(title: Text('Row $i')),
              ),
            ),
            bottomBar: const SizedBox(height: 56),
          ),
        );
      });

      // EllieScreen is deliberately absent: AuthProvider builds a
      // MessagingService in its field initialiser, which needs a live Firebase
      // app, so the screen can't be pumped without a Firebase test harness.
      testWidgets('AuthScaffold lays out at ${entry.key}', (tester) async {
        await _pumpAt(
          tester,
          entry.value,
          const AuthScaffold(
            title: 'Verify your email',
            subtitle: 'We sent a six digit code to your inbox.',
            child: Column(
              children: [
                TextField(),
                SizedBox(height: 16),
                TextField(),
              ],
            ),
          ),
        );
      });
    }
  });
}
