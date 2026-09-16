import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corex_mobile/services/image_cache.dart';

/// The session memo behind `CoreXPhoto`'s "skip a thumb we already know is
/// missing" path. Only a definite 404 may be memoised — anything else would
/// pin the full-size fallback for the rest of the session after a blip.
void main() {
  const thumb = 'https://h/storage/properties/1/thumbs/a.jpg';

  setUp(CoreXImageCache.resetMissingThumbs);

  test('a 404 marks the thumb missing', () {
    expect(CoreXImageCache.isThumbMissing(thumb), isFalse);
    final recorded = CoreXImageCache.noteThumbFailure(
        thumb, const HttpExceptionWithStatus(404, 'Invalid statusCode: 404'));
    expect(recorded, isTrue);
    expect(CoreXImageCache.isThumbMissing(thumb), isTrue);
  });

  test('a transient failure is not memoised', () {
    final transient = <Object>[
      const HttpExceptionWithStatus(500, 'Invalid statusCode: 500'),
      const HttpExceptionWithStatus(503, 'Invalid statusCode: 503'),
      const SocketException('offline'),
      'timeout',
    ];
    for (final e in transient) {
      expect(CoreXImageCache.noteThumbFailure(thumb, e), isFalse,
          reason: '$e');
      expect(CoreXImageCache.isThumbMissing(thumb), isFalse, reason: '$e');
    }
  });

  test('is bounded, dropping the oldest entry first', () {
    const notFound = HttpExceptionWithStatus(404, 'Invalid statusCode: 404');
    for (var i = 0; i < CoreXImageCache.missingThumbCap; i++) {
      CoreXImageCache.noteThumbFailure('https://h/t/$i.jpg', notFound);
    }
    expect(CoreXImageCache.isThumbMissing('https://h/t/0.jpg'), isTrue);
    CoreXImageCache.noteThumbFailure('https://h/t/overflow.jpg', notFound);
    expect(CoreXImageCache.isThumbMissing('https://h/t/0.jpg'), isFalse);
    expect(CoreXImageCache.isThumbMissing('https://h/t/1.jpg'), isTrue);
    expect(CoreXImageCache.isThumbMissing('https://h/t/overflow.jpg'), isTrue);
  });
}
