import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corex_mobile/models/gallery_tags.dart';
import 'package:corex_mobile/models/property.dart';
import 'package:corex_mobile/screens/properties/property_gallery_screen.dart';
import 'package:corex_mobile/services/api_service.dart';

/// Covers the full-screen gallery manager added to make a property with
/// dozens of photos manageable: a grid per room, room filter chips, filing,
/// and a dedicated room-reorder sheet. Drag-to-reorder itself (both the photo
/// grid's `DragTarget` cells and the reorder sheet's `ReorderableListView`)
/// isn't gesture-simulated here — no test elsewhere in this app drives that
/// kind of drag either; these tests cover the surrounding state machine
/// (fetch, filter, select, file, adopt a reorder response) instead.
class _FakeApi extends ApiService {
  Property? property;
  ApiException? propertyError;

  GalleryTagsData? galleryTags;

  GalleryAssignResult? assignResult;
  String? lastAssignedRoomTag;

  GalleryTagsData? addTagResult;
  ApiException? addTagError;
  String? lastAddedTag;
  ApiException? assignError;

  TagReorderResult? tagReorderResult;
  ApiException? tagReorderError;

  DeletedImages? deleteResult;
  ApiException? deleteError;
  List<String>? lastDeletedImageUrls;

  GalleryReorderResult? reorderResult;
  bool reorderCalled = false;
  List<String>? lastReorderImages;
  String? lastReorderRoomTag;

  @override
  Future<GalleryReorderResult> reorderGalleryImages(
    int propertyId,
    List<String> images, {
    String? roomTag,
    String? fingerprint,
  }) async {
    reorderCalled = true;
    lastReorderImages = images;
    lastReorderRoomTag = roomTag;
    return reorderResult ??
        GalleryReorderResult(
          message: 'Photo order updated.',
          roomTag: roomTag,
          unknownImages: const [],
          galleryImages: images,
          categories: GalleryCategories.empty,
          galleryFingerprint: 'sha1-new',
        );
  }

  @override
  Future<Property> getProperty(int id) async {
    if (propertyError != null) throw propertyError!;
    return property ?? Property(id: id, address: '');
  }

  @override
  Future<GalleryTagsData> getGalleryTags(int id) async =>
      galleryTags ?? GalleryTagsData.empty(id);

  @override
  Future<GalleryAssignResult> assignGalleryImages(
      int propertyId, List<String> images, String? roomTag) async {
    lastAssignedRoomTag = roomTag;
    if (assignError != null) throw assignError!;
    return assignResult!;
  }

  @override
  Future<GalleryTagsData> addGalleryTag(int propertyId, String tag) async {
    lastAddedTag = tag;
    if (addTagError != null) throw addTagError!;
    return addTagResult!;
  }

  @override
  Future<TagReorderResult> reorderGalleryTags(
      int propertyId, List<String> tags) async {
    if (tagReorderError != null) throw tagReorderError!;
    return tagReorderResult ?? TagReorderResult(message: 'ok', availableTags: tags);
  }

  @override
  Future<DeletedImages> deletePropertyImages(
    int propertyId, {
    List<String> clientUploadIds = const [],
    List<String> imageUrls = const [],
  }) async {
    lastDeletedImageUrls = imageUrls;
    if (deleteError != null) throw deleteError!;
    return deleteResult ??
        DeletedImages(
            message: '${imageUrls.length} photo(s) deleted.',
            deleted: imageUrls.length,
            unknownIds: const []);
  }
}

Property _seededProperty({
  Map<String, List<String>> categories = const {},
  List<String> unsorted = const [],
  List<String> galleryTags = const [],
  List<String> galleryImages = const [],
}) {
  return Property(
    id: 7,
    address: '',
    galleryCategories: {
      'categories': categories,
      'unsorted': unsorted,
    },
    galleryTags: galleryTags,
    galleryImages: galleryImages,
    galleryFingerprint: 'sha1-abc',
  );
}

Widget _wrap(Widget child) =>
    MaterialApp(theme: ThemeData.dark(), home: child);

