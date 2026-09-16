import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:corex_mobile/models/gallery_tags.dart';
import 'package:corex_mobile/models/property.dart';
import 'package:corex_mobile/models/property_compliance.dart';
import 'package:corex_mobile/models/property_drive.dart';
import 'package:corex_mobile/models/property_overview.dart';
import 'package:corex_mobile/providers/auth_provider.dart';
import 'package:corex_mobile/screens/properties/property_overview_screen.dart';
import 'package:corex_mobile/services/api_service.dart';

/// Share / Open Live Preview attribution — the "my details vs listing agent's
/// details" chooser. Mirrors the web's `property-share.js`: the choice is
/// baked into the link as `?agent=<my id>` / `?agent=listing` and resolved by
/// the server, so these tests only assert on the query string we produce.
class _FakeApi extends ApiService {
  PropertyOverview? overview;

  @override
  Future<PropertyOverview> getPropertyOverview(int id,
          {bool forceRefresh = false}) async =>
      overview!;

  @override
  Future<PropertyCompliance> getPropertyCompliance(int id) async =>
      throw ApiException(404, 'no compliance');

  @override
  Future<List<PropertyContact>> getPropertyContacts(int id) async => const [];

  @override
  Future<PropertyDriveData> getPropertyDocuments(int id) async =>
      throw ApiException(404, 'no drive');

  @override
  Future<Property> getProperty(int id) async => Property(id: id, address: '');

  @override
  Future<GalleryTagsData> getGalleryTags(int id) async =>
      GalleryTagsData.empty(id);
}

const _previewUrl = 'https://corexos.co.za/corex/properties/7/preview';

PropertyOverview _overview({ContactRef? agent}) => PropertyOverview(
      id: 7,
      title: '4 Bed House',
      priceDisplay: 'R 2 950 000',
      livePreviewUrl: _previewUrl,
      agent: agent,
      keyDates: const KeyDates(),
    );

const _shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

/// Captures what share_plus would have handed the OS sheet.
List<Map<dynamic, dynamic>> _mockShare(WidgetTester tester) {
  final calls = <Map<dynamic, dynamic>>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    _shareChannel,
    (call) async {
      calls.add(Map<dynamic, dynamic>.from(call.arguments as Map));
      return 'ok';
    },
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(_shareChannel, null));
  return calls;
}

Future<AuthProvider> _pump(
  WidgetTester tester, {
  required PropertyOverview overview,
  Map<String, dynamic>? user,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final auth = AuthProvider()..debugSetUser(user);
  addTearDown(auth.dispose);
  final api = _FakeApi()..overview = overview;
  await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
    value: auth,
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: PropertyOverviewScreen(propertyId: 7, api: api),
    ),
  ));
  await tester.pumpAndSettle();
  return auth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final chooserTitle = find.text('Whose contact details should show?');
  final shareButton = find.text('Share Listing');
  const listingAgent = ContactRef(id: 42, name: 'Sipho Dlamini');
  const otherAgent = {'id': 9, 'name': 'Thandi Nkosi'};

  testWidgets('Share Listing sits directly below Open Live Preview',
      (tester) async {
    await _pump(tester, overview: _overview(), user: null);
    final preview = find.text('Open Live Preview');
    expect(preview, findsOneWidget);
    expect(shareButton, findsOneWidget);
    expect(tester.getTopLeft(shareButton).dy,
        greaterThan(tester.getBottomLeft(preview).dy));
  });

  testWidgets(
      'another agent sharing gets the chooser, and "My details" bakes '
      'their id into the link', (tester) async {
    final calls = _mockShare(tester);
    await _pump(tester,
        overview: _overview(agent: listingAgent), user: otherAgent);

    await tester.tap(shareButton);
    await tester.pumpAndSettle();
    expect(chooserTitle, findsOneWidget);
    expect(find.text('Thandi Nkosi'), findsOneWidget);
    expect(find.text('Sipho Dlamini'), findsOneWidget);

    await tester.tap(find.text('My details'));
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    final text = calls.single['text'] as String;
    expect(text, contains('$_previewUrl?agent=9'));
    expect(text, startsWith('4 Bed House — R 2 950 000\n'));
    expect(calls.single['subject'], '4 Bed House');
  });

  testWidgets('"Listing agent\'s details" bakes ?agent=listing into the link',
      (tester) async {
    final calls = _mockShare(tester);
    await _pump(tester,
        overview: _overview(agent: listingAgent), user: otherAgent);

    await tester.tap(shareButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Listing agent's details"));
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    expect(calls.single['text'], contains('$_previewUrl?agent=listing'));
  });

  testWidgets('dismissing the chooser shares nothing', (tester) async {
    final calls = _mockShare(tester);
    await _pump(tester,
        overview: _overview(agent: listingAgent), user: otherAgent);

    await tester.tap(shareButton);
    await tester.pumpAndSettle();
    expect(chooserTitle, findsOneWidget);
    // Tap the scrim above the sheet.
    await tester.tapAt(const Offset(600, 40));
    await tester.pumpAndSettle();

    expect(chooserTitle, findsNothing);
    expect(calls, isEmpty);
  });

  testWidgets(
      'the listing agent sharing their own listing still gets the chooser '
      '(mirrors the web; agents mostly share their own listings)',
      (tester) async {
    final calls = _mockShare(tester);
    await _pump(tester,
        overview: _overview(agent: const ContactRef(id: 9, name: 'Thandi Nkosi')),
        user: otherAgent);

    await tester.tap(shareButton);
    await tester.pumpAndSettle();
    expect(chooserTitle, findsOneWidget);
    // Both rows name the same person — that is the point: the choice is
    // still offered, and picking "My details" still attributes to them.
    expect(find.text('Thandi Nkosi'), findsNWidgets(2));

    await tester.tap(find.text('My details'));
    await tester.pumpAndSettle();

    expect(calls.single['text'], contains('$_previewUrl?agent=9'));
  });

  testWidgets('an assistant never gets the "My details" option (AT-267)',
      (tester) async {
    final calls = _mockShare(tester);
    await _pump(tester,
        overview: _overview(agent: listingAgent),
        user: {'id': 9, 'name': 'Assistant Amy', 'is_assistant': true});

    await tester.tap(shareButton);
    await tester.pumpAndSettle();

    expect(chooserTitle, findsNothing);
    expect(calls.single['text'], contains('?agent=listing'));
  });

  testWidgets('no signed-in user falls back to the listing agent rather '
      'than failing', (tester) async {
    final calls = _mockShare(tester);
    await _pump(tester, overview: _overview(agent: listingAgent), user: null);

    await tester.tap(shareButton);
    await tester.pumpAndSettle();

    expect(chooserTitle, findsNothing);
    expect(calls.single['text'], contains('?agent=listing'));
  });
}
