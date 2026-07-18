import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corex_mobile/screens/coming_soon_screen.dart';

// Matches the ComingSoonScreen page title (28px heading), scoped so it does not
// collide with the nav tab of the same name — the Ellie tab is always shown.
Finder _title(String text) => find.byWidgetPredicate(
      (w) => w is Text && w.data == text && w.style?.fontSize == 28,
    );

void main() {
  testWidgets('ComingSoonScreen renders the feature name and description',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ComingSoonScreen(
        feature: 'Ellie',
        description: 'Your AI assistant for CoreX',
      ),
    ));

    expect(_title('Ellie'), findsOneWidget);
    expect(find.text('COMING SOON'), findsOneWidget);
    expect(find.text('Your AI assistant for CoreX'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
  });

  testWidgets('ComingSoonScreen omits description when not provided',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ComingSoonScreen(feature: 'FICA'),
    ));

    expect(find.text('FICA'), findsOneWidget);
    expect(find.text('COMING SOON'), findsOneWidget);
  });
}
