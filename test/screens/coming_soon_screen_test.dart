import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corex_mobile/screens/coming_soon_screen.dart';

void main() {
  testWidgets('ComingSoonScreen renders the feature name and description',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ComingSoonScreen(
        feature: 'Ellie',
        description: 'Your AI assistant for CoreX',
      ),
    ));

    expect(find.text('Ellie'), findsOneWidget);
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