/// The body is a single scrolling `ListView`, so a section below the fold on
/// the default 800×600 test surface is never inflated (a `Sliver` only
/// builds elements near the viewport) and `find.text` on it comes back
/// empty even though it would render fine on a real, taller phone.
void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 5000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// A bounded stand-in for `pumpAndSettle()`. Every photo thumbnail on this
/// screen is a `CachedNetworkImage`, and under the test binding's mocked
/// HttpClient (every request completes 400) its failed-fetch handling keeps
/// scheduling frames rather than settling — `pumpAndSettle()` never detects
/// quiescence and times out. These tests assert on text and widget
/// structure, never on an image finishing (or failing) to load, so a fixed
/// run of pumps — comfortably past any standard Material transition (sheet
/// open/close, filter change) — stands in for it.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The reorder-rooms sheet lays tiles out in a 2-column grid, not a list, so
/// there's no `ListTile` to read order off any more. `GridView.builder`
/// still builds its items in index order though, so the tag name `Text`
/// widgets come back in the sheet's current order regardless of which
/// column/row they land in visually.
///
/// The sheet is a modal *on top of* the still-mounted gallery screen, whose
/// own room-section headers repeat the same room names — so this must be
/// scoped to just the sheet's grid, or a room appears twice (once behind the
/// sheet, once in it). `GridView` (the box widget, not `SliverGrid`) is only
/// ever used by the sheet here, which makes it a safe, public anchor for
/// `find.descendant` — the sheet's own class is private to the screen's file
/// and can't be named from a test.
List<String> _roomTileOrder(WidgetTester tester, Set<String> tags) {
  return tester
      .widgetList<Text>(find.descendant(
        of: find.byType(GridView),
        matching: find.byWidgetPredicate((w) => w is Text && tags.contains(w.data)),
      ))
      .map((t) => t.data!)
      .toList();
}

