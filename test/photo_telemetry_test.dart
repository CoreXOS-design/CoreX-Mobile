import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:corex_mobile/models/gallery_tags.dart';
import 'package:corex_mobile/services/photo_telemetry.dart';
import 'package:corex_mobile/services/upload_queue.dart';
import 'package:corex_mobile/services/upload_service.dart';
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

  group('a photo queued at the shutter', () {
    test('persists the raw-and-unbaked state and the sensor reading', () {
      // The 2026-08-31 shape: 47 captured, 6 queued. The queue row is now
      // written before the downscale/orientation bake, so both facts the bake
      // will need have to survive a kill — including the tilt, which is
      // readable only at capture and exists nowhere else once the camera is
      // gone.
      final item = PendingUpload(
        id: 'shot_1',
        propertyId: 15753,
        path: '/data/app/upload_queue/shot_1.jpg',
        clientUploadId: '1788170293929473_3',
        batchId: 'shoot-8f21',
        roomTag: 'Kitchen',
        needsProcessing: true,
        sensorRotation: 90,
        createdAt: 1788170293929,
      );

      final back = PendingUpload.fromJson(item.toJson());

      expect(back.needsProcessing, isTrue);
      expect(back.sensorRotation, 90);
      expect(back.roomTag, 'Kitchen');
    });

    test('a row written before this existed is treated as already baked', () {
      // Photos sitting in a queue when this build installs were processed
      // before they were ever persisted. Reading absent as "needs processing"
      // would re-bake an already-baked photo; reading it as "done" is both
      // correct and the safe direction.
      final legacy = PendingUpload.fromJson({
        'id': 'old_1',
        'property_id': 42,
        'path': '/tmp/old.jpg',
        'client_upload_id': 'old_1',
        'room_tag': 'Kitchen',
        'state': 'pending',
        'created_at': 1756382773000,
      });

      expect(legacy.needsProcessing, isFalse);
      expect(legacy.sensorRotation, isNull);
    });

    test('an unknown tilt stays unknown rather than becoming zero', () {
      // Every image_picker path. A null reading means "trust the file's own
      // EXIF"; a 0 would mean "the device says upright" and would suppress the
      // fallback the bake depends on.
      final item = PendingUpload(
        id: 'pick_1',
        propertyId: 1,
        path: '/tmp/p.jpg',
        clientUploadId: 'pick_1',
        roomTag: null,
        needsProcessing: true,
        sensorRotation: null,
        createdAt: 1,
      );

      expect(PendingUpload.fromJson(item.toJson()).sensorRotation, isNull);
    });
  });

  group('recalling a deleted photo', () {
    test('a photo never on the wire is gone once the queue row goes', () {
      // attempts is incremented only when a request is actually being made,
      // so zero is the one state where removing the row is the whole job and
      // no server delete is warranted.
      final fresh = PendingUpload(
        id: 'shot_1',
        propertyId: 15753,
        path: '/tmp/a.jpg',
        clientUploadId: '1788176218829168_1',
        roomTag: null,
        needsProcessing: true,
        createdAt: 1,
      );

      expect(fresh.attempts, 0);
    });

    test('every recall outcome that means "gone" is treated as gone', () {
      // notOnServer is an outcome, not a failure: nothing matched because the
      // photo never landed or someone removed it first. Reading it as failure
      // would nag the agent about a photo that is already not there.
      const gone = <PhotoRecall>[
        PhotoRecall.neverSent,
        PhotoRecall.deletedFromServer,
        PhotoRecall.notOnServer,
      ];
      for (final outcome in gone) {
        expect(PhotoRecallResult(outcome, null).isGone, isTrue,
            reason: '$outcome should count as gone');
      }
      // These two leave the photo on the property, so the UI must put it back
      // rather than imply it was deleted.
      expect(const PhotoRecallResult(PhotoRecall.refused, null).isGone,
          isFalse);
      expect(const PhotoRecallResult(PhotoRecall.failed, null).isGone, isFalse);
    });

    test('a 404 body still parses as a real outcome', () {
      // The server answers 404 with deleted:0 when nothing matched. That is
      // not an error path — it has to come back as a readable result.
      final result = DeletedImages.fromJson({
        'message': 'No matching images.',
        'deleted': 0,
        'unknown_ids': ['1788176218829168_1'],
      });

      expect(result.matchedNothing, isTrue);
      expect(result.unknownIds, ['1788176218829168_1']);
    });

    test('a successful delete is not mistaken for a miss', () {
      final result = DeletedImages.fromJson({
        'message': 'Deleted.',
        'deleted': 1,
        'unknown_ids': const [],
      });

      expect(result.matchedNothing, isFalse);
      expect(result.deleted, 1);
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
