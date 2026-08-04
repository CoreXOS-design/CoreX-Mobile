import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corex_mobile/models/gallery_tags.dart';
import 'package:corex_mobile/models/property_compliance.dart';
import 'package:corex_mobile/models/property_drive.dart';
import 'package:corex_mobile/models/property_overview.dart';
import 'package:corex_mobile/screens/properties/property_overview_screen.dart';
import 'package:corex_mobile/services/api_service.dart';

class _FakeApi extends ApiService {
  PropertyOverview? overview;
  ApiException? overviewError;

  PropertyCompliance? compliance;
  List<PropertyContact> contacts = const [];

  GalleryTagsData? addResult;
  ApiException? addError;

  @override
  Future<PropertyOverview> getPropertyOverview(int id,
      {bool forceRefresh = false}) async {
    if (overviewError != null) throw overviewError!;
    return overview!;
  }

  @override
  Future<PropertyCompliance> getPropertyCompliance(int id) async {
    if (compliance == null) throw ApiException(404, 'no compliance');
    return compliance!;
  }

  @override
  Future<List<PropertyContact>> getPropertyContacts(int id) async => contacts;

  /// Stubbed so these tests never reach the network. Defaults to "no Drive
  /// payload", which is what the screen sees on a backend that doesn't serve
  /// /documents — the section then simply doesn't render.
  PropertyDriveData? drive;

  @override
  Future<PropertyDriveData> getPropertyDocuments(int id) async {
    if (drive == null) throw ApiException(404, 'no drive');
    return drive!;
  }

  @override
  Future<GalleryTagsData> addGalleryTag(int propertyId, String tag) async {
    if (addError != null) throw addError!;
    return addResult!;
  }
}

PropertyOverview _baseOverview({
  List<Placement> placements = const [],
  List<PortalLink> portalLinks = const [],
  bool rentalInspections = false,
}) {
  return PropertyOverview(
    id: 7,
    title: '4 Bed House',
    status: 'Active',
    suburb: 'Uvongo',
    city: 'Margate',
    priceDisplay: 'R 2 950 000',
    daysOnMarket: 14,
    beds: 4,
    baths: 2,
    garages: 3,
    sizeM2: '850',
    placements: placements,
    portalLinks: portalLinks,
    rentalInspectionsAvailable: rentalInspections,
    keyDates: const KeyDates(listed: '2026-01-10', expires: '2026-07-10'),
  );
}

List<String> _tabLabels(WidgetTester tester) => tester
    .widgetList<Tab>(find.byType(Tab))
    .map((t) => t.text ?? '')
    .toList();

Widget _wrap(Widget child) =>
    MaterialApp(theme: ThemeData.dark(), home: child);

