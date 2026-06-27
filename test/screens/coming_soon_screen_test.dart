import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:corex_mobile/providers/feature_flags_provider.dart';
import 'package:corex_mobile/screens/coming_soon_screen.dart';

// ComingSoonScreen renders CorexBottomNav, which reads FeatureFlagsProvider.
Widget _wrap(Widget child) => ChangeNotifierProvider(
      create: (_) => FeatureFlagsProvider(),
      child: child,
    );

void main() {
  testWidgets('ComingSoonScreen renders the feature name and description',
      (tester) async {
    await tester.pumpWidget(_wrap(const MaterialApp(
      home: ComingSoonScreen(
        feature: 'Ellie',
        description: 'Your AI assistant for CoreX',
      ),
    )));

    expect(find.text('Ellie'), findsOneWidget);
    expect(find.text('COMING SOON'), findsOneWidget);
    expect(find.text('Your AI assistant for CoreX'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
  });

  testWidgets('ComingSoonScreen omits description when not provided',
      (tester) async {
    await tester.pumpWidget(_wrap(const MaterialApp(
      home: ComingSoonScreen(feature: 'FICA'),
    )));

    expect(find.text('FICA'), findsOneWidget);
    expect(find.text('COMING SOON'), findsOneWidget);
  });
}
