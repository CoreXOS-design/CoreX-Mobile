import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corex_mobile/models/contact.dart';
import 'package:corex_mobile/screens/contacts/contact_show_screen.dart';
import 'package:corex_mobile/services/api_service.dart';

class _FakeApi extends ApiService {
  Contact? contact;

  @override
  Future<Contact> getContact(int id) async {
    if (contact == null) throw ApiException(404, 'not found');
    return contact!;
  }
}

Contact _contact({
  List<ContactMatch> matches = const [],
  List<ContactLinkedProperty> properties = const [],
  String? phone = '082 555 1234',
}) =>
    Contact(
      id: 5,
      firstName: 'John',
      lastName: 'Owner',
      phone: phone,
      email: 'john@example.test',
      contactTypeName: 'Seller',
      matches: matches,
      linkedProperties: properties,
    );

Widget _wrap(Widget child) =>
    MaterialApp(theme: ThemeData.dark(), home: child);

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

List<String> _tabLabels(WidgetTester tester) => tester
    .widgetList<Tab>(find.byType(Tab))
    .map((t) => t.text ?? '')
    .toList();

Future<void> _openTab(WidgetTester tester, String label) async {
  final tab = find.byWidgetPredicate(
      (w) => w is Tab && (w.text ?? '').startsWith(label));
  expect(tab, findsOneWidget, reason: 'no "$label" tab on screen');
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('three tabs, with live counts on Matches and Properties',
      (tester) async {
    _useTallViewport(tester);
    final api = _FakeApi()
      ..contact = _contact(
        matches: const [ContactMatch(id: 1, name: 'Beach house search')],
        properties: const [
          ContactLinkedProperty(id: 9, address: '12 Marine Drive'),
          ContactLinkedProperty(id: 10, address: '4 Ocean View'),
        ],
      );

    await tester.pumpWidget(_wrap(ContactShowScreen(contactId: 5, api: api)));
    await tester.pumpAndSettle();

    expect(_tabLabels(tester), ['Details', 'Matches · 1', 'Properties · 2']);
  });

  testWidgets('Details is the landing tab and holds the contact details',
      (tester) async {
    _useTallViewport(tester);
    final api = _FakeApi()..contact = _contact();

    await tester.pumpWidget(_wrap(ContactShowScreen(contactId: 5, api: api)));
    await tester.pumpAndSettle();

    expect(find.text('082 555 1234'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
  });

  testWidgets('the name appears once — hero only, not repeated in Details',
      (tester) async {
    // The old layout rendered the name in a header card AND the app bar. The
    // hero owns it now, so a duplicate here means the split regressed.
    _useTallViewport(tester);
    final api = _FakeApi()..contact = _contact();

    await tester.pumpWidget(_wrap(ContactShowScreen(contactId: 5, api: api)));
    await tester.pumpAndSettle();

    expect(find.text('John Owner'), findsOneWidget);
  });

  testWidgets('matches and properties live behind their own tabs',
      (tester) async {
    _useTallViewport(tester);
    final api = _FakeApi()
      ..contact = _contact(
        matches: const [ContactMatch(id: 1, name: 'Beach house search')],
        properties: const [
          ContactLinkedProperty(id: 9, address: '12 Marine Drive'),
        ],
      );

    await tester.pumpWidget(_wrap(ContactShowScreen(contactId: 5, api: api)));
    await tester.pumpAndSettle();

    expect(find.text('12 Marine Drive'), findsNothing);

    await _openTab(tester, 'Matches');
    expect(find.text('Beach house search'), findsOneWidget);

    await _openTab(tester, 'Properties');
    expect(find.text('12 Marine Drive'), findsOneWidget);
  });

  testWidgets('empty tabs keep their directive empty states', (tester) async {
    _useTallViewport(tester);
    final api = _FakeApi()..contact = _contact();

    await tester.pumpWidget(_wrap(ContactShowScreen(contactId: 5, api: api)));
    await tester.pumpAndSettle();

    expect(_tabLabels(tester), ['Details', 'Matches · 0', 'Properties · 0']);

    await _openTab(tester, 'Matches');
    expect(find.text('No matches yet'), findsOneWidget);

    await _openTab(tester, 'Properties');
    expect(find.text('No linked listings'), findsOneWidget);
  });

  testWidgets('a contact with no details says so instead of showing a blank '
      'card', (tester) async {
    _useTallViewport(tester);
    final api = _FakeApi()
      ..contact = const Contact(
        id: 5,
        firstName: 'John',
        lastName: 'Owner',
        matches: [],
        linkedProperties: [],
      );

    await tester.pumpWidget(_wrap(ContactShowScreen(contactId: 5, api: api)));
    await tester.pumpAndSettle();

    expect(find.textContaining('No phone, email or ID captured yet'),
        findsOneWidget);
  });
}
