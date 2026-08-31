import 'package:flutter_test/flutter_test.dart';

import 'package:corex_mobile/services/upload_queue.dart';

/// The durability contract behind the 2026-08-28 incident.
///
/// 27 photos reached the server with `room_tag` absent because the selected
/// room lived in a screen's state rather than on the queued item. These tests
/// pin the round-trip that has to survive an app kill: whatever the POST needs
/// goes into the store and comes back out identical, `roomTag` included.
///
/// Serialisation is tested directly rather than through [UploadQueue], which
/// needs SharedPreferences and a real filesystem; the persisted JSON is the
/// thing that actually crosses the process boundary.
void main() {
  group('PendingUpload round-trip', () {
    test('carries the whole upload intent, room tag included', () {
      final item = PendingUpload(
        id: '1756382773000000_9',
        propertyId: 42,
        path: '/data/app/upload_queue/1756382773000000_9.jpg',
        clientUploadId: '1756382773000000_9',
        roomTag: 'Bathroom 3',
        createdAt: 1756382773000,
      );

      final back = PendingUpload.fromJson(item.toJson());

      expect(back.id, item.id);
      expect(back.propertyId, 42);
      expect(back.path, item.path);
      expect(back.clientUploadId, item.clientUploadId);
      expect(back.roomTag, 'Bathroom 3');
      expect(back.createdAt, 1756382773000);
    });

    test('a null room tag survives as null — untagged is a choice, not a gap',
        () {
      final item = PendingUpload(
        id: 'a_1',
        propertyId: 7,
        path: '/tmp/a.jpg',
        clientUploadId: 'a_1',
        roomTag: null,
        createdAt: 1,
      );

      expect(item.toJson()['room_tag'], isNull);
      expect(PendingUpload.fromJson(item.toJson()).roomTag, isNull);
    });

    test('a tag with a space type outside the old fixed set survives', () {
      // The Spaces editor now offers ~50 types. Nothing in the queue may
      // validate a tag against a hard-coded room vocabulary.
      for (final tag in const [
        'Entrance Hall',
        'Scullery',
        'Braai Room',
        'Laundry Room',
        'Office',
      ]) {
        final item = PendingUpload(
          id: 'x',
          propertyId: 1,
          path: '/tmp/x.jpg',
          clientUploadId: 'x',
          roomTag: tag,
          createdAt: 1,
        );
        expect(PendingUpload.fromJson(item.toJson()).roomTag, tag);
      }
    });

    test('an item killed mid-request comes back pending, never uploading', () {
      // `uploading` is transient. Persisting it would leave a photo in a state
      // nothing moves it out of, i.e. stranded exactly as before.
      final item = PendingUpload(
        id: 'a_1',
        propertyId: 7,
        path: '/tmp/a.jpg',
        clientUploadId: 'a_1',
        roomTag: 'Kitchen',
        state: PendingUploadState.uploading,
        createdAt: 1,
      );

      expect(item.toJson()['state'], 'pending');
      expect(PendingUpload.fromJson(item.toJson()).state,
          PendingUploadState.pending);
    });

    test('a failed item stays failed, with the server message intact', () {
      final item = PendingUpload(
        id: 'a_1',
        propertyId: 7,
        path: '/tmp/a.jpg',
        clientUploadId: 'a_1',
        roomTag: null,
        state: PendingUploadState.failed,
        error: 'Image is too large to upload. Please try a smaller photo.',
        createdAt: 1,
        attempts: 3,
      );

      final back = PendingUpload.fromJson(item.toJson());
      expect(back.state, PendingUploadState.failed);
      expect(back.error, contains('too large'));
      expect(back.attempts, 3);
    });

    test('an item written before client_upload_id was persisted still dedupes',
        () {
      // Migration: the old build used the id as the idempotency key, so a photo
      // queued then and replayed now must present the same key.
      final back = PendingUpload.fromJson({
        'id': 'legacy_4',
        'property_id': 42,
        'path': '/tmp/legacy.jpg',
        'room_tag': 'Bathroom 3',
        'state': 'pending',
        'created_at': 1756382773000,
      });

      expect(back.clientUploadId, 'legacy_4');
      expect(back.roomTag, 'Bathroom 3');
      expect(back.attempts, 0);
    });
  });
}
