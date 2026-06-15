import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corex_mobile/models/client_models.dart';
import 'package:corex_mobile/screens/client/client_testimonial_form_screen.dart';
import 'package:corex_mobile/screens/client/client_testimonials_screen.dart';
import 'package:corex_mobile/services/api_service.dart'
    show ValidationException;
import 'package:corex_mobile/services/client_auth_service.dart';

/// Fakes the two client testimonial endpoints — overriding the network methods
/// so widget tests never hit http or secure storage.
class _FakeClientApi extends ClientAuthService {
  Object? submitError;
  ClientTestimonial? submitResult;
  ClientTestimonialInput? lastInput;

  List<ClientTestimonial> list;
  Object? listError;

  _FakeClientApi({this.list = const []});

  @override
  Future<ClientTestimonial> submitTestimonial(
      ClientTestimonialInput input) async {
    lastInput = input;
    if (submitError != null) throw submitError!;
    return submitResult ??
        ClientTestimonial(
          id: 1,
          body: input.body,
          rating: input.rating,
          displayName: input.displayName,
        );
  }

  @override
  Future<({int agencyId, List<ClientTestimonial> testimonials})>
      testimonials() async {
    if (listError != null) throw listError!;
    return (agencyId: 5, testimonials: list);
  }
}

Widget _wrap(Widget child) =>
    MaterialApp(theme: ThemeData.dark(), home: child);

void main() {
  testWidgets('submitting a testimonial shows the success confirmation',
      (tester) async {
    final api = _FakeClientApi();

    await tester.pumpWidget(_wrap(
      ClientTestimonialFormScreen(prefillName: 'Bob Buyer', api: api),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextField).first, 'My agent was fantastic.');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send to my agent'));
    await tester.pumpAndSettle();

    expect(api.lastInput?.body, 'My agent was fantastic.');
    expect(find.text('Thanks — sent to your agent'), findsOneWidget);
  });

  testWidgets('required-body 422 maps the error back onto the body field',
      (tester) async {
    final api = _FakeClientApi()
      ..submitError = ValidationException('Validation failed', {
        'body': 'The body field is required.',
      });

    await tester.pumpWidget(_wrap(
      ClientTestimonialFormScreen(api: api),
    ));
    await tester.pumpAndSettle();

    // Body is required — the submit button is disabled while it's empty, so
    // enter text to enable submit, then the server rejects it and we surface
    // the field error inline.
    await tester.enterText(find.byType(TextField).first, 'x');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send to my agent'));
    await tester.pumpAndSettle();

    expect(find.text('The body field is required.'), findsOneWidget);
    // Still on the form (no success view).
    expect(find.text('Thanks — sent to your agent'), findsNothing);
  });

  testWidgets('list shows Live chip only for published testimonials',
      (tester) async {
    final api = _FakeClientApi(list: [
      ClientTestimonial(
        id: 12,
        body: 'Helped us find the perfect home.',
        rating: 5,
        displayName: 'Bob B.',
        published: true,
        createdAt: '2026-06-15T10:00:00Z',
      ),
      ClientTestimonial(
        id: 13,
        body: 'Great communication throughout.',
        rating: 4,
        displayName: 'Bob B.',
        published: false,
        createdAt: '2026-06-14T10:00:00Z',
      ),
    ]);

    await tester.pumpWidget(_wrap(
      ClientTestimonialsScreen(api: api),
    ));
    await tester.pumpAndSettle();

    // Published → "Live on website"; unpublished shows no status chip.
    expect(find.text('Live on website'), findsOneWidget);
    expect(find.text('Submitted'), findsNothing);
    expect(find.text('Helped us find the perfect home.'), findsOneWidget);
    expect(find.text('Great communication throughout.'), findsOneWidget);
  });
}
