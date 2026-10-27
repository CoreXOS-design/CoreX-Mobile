import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corex_mobile/screens/rentals/widgets/rentals_actions.dart';
import 'package:corex_mobile/screens/rentals/widgets/rentals_ui.dart';
import 'package:corex_mobile/services/rentals/rentals_http.dart';

/// Mobile rentals parity (hfc-dash `.ai/specs/at-508-mobile-parity-addendum.md`):
/// the phone shows what the server decided and works out nothing itself.
void main() {
  group('condition colours come from condition_states.severity', () {
    final states = <Map<String, dynamic>>[
      {'key': 'good', 'label': 'Good', 'severity': 'blue'},
      {'key': 'damaged', 'label': 'Damaged', 'severity': 'red'},
      {'key': 'stained', 'label': 'Stained', 'severity': 'amber'},
      {'key': 'na', 'label': 'N/A', 'severity': 'grey'},
      {'key': 'odd', 'label': 'Odd', 'severity': 'purple'},
    ];

    test('each severity has the web colour', () {
      expect(conditionColor(states, 'good'), const Color(0xFF0EA5E9));
      expect(conditionColor(states, 'damaged'), const Color(0xFFC41E3A));
      expect(conditionColor(states, 'stained'), const Color(0xFFF59E0B));
      expect(conditionColor(states, 'na'), const Color(0xFF6B7280));
    });

    test('an unknown key or an unknown severity is red, as on the web', () {
      expect(conditionColor(states, 'never-heard-of-it'), const Color(0xFFC41E3A));
      expect(conditionColor(states, 'odd'), const Color(0xFFC41E3A));
      expect(conditionColor(const <Map<String, dynamic>>[], 'good'), const Color(0xFFC41E3A));
    });

    test('labels are the agency\'s, the key only as a last resort', () {
      expect(conditionLabel(states, 'damaged'), 'Damaged');
      expect(conditionLabel(states, 'gone'), 'gone');
    });
  });

  group('a new record\'s id is read from the web redirect', () {
    test('last number in the path', () {
      expect(idFromRedirect('/corex/rental-applications/57'), 57);
      expect(idFromRedirect('https://x.co/corex/leases/12#draft-follow-up'), 12);
      expect(idFromRedirect('/corex/rental-work-orders/9/edit'), 9);
      expect(idFromRedirect('/corex/rental-inspections/3/rooms/8'), 8);
    });

    test('no id when the redirect names no record', () {
      expect(idFromRedirect('/corex/rental-applications'), isNull);
      expect(idFromRedirect(null), isNull);
      expect(idFromRedirect(42), isNull);
    });
  });

  group('a 403 hides the button for the session', () {
    test('marked keys are remembered, others are not', () {
      RentalsDenied.mark('inspection.cancel');
      expect(RentalsDenied.has('inspection.cancel'), isTrue);
      expect(RentalsDenied.has('inspection.archive'), isFalse);
      expect(RentalsDenied.has(null), isFalse);
    });

    testWidgets('a denied button is gone, not greyed', (tester) async {
      RentalsDenied.mark('x.denied');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            ServerActionButton(
                icon: Icons.close, label: 'Hidden', denyKey: 'x.denied', onPressed: () {}),
            ServerActionButton(
                icon: Icons.check, label: 'Shown', denyKey: 'x.allowed', onPressed: () {}),
          ]),
        ),
      ));
      expect(find.text('Hidden'), findsNothing);
      expect(find.text('Shown'), findsOneWidget);
    });

    testWidgets('no signal disables the actions with a plain line', (tester) async {
      RentalsHttp.instance.reachable.value = false;
      addTearDown(() => RentalsHttp.instance.reachable.value = true);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RentalsActionsSection(actions: [
            ServerActionButton(icon: Icons.check, label: 'Do it', onPressed: () {}),
          ]),
        ),
      ));
      expect(find.text(kNeedsSignal), findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(find.byWidgetPredicate(
          (w) => w is ButtonStyleButton));
      expect(button.onPressed, isNull);
    });
  });

  group('action forms show the server\'s answer', () {
    Future<void> open(WidgetTester tester,
        Future<Map<String, dynamic>> Function(ActionFormValues) submit) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showActionForm(context,
                  title: 'Cancel this inspection',
                  fields: const [
                    ActionField('cancel_reason', 'Why?',
                        kind: ActionFieldKind.multiline, required: true),
                  ],
                  submit: submit),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Tenant away');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
    }

    testWidgets('422: the error sits under its field, the sheet stays', (tester) async {
      await open(
          tester,
          (_) async => throw RentalsApiException(422, 'The reason is too short.',
              fieldErrors: {'cancel_reason': 'The reason is too short.'}));
      expect(find.text('Cancel this inspection'), findsOneWidget);
      expect(find.text('The reason is too short.'), findsOneWidget);
    });

    testWidgets('409: the web\'s own sentence, unchanged', (tester) async {
      await open(
          tester,
          (_) async => throw RentalsApiException(
              409, 'Cannot cancel an inspection that is completed.',
              code: 'not_recordable'));
      expect(find.text('Cannot cancel an inspection that is completed.'), findsOneWidget);
    });

    testWidgets('success: the server\'s message, then the yellow warning', (tester) async {
      Map<String, dynamic>? sent;
      await open(tester, (v) async {
        sent = v.values;
        return {
          'ok': true,
          'message': 'Inspection cancelled.',
          'warning': 'The tenant has no email address.',
        };
      });
      expect(sent, {'cancel_reason': 'Tenant away'});
      expect(find.text('Cancel this inspection'), findsNothing);
      expect(find.text('Inspection cancelled.'), findsOneWidget);
    });
  });
}
