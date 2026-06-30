import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corex_mobile/screens/splash_screen.dart';

void main() {
  testWidgets('splash screen renders the CoreX wordmark',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SplashScreen(onFinished: () {}),
    ));
    await tester.pump();

    // The wordmark is revealed letter-by-letter, so assert on individual
    // glyphs rather than the joined string.
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    expect(find.text('X'), findsOneWidget);

    // Drive the staggered animation (1.7s) plus the chained 350ms post-delay
    // timer to completion. The timer is scheduled by a microtask that only
    // runs after the animation's TickerFuture resolves, so step through
    // several pump boundaries to ensure both the animation and the follow-up
    // timer have fired — otherwise a pending timer trips teardown.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  });
}