/// Each tab is its own lazily-built scroll view, so a viewport tall enough to
/// hold a whole tab keeps assertions from having to scroll.
void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 5000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Switches tabs. Labels carry a count suffix ("Drive · 3"), so match on the
/// prefix rather than the rendered text.
Future<void> _openTab(WidgetTester tester, String label) async {
  final tab = find.byWidgetPredicate(
      (w) => w is Tab && (w.text ?? '').startsWith(label));
  expect(tab, findsOneWidget, reason: 'no "$label" tab on screen');
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders portal link card when live', (tester) async {
    _useTallViewport(tester);
    final api = _FakeApi()
      ..overview = _baseOverview(portalLinks: const [
        PortalLink(
          portal: 'property24',
          label: 'Property24',
          url: 'https://www.property24.com/listing/123',
          status: 'live',
        ),
      ]);

    await tester.pumpWidget(_wrap(
      PropertyOverviewScreen(propertyId: 7, api: api),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Property24'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('View on Property24'), findsOneWidget);
    expect(find.text('Where this listing is published'), findsOneWidget);
  });

  testWidgets('shows directive empty state when nothing is live',
      (tester) async {
    _useTallViewport(tester);
    final api = _FakeApi()..overview = _baseOverview(portalLinks: const []);

    await tester.pumpWidget(_wrap(
      PropertyOverviewScreen(propertyId: 7, api: api),
    ));
    await tester.pumpAndSettle();

    expect(
      find.textContaining("isn't live anywhere yet"),
      findsOneWidget,
    );
  });

  testWidgets('compliance card renders status badge, gates and blocked_by',
      (tester) async {
    final api = _FakeApi()
      ..overview = _baseOverview(placements: const [])
      ..compliance = PropertyCompliance.fromJson({
        'property_id': 7,
        'status': 'BLOCKED',
        'marketable': false,
        'ready': false,
        'blocked_by': ['No signed authority document'],
        'next_actions': const [],
        'checklist': {
          'authority_to_market': {'passed': false, 'detail': 'No signed authority'},
          'photos': {'passed': false, 'detail': 'Only 2 photos'},
        },
        'photos': {'count': 2, 'required': 4, 'passed': false},
        'sellers': [
          {'contact_id': 9, 'name': 'John Owner', 'role': 'owner', 'fica_passed': true}
        ],
      });

    await tester.pumpWidget(_wrap(
      PropertyOverviewScreen(propertyId: 7, api: api),
    ));
    await tester.pumpAndSettle();

    await _openTab(tester, 'Compliance');

    expect(find.text('BLOCKED'), findsOneWidget);
    expect(find.text('Authority to market'), findsOneWidget);
    expect(find.text('Blocking go-live'), findsOneWidget);
    expect(find.text('No signed authority document'), findsOneWidget);
    expect(find.text('2/4 photos'), findsOneWidget);
    expect(find.text('John Owner'), findsOneWidget);
    // Not ready → the go-live button is present but disabled.
    expect(find.text('Send Authority to Market'), findsOneWidget);
  });

  testWidgets('LIVE compliance shows attribution and no go-live button',
      (tester) async {
    final api = _FakeApi()
      ..overview = _baseOverview(placements: const [])
      ..compliance = PropertyCompliance.fromJson({
        'property_id': 7,
        'status': 'LIVE',
        'marketable': true,
        'ready': true,
        'snapshot_at': '2026-06-15T10:00:00+02:00',
        'snapshotted_by': 'Jane Agent',
        'checklist': const {},
        'sellers': const [],
      });

    await tester.pumpWidget(_wrap(
      PropertyOverviewScreen(propertyId: 7, api: api),
    ));
    await tester.pumpAndSettle();

    await _openTab(tester, 'Compliance');

    expect(find.text('LIVE'), findsOneWidget);
    expect(find.textContaining('Sent to market on'), findsOneWidget);
    expect(find.text('by Jane Agent'), findsOneWidget);
    expect(find.text('Send Authority to Market'), findsNothing);
  });

  testWidgets(
      'a next_action for a PASSED gate is not resurrected under the sellers',
      (tester) async {
    // All compliance done, not yet sent to market. The server still lists the
    // mandate action; because its gate has passed it must not reappear as a
    // "Next actions" button below the seller list.
    final api = _FakeApi()
      ..overview = _baseOverview(placements: const [])
      ..compliance = PropertyCompliance.fromJson({
        'property_id': 7,
        'status': 'READY',
        'marketable': false,
        'ready': true,
        'blocked_by': const [],
        'next_actions': [
          {
            'label': 'Send mandate for signature',
            'action_url': 'https://example.test/esign',
          }
        ],
        'checklist': {
          'authority_to_market': {'passed': true, 'detail': 'Mandate signed'},
          'fica_sellers': {'passed': true, 'detail': 'All sellers approved'},
          'photos': {'passed': true, 'detail': '8 photos'},
          'details_complete': {'passed': true, 'detail': 'All complete'},
        },
        'photos': {'count': 8, 'required': 4, 'passed': true},
        'sellers': [
          {
            'contact_id': 9,
            'name': 'John Owner',
            'role': 'owner',
            'fica_passed': true
          }
        ],
      });

    await tester.pumpWidget(_wrap(
      PropertyOverviewScreen(propertyId: 7, api: api),
    ));
    await tester.pumpAndSettle();

    await _openTab(tester, 'Compliance');

    expect(find.text('READY'), findsOneWidget);
    expect(find.text('John Owner'), findsOneWidget);
    expect(find.text('Send mandate for signature'), findsNothing);
    expect(find.text('Next actions'), findsNothing);
    // The go-live CTA is a different thing and must survive.
    expect(find.text('Send Authority to Market'), findsOneWidget);
  });

  testWidgets('"Send Marketing Pack" is not swallowed by the authority gate',
      (tester) async {
    // Its label contains "market", so a loose match would hide it now that
    // passed gates consume their actions.
    final api = _FakeApi()
      ..overview = _baseOverview(placements: const [])
      ..compliance = PropertyCompliance.fromJson({
        'property_id': 7,
        'status': 'READY',
        'marketable': false,
        'ready': true,
        'blocked_by': const [],
        'next_actions': [
          {
            'label': 'Send Marketing Pack',
            'action_url': 'https://example.test/pack',
          }
        ],
        'checklist': {
          'authority_to_market': {'passed': true, 'detail': 'Mandate signed'},
        },
        'sellers': const [],
      });

    await tester.pumpWidget(_wrap(
      PropertyOverviewScreen(propertyId: 7, api: api),
    ));
    await tester.pumpAndSettle();

    await _openTab(tester, 'Compliance');

    expect(find.text('Send Marketing Pack'), findsOneWidget);
  });

  testWidgets('a genuinely unrelated next_action still shows', (tester) async {
    final api = _FakeApi()
      ..overview = _baseOverview(placements: const [])
      ..compliance = PropertyCompliance.fromJson({
        'property_id': 7,
        'status': 'READY',
        'marketable': false,
        'ready': true,
        'blocked_by': const [],
        'next_actions': [
          {
            'label': 'Order a photographer',
            'action_url': 'https://example.test/photographer',
          }
        ],
        'checklist': {
          'authority_to_market': {'passed': true, 'detail': 'Mandate signed'},
        },
        'sellers': const [],
      });

    await tester.pumpWidget(_wrap(
      PropertyOverviewScreen(propertyId: 7, api: api),
    ));
    await tester.pumpAndSettle();

    await _openTab(tester, 'Compliance');

    expect(find.text('Next actions'), findsOneWidget);
    expect(find.text('Order a photographer'), findsOneWidget);
  });

  testWidgets('Drive section renders when the property has files',
      (tester) async {
    final api = _FakeApi()
      ..overview = _baseOverview(placements: const [])
      ..drive = PropertyDriveData.fromJson({
        'property_id': 7,
        'folders': [
          {
            'document_type_id': 3,
            'label': 'Mandate',
            'slug': 'mandate',
            'count': 1
          }
        ],
        'documents': [
          {
            'id': 101,
            'original_name': 'Mandate Agreement.pdf',
            'mime_type': 'application/pdf',
            'human_size': '240.0 KB',
            'document_type': {'id': 3, 'label': 'Mandate', 'slug': 'mandate'},
            'uploaded_by': {'id': 5, 'name': 'Jane Agent'},
            'created_at': '2026-08-01T10:22:00+02:00',
            'can_download': true,
          }
        ],
      });

    await tester.pumpWidget(_wrap(
      PropertyOverviewScreen(propertyId: 7, api: api),
    ));
    await tester.pumpAndSettle();

    // The tab carries the file count.
    expect(find.byWidgetPredicate((w) => w is Tab && w.text == 'Drive · 1'),
        findsOneWidget);

    await _openTab(tester, 'Drive');
    expect(find.text('Mandate Agreement.pdf'), findsOneWidget);
  });

  testWidgets('Drive section still renders — with a Retry — when the fetch '
      'fails, instead of vanishing', (tester) async {
    // A backend without /documents must not break the rest of the screen, but
    // it must not make the whole section disappear either: that reads as "the
    // feature was never built".
    final api = _FakeApi()..overview = _baseOverview(placements: const []);

    await tester.pumpWidget(_wrap(
      PropertyOverviewScreen(propertyId: 7, api: api),
    ));
    await tester.pumpAndSettle();

    await _openTab(tester, 'Drive');

    expect(find.text('Retry'), findsOneWidget);
    // The rest of the screen is unaffected.
    expect(find.byWidgetPredicate((w) => w is Tab && w.text == 'Info'),
        findsOneWidget);
  });

  testWidgets('Drive Retry re-fetches and renders the files', (tester) async {
    final api = _FakeApi()..overview = _baseOverview(placements: const []);

    await tester.pumpWidget(_wrap(
      PropertyOverviewScreen(propertyId: 7, api: api),
    ));
    await tester.pumpAndSettle();
    await _openTab(tester, 'Drive');
    expect(find.text('Retry'), findsOneWidget);

    // The endpoint comes online (or the network recovers).
    api.drive = PropertyDriveData.fromJson({
      'property_id': 7,
      'folders': const [],
      'documents': [
        {
          'id': 101,
          'original_name': 'Mandate Agreement.pdf',
          'mime_type': 'application/pdf',
          'human_size': '240.0 KB',
          'can_download': true,
        }
      ],
    });

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Mandate Agreement.pdf'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  group('tabs', () {
    testWidgets('shows the four standard tabs, Info first', (tester) async {
      final api = _FakeApi()..overview = _baseOverview();

      await tester.pumpWidget(_wrap(
        PropertyOverviewScreen(propertyId: 7, api: api),
      ));
      await tester.pumpAndSettle();

      expect(_tabLabels(tester),
          ['Info', 'Compliance', 'Contacts · 0', 'Drive']);
      // Info is the landing tab, so at-a-glance content is visible unprompted.
      expect(find.text('Where this listing is published'), findsOneWidget);
    });

    testWidgets('specs render as labelled tiles on Info, not one scrolling '
        'line of text', (tester) async {
      final api = _FakeApi()..overview = _baseOverview();

      await tester.pumpWidget(_wrap(
        PropertyOverviewScreen(propertyId: 7, api: api),
      ));
      await tester.pumpAndSettle();

      // Value and label are separate widgets in each tile — the old layout
      // rendered a single "4 Beds · 2 Baths · …" string instead.
      for (final pair in const [
        ('4', 'Beds'),
        ('2', 'Baths'),
        ('3', 'Garages'),
        ('850', 'Floor m²'),
      ]) {
        expect(find.text(pair.$1), findsOneWidget,
            reason: 'missing value for ${pair.$2}');
        expect(find.text(pair.$2), findsOneWidget);
      }
      expect(find.textContaining('4 Beds ·'), findsNothing);
    });

    testWidgets('specs the server omits get no tile at all', (tester) async {
      final api = _FakeApi()
        ..overview = const PropertyOverview(
          id: 7,
          title: '4 Bed House',
          beds: 4,
          placements: [],
          portalLinks: [],
          keyDates: KeyDates(),
        );

      await tester.pumpWidget(_wrap(
        PropertyOverviewScreen(propertyId: 7, api: api),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Beds'), findsOneWidget);
      expect(find.text('Baths'), findsNothing);
      expect(find.text('Garages'), findsNothing);
      expect(find.text('Mandate'), findsNothing);
    });

    // The negative case is covered by the exact label list above.
    testWidgets('Inspections tab appears when the server allows it',
        (tester) async {
      final api = _FakeApi()
        ..overview = _baseOverview(rentalInspections: true);

      await tester.pumpWidget(_wrap(
        PropertyOverviewScreen(propertyId: 7, api: api),
      ));
      await tester.pumpAndSettle();

      expect(_tabLabels(tester), contains('Inspections'));
      await _openTab(tester, 'Inspections');
      expect(find.text('Rental Inspections'), findsOneWidget);
    });

    testWidgets('agents and owner moved onto the Contacts tab and count there',
        (tester) async {
      final api = _FakeApi()
        ..overview = _baseOverview()
        ..contacts = const [
          PropertyContact(id: 3, fullName: 'Linked Person', role: 'Tenant'),
        ];

      await tester.pumpWidget(_wrap(
        PropertyOverviewScreen(propertyId: 7, api: api),
      ));
      await tester.pumpAndSettle();

      expect(_tabLabels(tester), contains('Contacts · 1'));
      // Not on Info any more — that was three separate sections before.
      expect(find.text('Linked Person'), findsNothing);

      await _openTab(tester, 'Contacts');
      expect(find.text('Linked Person'), findsOneWidget);
    });
  });

  test('addGalleryTag happy path returns new tag list', () async {
    final api = _FakeApi()
      ..addResult = GalleryTagsData.fromJson({
        'property_id': 7,
        'available_tags': ['Bedroom 1', 'Sea View'],
        'tag_counts': {'Bedroom 1': 0, 'Sea View': 0},
        'untagged_count': 0,
      });

    final result = await api.addGalleryTag(7, 'Sea View');
    expect(result.availableTags, contains('Sea View'));
    expect(result.availableTags, hasLength(2));
  });

  test('addGalleryTag surfaces 422 as ApiException', () async {
    final api = _FakeApi()..addError = ApiException(422, 'Tag already exists');
    expect(
      () => api.addGalleryTag(7, 'Bedroom 1'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 422)
          .having((e) => e.message, 'message', contains('exists'))),
    );
  });
}
