import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:corex_mobile/services/photo_telemetry.dart';
import 'package:corex_mobile/services/upload_queue.dart';
import 'package:corex_mobile/utils/image_processing.dart';

/// The wire contract behind the 2026-08-31 incident.
///
/// An agent shot ~40 photos on listing 15753 and 28 arrived; the only reason we
/// could prove the other 12 were never enqueued is that `client_upload_id`
/// happened to run 1..28 with no gaps. These tests pin the two things that turn
/// that excavation into an answer: the phase names the server groups on, and
/// the fact that a photo's id exists from the shutter rather than from the
/// queue.
///
/// The durable log itself needs `path_provider` and a real filesystem, so it is
/// exercised by the on-device definition of done (shoot ten, force-kill,
/// reopen) rather than here.
void main() {
  group('phase names', () {
    test('match the six phases the server accepts', () {
      expect(PhotoPhase.captured.wire, 'captured');
      expect(PhotoPhase.queued.wire, 'queued');
      expect(PhotoPhase.uploadStarted.wire, 'upload_started');
      expect(PhotoPhase.uploadOk.wire, 'upload_ok');
      expect(PhotoPhase.uploadFailed.wire, 'upload_failed');
      expect(PhotoPhase.dropped.wire, 'dropped');
    });

    test('there is no client-side "received"', () {
      // The server writes `received` itself when the bytes land and rejects it
      // from a client. "Did it actually arrive" is the one thing the phone
      // cannot witness, and it is the whole question — so the enum must not
      // grow a way to claim it.
      expect(
        PhotoPhase.values.map((p) => p.wire),
        isNot(contains('received')),
      );
      expect(PhotoPhase.values, hasLength(6));
    });
  });

  group('a photo is named at the shutter', () {
    test('every capture gets its own id', () {
      final a = CapturedPhoto(File('/tmp/a.jpg'));
      final b = CapturedPhoto(File('/tmp/b.jpg'));

      expect(a.uploadId, isNotEmpty);
      expect(a.uploadId, isNot(b.uploadId));
    });

    test('the id survives into the queue row unchanged', () {
      // The join between `captured` (filed before the queue row exists) and
      // everything after it. If enqueue re-issued the key, the report would
      // show two photos where there is one, and the gap we are hunting would
      // be indistinguishable from an ordinary upload.
      final photo = CapturedPhoto(File('/tmp/a.jpg'));
      final item = PendingUpload(
        id: 'queue_row_1',
        propertyId: 15753,
        path: '/data/app/upload_queue/queue_row_1.jpg',
        clientUploadId: photo.uploadId,
        batchId: 'shoot-8f21',
        roomTag: 'Bedroom 2',
        createdAt: 1788170293929,
      );

      expect(PendingUpload.fromJson(item.toJson()).clientUploadId,
          photo.uploadId);
    });
  });

  group('PendingUpload batch id', () {
    test('round-trips, so a replay days later reports under its own shoot', () {
      final item = PendingUpload(
        id: 'a_1',
        propertyId: 15753,
        path: '/tmp/a.jpg',
        clientUploadId: 'a_1',
        batchId: 'shoot-8f21',
        roomTag: null,
        createdAt: 1,
      );

      expect(PendingUpload.fromJson(item.toJson()).batchId, 'shoot-8f21');
    });

    test('is null for rows written before it existed', () {
      // Photos already sitting in a queue when this build installs must still
      // upload; an absent batch id is missing context, never a broken row.
      final legacy = PendingUpload.fromJson({
        'id': 'old_1',
        'property_id': 42,
        'path': '/tmp/old.jpg',
        'client_upload_id': 'old_1',
        'room_tag': 'Kitchen',
        'state': 'pending',
        'created_at': 1756382773000,
        'attempts': 2,
      });

      expect(legacy.batchId, isNull);
      expect(legacy.clientUploadId, 'old_1');
      expect(legacy.roomTag, 'Kitchen');
    });
  });
}
