import 'package:flutter_test/flutter_test.dart';
import 'package:corex_mobile/services/image_cache.dart';

/// `CoreXImageCache.thumbUrl` must mirror the backend's
/// `PropertyThumbnailService::thumbRelPath` exactly — a wrong rewrite doesn't
/// crash, it silently 404s and falls back to the full-size original, which is
/// the 30 MB-per-property problem this exists to fix.
void main() {
  group('CoreXImageCache.thumbUrl', () {
    test('rewrites a property photo to its thumbs/ sibling as .jpg', () {
      expect(
        CoreXImageCache.thumbUrl(
            'https://corexos.co.za/storage/properties/6058/abc123.jpg'),
        'https://corexos.co.za/storage/properties/6058/thumbs/abc123.jpg',
      );
    });

    test('png / webp / JPEG originals all map to a .jpg thumb', () {
      for (final ext in ['png', 'webp', 'jpeg', 'JPG', 'PNG']) {
        expect(
          CoreXImageCache.thumbUrl(
              'https://h/storage/properties/1/photo.$ext'),
          'https://h/storage/properties/1/thumbs/photo.jpg',
          reason: ext,
        );
      }
    });

    test('preserves a query string', () {
      expect(
        CoreXImageCache.thumbUrl(
            'https://h/storage/properties/1/photo.jpg?v=3'),
        'https://h/storage/properties/1/thumbs/photo.jpg?v=3',
      );
    });

    test('leaves an existing thumb URL alone', () {
      const thumb = 'https://h/storage/properties/1/thumbs/photo.jpg';
      expect(CoreXImageCache.thumbUrl(thumb), thumb);
    });

    test('leaves non-property images alone', () {
      const urls = [
        'https://h/storage/avatars/12.jpg',
        'https://h/storage/agencies/logo.png',
        'https://h/storage/properties/notanid/x.jpg',
        'https://h/storage/properties/1/deeper/x.jpg',
        'https://h/storage/properties/1/x.gif',
        'https://cdn.example.com/x.jpg',
        '',
      ];
      for (final u in urls) {
        expect(CoreXImageCache.thumbUrl(u), u, reason: u);
      }
    });

    test('works on a relative or protocol-relative URL', () {
      expect(
        CoreXImageCache.thumbUrl('/storage/properties/9/a.jpg'),
        '/storage/properties/9/thumbs/a.jpg',
      );
      expect(
        CoreXImageCache.thumbUrl('//h/storage/properties/9/a.jpg'),
        '//h/storage/properties/9/thumbs/a.jpg',
      );
    });
  });
}
