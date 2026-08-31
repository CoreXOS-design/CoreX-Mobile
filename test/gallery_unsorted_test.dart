import 'package:flutter_test/flutter_test.dart';

import 'package:corex_mobile/models/gallery_tags.dart';

/// Covers the parsing half of the 2026-08-28 photo incident:
///
///  * `gallery_categories.unsorted` — the key that made 27 stored-but-invisible
///    photos visible. It is new, so every older shape has to keep working
///    alongside it.
///  * the `gallery/assign` response, including the partial success that is a
///    200 rather than an error.
void main() {
  group('GalleryCategories.fromJson', () {
    test('reads the current shape: categories + unsorted', () {
      final g = GalleryCategories.fromJson({
        'categories': {
          'Bathroom 3': ['https://x/a.jpg'],
        },
        'unsorted': ['https://x/b.jpg', 'https://x/c.jpg'],
      });

      expect(g.categories['Bathroom 3'], ['https://x/a.jpg']);
      expect(g.unsorted, ['https://x/b.jpg', 'https://x/c.jpg']);
      expect(g.totalCount, 3);
    });

    test('a payload with no unsorted key yields an empty bucket, not null', () {
      final g = GalleryCategories.fromJson({
        'categories': {
          'Kitchen': ['https://x/a.jpg'],
        },
      });

      expect(g.unsorted, isEmpty);
      expect(g.categories['Kitchen'], hasLength(1));
    });

    test('object entries are unwrapped to their url', () {
      final g = GalleryCategories.fromJson({
        'categories': {
          'Kitchen': [
            {'url': 'https://x/a.jpg', 'id': 7},
          ],
        },
        'unsorted': [
          {'url': 'https://x/b.jpg'},
        ],
      });

      expect(g.categories['Kitchen'], ['https://x/a.jpg']);
      expect(g.unsorted, ['https://x/b.jpg']);
    });

    test('a legacy Unsorted category is folded into the bucket, not rendered '
        'as a room', () {
      final g = GalleryCategories.fromJson({
        'categories': {
          'Kitchen': ['https://x/a.jpg'],
          'Unsorted': ['https://x/b.jpg'],
        },
      });

      expect(g.categories.containsKey('Unsorted'), isFalse);
      expect(g.unsorted, ['https://x/b.jpg']);
    });

    test('a flat map is treated as the category map', () {
      final g = GalleryCategories.fromJson({
        'Kitchen': ['https://x/a.jpg'],
        'unsorted': ['https://x/b.jpg'],
      });

      expect(g.categories['Kitchen'], ['https://x/a.jpg']);
      expect(g.unsorted, ['https://x/b.jpg']);
    });

    test('a server mid-migration sending both spellings does not duplicate', () {
      final g = GalleryCategories.fromJson({
        'categories': {
          'Unsorted': ['https://x/b.jpg'],
        },
        'unsorted': ['https://x/b.jpg'],
      });

      expect(g.unsorted, ['https://x/b.jpg']);
    });

    test('junk degrades to empty rather than throwing', () {
      expect(GalleryCategories.fromJson(null).totalCount, 0);
      expect(GalleryCategories.fromJson('nope').totalCount, 0);
      expect(
        GalleryCategories.fromJson({
          'categories': {'Kitchen': 'not-a-list'},
          'unsorted': 12,
        }).totalCount,
        0,
      );
    });

    test('empty urls are dropped so the grid never renders a blank tile', () {
      final g = GalleryCategories.fromJson({
        'categories': {
          'Kitchen': ['', 'https://x/a.jpg'],
        },
        'unsorted': [
          {'url': ''},
        ],
      });

      expect(g.categories['Kitchen'], ['https://x/a.jpg']);
      expect(g.unsorted, isEmpty);
    });
  });

  group('GalleryAssignResult.fromJson', () {
    test('reads a full success', () {
      final r = GalleryAssignResult.fromJson({
        'message': "2 photo(s) filed under 'Kitchen'.",
        'moved': 2,
        'unknown_images': [],
        'room_tag': 'Kitchen',
        'gallery_categories': {
          'categories': {
            'Kitchen': ['https://x/b.jpg', 'https://x/c.jpg'],
          },
          'unsorted': [],
        },
        'available_tags': ['Bedroom 1', 'Kitchen', 'Entrance Hall'],
      });

      expect(r.moved, 2);
      expect(r.roomTag, 'Kitchen');
      expect(r.isPartial, isFalse);
      expect(r.categories.categories['Kitchen'], hasLength(2));
      expect(r.categories.unsorted, isEmpty);
      // The tag list is whatever the server sent, however long — nothing here
      // assumes a fixed vocabulary of room names.
      expect(r.availableTags, contains('Entrance Hall'));
    });

    test('moved > 0 with unknown_images is a partial success, not a failure',
        () {
      final r = GalleryAssignResult.fromJson({
        'message': "1 photo(s) filed under 'Kitchen'.",
        'moved': 1,
        'unknown_images': ['https://x/gone.jpg'],
        'room_tag': 'Kitchen',
        'gallery_categories': {'categories': {}, 'unsorted': []},
        'available_tags': ['Kitchen'],
      });

      expect(r.isPartial, isTrue);
      expect(r.unknownImages, ['https://x/gone.jpg']);
    });

    test('room_tag null means the photos went back to Unsorted', () {
      final r = GalleryAssignResult.fromJson({
        'message': '2 photo(s) moved to Unsorted.',
        'moved': 2,
        'unknown_images': [],
        'room_tag': null,
        'gallery_categories': {
          'categories': {},
          'unsorted': ['https://x/b.jpg', 'https://x/c.jpg'],
        },
        'available_tags': ['Kitchen'],
      });

      expect(r.roomTag, isNull);
      expect(r.categories.unsorted, hasLength(2));
    });

    test('a filed photo leaves its old room rather than appearing in both', () {
      // The server recomputes the whole gallery, and callers adopt it
      // wholesale — that is what makes a re-file a move.
      final before = GalleryCategories.fromJson({
        'categories': {
          'Kitchen': ['https://x/b.jpg'],
        },
        'unsorted': [],
      });
      final after = GalleryAssignResult.fromJson({
        'message': "1 photo(s) filed under 'Lounge'.",
        'moved': 1,
        'unknown_images': [],
        'room_tag': 'Lounge',
        'gallery_categories': {
          'categories': {
            'Kitchen': [],
            'Lounge': ['https://x/b.jpg'],
          },
          'unsorted': [],
        },
        'available_tags': ['Kitchen', 'Lounge'],
      }).categories;

      expect(before.categories['Kitchen'], ['https://x/b.jpg']);
      expect(after.categories['Kitchen'], isEmpty);
      expect(after.categories['Lounge'], ['https://x/b.jpg']);
      expect(after.totalCount, 1);
    });
  });
}