void main() {
  testWidgets(
      'a many-room, many-photo property renders via real slivers, not '
      'shrinkWrap GridViews', (tester) async {
    // Regression guard for the ANR this screen originally shipped with:
    // a GridView per room with `shrinkWrap: true` inside an outer ListView
    // forces every photo across every room to be laid out synchronously on
    // every rebuild. With ~90 photos that blew past Android's 5s
    // input-dispatch timeout and the OS killed the app. `SliverGrid` inside
    // one `CustomScrollView` is the fix — it only builds what's near the
    // viewport regardless of how many rooms or photos there are, so this
    // asserts the widget tree actually uses that shape.
    _useTallViewport(tester);
    final categories = <String, List<String>>{
      for (var room = 1; room <= 12; room++)
        'Room $room': [
          for (var photo = 1; photo <= 8; photo++)
            'https://x/room$room-$photo.jpg',
        ],
    };
    final api = _FakeApi()
      ..property = _seededProperty(
        categories: categories,
        galleryTags: categories.keys.toList(),
      )
      ..galleryTags = GalleryTagsData.fromJson({
        'property_id': 7,
        'available_tags': categories.keys.toList(),
        'tag_counts': {for (final e in categories.entries) e.key: e.value.length},
        'untagged_count': 0,
      });

    await tester.pumpWidget(_wrap(PropertyGalleryScreen(propertyId: 7, api: api)));
    await _settle(tester);

    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(find.byType(SliverGrid), findsWidgets);
    // The bug-shaped widget must be gone entirely — not just replaced in
    // the photo grid — since a `GridView` anywhere back in this tree is the
    // same eager-layout trap.
    expect(find.byType(GridView), findsNothing);
  });

  testWidgets('renders each room as its own section with a photo count',
      (tester) async {
    _useTallViewport(tester);
    final api = _FakeApi()
      ..property = _seededProperty(
        categories: {
          'Kitchen': ['https://x/a.jpg', 'https://x/b.jpg'],
          'Lounge': ['https://x/c.jpg'],
        },
        unsorted: ['https://x/d.jpg'],
        galleryTags: const ['Kitchen', 'Lounge'],
      )
      ..galleryTags = GalleryTagsData.fromJson({
        'property_id': 7,
        'available_tags': ['Kitchen', 'Lounge'],
        'tag_counts': {'Kitchen': 2, 'Lounge': 1},
        'untagged_count': 1,
      });

    await tester.pumpWidget(_wrap(PropertyGalleryScreen(propertyId: 7, api: api)));
    await _settle(tester);

    expect(find.text('Kitchen'), findsOneWidget);
    expect(find.text('Lounge'), findsOneWidget);
    expect(find.text('Unsorted'), findsOneWidget);
    // Section header count pill and filter chip both say "2" / "1" — the
    // exact count matters more than which widget it's attached to.
    expect(find.textContaining('Kitchen · 2'), findsOneWidget);
    expect(find.textContaining('Lounge · 1'), findsOneWidget);
    expect(find.textContaining('Unsorted · 1'), findsOneWidget);
  });

  testWidgets('tapping a room chip filters the grid to just that room',
      (tester) async {
    _useTallViewport(tester);
    final api = _FakeApi()
      ..property = _seededProperty(
        categories: {
          'Kitchen': ['https://x/a.jpg'],
          'Lounge': ['https://x/c.jpg'],
        },
        galleryTags: const ['Kitchen', 'Lounge'],
      )
      ..galleryTags = GalleryTagsData.fromJson({
        'property_id': 7,
        'available_tags': ['Kitchen', 'Lounge'],
        'tag_counts': {'Kitchen': 1, 'Lounge': 1},
        'untagged_count': 0,
      });

    await tester.pumpWidget(_wrap(PropertyGalleryScreen(propertyId: 7, api: api)));
    await _settle(tester);

    expect(find.text('Lounge'), findsOneWidget);

    // The chip and the section header share the room's plain name, so match
    // the chip specifically by its "· count" suffix.
    await tester.tap(find.text('Kitchen · 1'));
    await _settle(tester);

    expect(find.text('Kitchen'), findsOneWidget);
    expect(find.text('Lounge'), findsNothing);
  });

  testWidgets('selecting an unsorted photo and filing it calls the assign '
      'API and clears the selection', (tester) async {
    _useTallViewport(tester);
    final api = _FakeApi()
      ..property = _seededProperty(
        unsorted: ['https://x/d.jpg'],
        galleryTags: const ['Kitchen'],
      )
      ..galleryTags = GalleryTagsData.fromJson({
        'property_id': 7,
        'available_tags': ['Kitchen'],
        'tag_counts': {'Kitchen': 0},
        'untagged_count': 1,
      })
      ..assignResult = GalleryAssignResult.fromJson({
        'message': "1 photo(s) filed under 'Kitchen'.",
        'moved': 1,
        'unknown_images': [],
        'room_tag': 'Kitchen',
        'gallery_categories': {
          'categories': {
            'Kitchen': ['https://x/d.jpg'],
          },
          'unsorted': [],
        },
        'available_tags': ['Kitchen'],
      });

    await tester.pumpWidget(_wrap(PropertyGalleryScreen(propertyId: 7, api: api)));
    await _settle(tester);

    // Select the one unsorted thumbnail.
    await tester.tap(find.byKey(const ValueKey('photo-cell-https://x/d.jpg')));
    await tester.pump();
    expect(find.text('1 photo selected'), findsOneWidget);

    await tester.tap(find.text('File under…'));
    await _settle(tester);
    // "Kitchen" also names the (currently empty) room section behind the
    // sheet, so target the room-picker's own list tile specifically.
    await tester.tap(find.widgetWithText(ListTile, 'Kitchen'));
    await _settle(tester);

    expect(find.text("1 photo(s) filed under 'Kitchen'."), findsOneWidget);
    expect(find.text('1 photo selected'), findsNothing);
    // Unsorted emptied out — its chip and section both drop off.
    expect(find.textContaining('Unsorted'), findsNothing);
  });

  testWidgets(
      '"New custom tag…" in the File-under picker creates the tag and files '
      'the selection under the server\'s spelling of it', (tester) async {
    _useTallViewport(tester);
    final api = _FakeApi()
      ..property = _seededProperty(
        unsorted: ['https://x/d.jpg'],
        galleryTags: const ['Kitchen'],
      )
      ..galleryTags = GalleryTagsData.fromJson({
        'property_id': 7,
        'available_tags': ['Kitchen'],
        'tag_counts': {'Kitchen': 0},
        'untagged_count': 1,
      })
      // The server normalises the typed name; the assign must use *its*
      // spelling, or it 422s as an unknown tag a moment after creating it.
      ..addTagResult = GalleryTagsData.fromJson({
        'property_id': 7,
        'available_tags': ['Kitchen', 'Sea View'],
        'tag_counts': {'Kitchen': 0, 'Sea View': 0},
        'untagged_count': 1,
      })
      ..assignResult = GalleryAssignResult.fromJson({
        'message': "1 photo(s) filed under 'Sea View'.",
        'moved': 1,
        'unknown_images': [],
        'room_tag': 'Sea View',
        'gallery_categories': {
          'categories': {
            'Kitchen': [],
            'Sea View': ['https://x/d.jpg'],
          },
          'unsorted': [],
        },
        'available_tags': ['Kitchen', 'Sea View'],
      });

    await tester.pumpWidget(_wrap(PropertyGalleryScreen(propertyId: 7, api: api)));
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('photo-cell-https://x/d.jpg')));
    await tester.pump();
    await tester.tap(find.text('File under…'));
    await _settle(tester);

    await tester.tap(find.widgetWithText(ListTile, 'New custom tag…'));
    await _settle(tester);
    expect(find.text('Add custom tag'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  sea view ');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
    await _settle(tester);

    expect(api.lastAddedTag, 'sea view');
    expect(api.lastAssignedRoomTag, 'Sea View');
    expect(find.text("1 photo(s) filed under 'Sea View'."), findsOneWidget);
    expect(find.text('1 photo selected'), findsNothing);
    // The new room is now a section of its own.
    expect(find.text('Sea View'), findsWidgets);
  });

  testWidgets(
      'cancelling the custom-tag prompt returns to the picker with the '
      'selection intact', (tester) async {
    _useTallViewport(tester);
    final api = _FakeApi()
      ..property = _seededProperty(
        unsorted: ['https://x/d.jpg'],
        galleryTags: const ['Kitchen'],
      )
      ..galleryTags = GalleryTagsData.fromJson({
        'property_id': 7,
        'available_tags': ['Kitchen'],
        'tag_counts': {'Kitchen': 0},
        'untagged_count': 1,
      });

    await tester.pumpWidget(_wrap(PropertyGalleryScreen(propertyId: 7, api: api)));
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('photo-cell-https://x/d.jpg')));
    await tester.pump();
    await tester.tap(find.text('File under…'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(ListTile, 'New custom tag…'));
    await _settle(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await _settle(tester);

    // Back in the picker, nothing created, nothing filed.
    expect(find.widgetWithText(ListTile, 'New custom tag…'), findsOneWidget);
    expect(api.lastAddedTag, isNull);
    expect(api.lastAssignedRoomTag, isNull);
    expect(find.text('1 photo selected'), findsOneWidget);
  });

  testWidgets(
      'selecting photos and deleting them confirms, calls the API, and '
      'removes them locally', (tester) async {
    _useTallViewport(tester);
    final api = _FakeApi()
      ..property = _seededProperty(
        categories: {
          'Kitchen': ['https://x/a.jpg', 'https://x/b.jpg'],
        },
        galleryTags: const ['Kitchen'],
      )
      ..galleryTags = GalleryTagsData.fromJson({
        'property_id': 7,
        'available_tags': ['Kitchen'],
        'tag_counts': {'Kitchen': 2},
        'untagged_count': 0,
      });

    await tester.pumpWidget(_wrap(PropertyGalleryScreen(propertyId: 7, api: api)));
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('photo-cell-https://x/a.jpg')));
    await tester.pump();
    expect(find.text('1 photo selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete'));
    await _settle(tester);

    // A destructive action needs a confirmation, not an immediate delete.
    expect(find.text('Delete 1 photo?'), findsOneWidget);
    expect(api.lastDeletedImageUrls, isNull);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
    await _settle(tester);

    expect(api.lastDeletedImageUrls, ['https://x/a.jpg']);
    expect(find.text('1 photo selected'), findsNothing);
    // Deleted locally without a round-trip refetch — the remaining photo
    // is still there, the deleted one is gone.
    expect(find.textContaining('Kitchen · 1'), findsOneWidget);
  });

  testWidgets(
      'the "All Photos" filter shows every photo in master order with a '
      'Cover badge on the first, and reorders drive the master-grid API '
      'call', (tester) async {
    // This is the one call that actually reaches the website — reordering
    // *within* a room leaves the master grid (and so the portal order and
    // cover photo) untouched. "All Photos" is where a drag calls
    // reorderGalleryImages with no room_tag at all.
    _useTallViewport(tester);
    final api = _FakeApi()
      ..property = _seededProperty(
        categories: {
          'Kitchen': ['https://x/a.jpg'],
          'Lounge': ['https://x/b.jpg'],
        },
        galleryTags: const ['Kitchen', 'Lounge'],
        galleryImages: const ['https://x/a.jpg', 'https://x/b.jpg'],
      )
      ..galleryTags = GalleryTagsData.fromJson({
        'property_id': 7,
        'available_tags': ['Kitchen', 'Lounge'],
        'tag_counts': {'Kitchen': 1, 'Lounge': 1},
        'untagged_count': 0,
      });

    await tester.pumpWidget(_wrap(PropertyGalleryScreen(propertyId: 7, api: api)));
    await _settle(tester);

    await tester.tap(find.text('All Photos · 2'));
    await _settle(tester);

    expect(find.text('Cover'), findsOneWidget);
    expect(
        find.text('Drag to set the order shown on the website — the first '
            'photo is the cover.'),
        findsOneWidget);
    // The room-grouped sections aren't shown in this view.
    expect(find.text('Kitchen'), findsNothing);
    expect(find.text('Lounge'), findsNothing);
  });

  testWidgets(
      'the reorder-rooms sheet can push its room order to the website as one '
      'flat master-grid reorder (no room_tag), rooms first then unsorted',
      (tester) async {
    // Room order on its own never reaches the website — it shows one flat
    // list. This button is what turns "Lounge first, then Kitchen" into that
    // list and saves it via the master-grid call.
    final api = _FakeApi()
      ..property = _seededProperty(
        categories: {
          'Kitchen': ['https://x/a.jpg'],
          'Lounge': ['https://x/b.jpg', 'https://x/c.jpg'],
        },
        unsorted: ['https://x/d.jpg'],
        galleryTags: const ['Lounge', 'Kitchen'],
        // The website's current order is the reverse of the room order.
        galleryImages: const [
          'https://x/d.jpg',
          'https://x/a.jpg',
          'https://x/c.jpg',
          'https://x/b.jpg',
        ],
      )
      ..galleryTags = GalleryTagsData.fromJson({
        'property_id': 7,
        'available_tags': ['Lounge', 'Kitchen'],
        'tag_counts': {'Lounge': 2, 'Kitchen': 1},
        'untagged_count': 1,
      });

    await tester.pumpWidget(_wrap(PropertyGalleryScreen(propertyId: 7, api: api)));
    await _settle(tester);

    await tester.tap(find.text('Sort'));
    await _settle(tester);
    expect(find.text('Sort website photos by room'), findsOneWidget);

    await tester.tap(find.text('Sort website photos by room'));
    await _settle(tester);
    // Changing the public listing's order (and cover) gets a confirmation.
    expect(find.text('Sort website photos by room?'), findsOneWidget);
    expect(api.reorderCalled, isFalse);

    await tester.tap(find.text('Sort website'));
    await _settle(tester);

    expect(api.reorderCalled, isTrue);
    expect(api.lastReorderRoomTag, isNull, reason: 'must be a master-grid reorder');
    expect(api.lastReorderImages, [
      'https://x/b.jpg',
      'https://x/c.jpg',
      'https://x/a.jpg',
      'https://x/d.jpg',
    ]);
    // Saved → the sheet closes, and the room sections are still there (the
    // fake's empty categories map must not have wiped them).
    expect(find.text('Reorder rooms'), findsNothing);
    expect(find.textContaining('Lounge'), findsWidgets);
  });

  testWidgets(
      'dragging a photo one cell forward in "All Photos" swaps it with its '
      'neighbour and sends the new master order (no room_tag)',
      (tester) async {
    // Regression: the drop handler used to apply a ReorderableListView-style
    // "-1 when moving forward", which made this exact drag a no-op — the
    // PUT went out with the unchanged order.
    _useTallViewport(tester);
    final api = _FakeApi()
      ..property = _seededProperty(
        categories: {
          'Kitchen': ['https://x/a.jpg', 'https://x/b.jpg', 'https://x/c.jpg'],
        },
        galleryTags: const ['Kitchen'],
        galleryImages: const [
          'https://x/a.jpg',
          'https://x/b.jpg',
          'https://x/c.jpg',
        ],
      )
      ..galleryTags = GalleryTagsData.fromJson({
        'property_id': 7,
        'available_tags': ['Kitchen'],
        'tag_counts': {'Kitchen': 3},
        'untagged_count': 0,
      });

    await tester.pumpWidget(_wrap(PropertyGalleryScreen(propertyId: 7, api: api)));
    await _settle(tester);
    await tester.tap(find.text('All Photos · 3'));
    await _settle(tester);

    // Every thumbnail goes through the disk cache — a plain Image.network
    // here would silently re-download on every visit.
    expect(find.byType(CachedNetworkImage), findsNWidgets(3));

    final a = find.byKey(const ValueKey('photo-cell-https://x/a.jpg'));
    final b = find.byKey(const ValueKey('photo-cell-https://x/b.jpg'));
    final gesture = await tester.startGesture(tester.getCenter(a));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(tester.getCenter(b));
    await tester.pump();
    await gesture.up();
    await _settle(tester);

    expect(api.reorderCalled, isTrue);
    expect(api.lastReorderRoomTag, isNull);
    expect(api.lastReorderImages,
        ['https://x/b.jpg', 'https://x/a.jpg', 'https://x/c.jpg']);
  });

  testWidgets(
      'dragging a photo backwards two cells in a room takes the target slot',
      (tester) async {
    _useTallViewport(tester);
    final api = _FakeApi()
      ..property = _seededProperty(
        categories: {
          'Kitchen': ['https://x/a.jpg', 'https://x/b.jpg', 'https://x/c.jpg'],
        },
        galleryTags: const ['Kitchen'],
      )
      ..galleryTags = GalleryTagsData.fromJson({
        'property_id': 7,
        'available_tags': ['Kitchen'],
        'tag_counts': {'Kitchen': 3},
        'untagged_count': 0,
      });

    await tester.pumpWidget(_wrap(PropertyGalleryScreen(propertyId: 7, api: api)));
    await _settle(tester);

    final c = find.byKey(const ValueKey('photo-cell-https://x/c.jpg'));
    final a = find.byKey(const ValueKey('photo-cell-https://x/a.jpg'));
    final gesture = await tester.startGesture(tester.getCenter(c));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(tester.getCenter(a));
    await tester.pump();
    await gesture.up();
    await _settle(tester);

    expect(api.lastReorderRoomTag, 'Kitchen');
    expect(api.lastReorderImages,
        ['https://x/c.jpg', 'https://x/a.jpg', 'https://x/b.jpg']);
  });

  testWidgets('the reorder-rooms sheet lists rooms in their current order',
      (tester) async {
    final api = _FakeApi()
      ..property = _seededProperty(
        categories: {
          'Kitchen': ['https://x/a.jpg'],
          'Lounge': ['https://x/c.jpg'],
        },
        galleryTags: const ['Kitchen', 'Lounge'],
      )
      ..galleryTags = GalleryTagsData.fromJson({
        'property_id': 7,
        'available_tags': ['Kitchen', 'Lounge'],
        'tag_counts': {'Kitchen': 1, 'Lounge': 1},
        'untagged_count': 0,
      });

    await tester.pumpWidget(_wrap(PropertyGalleryScreen(propertyId: 7, api: api)));
    await _settle(tester);

    await tester.tap(find.text('Sort'));
    await _settle(tester);

    expect(find.text('Reorder rooms'), findsOneWidget);
    expect(
        find.text('Drag to fine-tune, or pick a number to jump a room '
            'straight to that position.'),
        findsOneWidget);
    // Each tile's position badge, scoped to the sheet's grid so it can't
    // match anything from the still-mounted screen behind it.
    final gridFinder = find.byType(GridView);
    expect(find.descendant(of: gridFinder, matching: find.text('1')),
        findsOneWidget);
    expect(find.descendant(of: gridFinder, matching: find.text('2')),
        findsOneWidget);
    expect(_roomTileOrder(tester, const {'Kitchen', 'Lounge'}),
        ['Kitchen', 'Lounge']);

    await tester.tap(find.text('Done'));
    await _settle(tester);
    expect(find.text('Reorder rooms'), findsNothing);
  });

  testWidgets(
      "the reorder-rooms sheet's position picker jumps a room straight to a "
      'position without a long drag', (tester) async {
    // The whole reason this picker exists: dragging a room from the top all
    // the way to the bottom of a long list is exactly what an agent reported
    // as painful. Picking "3" should reach the same end state in one tap, no
    // dragging at all.
    final api = _FakeApi()
      ..property = _seededProperty(
        categories: {
          'Kitchen': ['https://x/a.jpg'],
          'Lounge': ['https://x/c.jpg'],
          'Patio': ['https://x/e.jpg'],
        },
        galleryTags: const ['Kitchen', 'Lounge', 'Patio'],
      )
      ..galleryTags = GalleryTagsData.fromJson({
        'property_id': 7,
        'available_tags': ['Kitchen', 'Lounge', 'Patio'],
        'tag_counts': {'Kitchen': 1, 'Lounge': 1, 'Patio': 1},
        'untagged_count': 0,
      })
      ..tagReorderResult = const TagReorderResult(
        message: 'ok', availableTags: ['Lounge', 'Patio', 'Kitchen']);

    await tester.pumpWidget(_wrap(PropertyGalleryScreen(propertyId: 7, api: api)));
    await _settle(tester);

    await tester.tap(find.text('Sort'));
    await _settle(tester);

    // Kitchen starts at position 1 — its badge is the sheet's own "1".
    await tester.tap(find.descendant(
        of: find.byType(GridView), matching: find.text('1')));
    await _settle(tester);

    expect(find.text('Move "Kitchen" to position'), findsOneWidget);
    // The position chips sit in a Wrap so several fit per row — pick "3"
    // to send Kitchen to the bottom of this 3-room list.
    await tester.tap(
        find.descendant(of: find.byType(Wrap), matching: find.text('3')));
    await _settle(tester);

    expect(_roomTileOrder(tester, const {'Kitchen', 'Lounge', 'Patio'}),
        ['Lounge', 'Patio', 'Kitchen']);
  });

  testWidgets(
      'reordering rooms from the Sort sheet leaves the "All Photos" view '
      'selected', (tester) async {
    // The sheet's onReordered clears a filter for a room that vanished; the
    // master-grid sentinel is not a room name and used to get cleared too,
    // bouncing the user back to the grouped view on every room move.
    _useTallViewport(tester);
    final api = _FakeApi()
      ..property = _seededProperty(
        categories: {
          'Kitchen': ['https://x/a.jpg'],
          'Lounge': ['https://x/b.jpg'],
        },
        galleryTags: const ['Kitchen', 'Lounge'],
        galleryImages: const ['https://x/a.jpg', 'https://x/b.jpg'],
      )
      ..galleryTags = GalleryTagsData.fromJson({
        'property_id': 7,
        'available_tags': ['Kitchen', 'Lounge'],
        'tag_counts': {'Kitchen': 1, 'Lounge': 1},
        'untagged_count': 0,
      })
      ..tagReorderResult = const TagReorderResult(
          message: 'ok', availableTags: ['Lounge', 'Kitchen']);

    await tester.pumpWidget(_wrap(PropertyGalleryScreen(propertyId: 7, api: api)));
    await _settle(tester);
    await tester.tap(find.text('All Photos · 2'));
    await _settle(tester);
    const hint = 'Drag to set the order shown on the website — the first '
        'photo is the cover.';
    expect(find.text(hint), findsOneWidget);

    await tester.tap(find.text('Sort'));
    await _settle(tester);
    await tester.tap(find.descendant(
        of: find.byType(GridView), matching: find.text('1')));
    await _settle(tester);
    await tester.tap(
        find.descendant(of: find.byType(Wrap), matching: find.text('2')));
    await _settle(tester);
    await tester.tap(find.text('Done'));
    await _settle(tester);

    expect(find.text(hint), findsOneWidget,
        reason: 'still on All Photos after a room reorder');
    expect(find.text('Cover'), findsOneWidget);
  });

  testWidgets('shows a retry state when the initial fetch fails',
      (tester) async {
    final api = _FakeApi()..propertyError = ApiException(500, 'Server error');

    await tester.pumpWidget(_wrap(PropertyGalleryScreen(propertyId: 7, api: api)));
    await _settle(tester);

    expect(find.text('Server error'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
