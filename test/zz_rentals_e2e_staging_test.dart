// TEMPORARY end-to-end run against Staging — delete after use. Uses the
// app's own services and offline queue so the requests are exactly the app's.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corex_mobile/screens/rentals/client/client_inspection_screens.dart';
import 'package:corex_mobile/screens/rentals/staff/staff_inspections_screens.dart';
import 'package:corex_mobile/services/api_service.dart';
import 'package:corex_mobile/services/client_auth_service.dart';
import 'package:corex_mobile/services/rentals/client_rentals_api.dart';
import 'package:corex_mobile/services/rentals/rental_write_queue.dart';
import 'package:corex_mobile/services/rentals/staff_rentals_api.dart';
import 'package:corex_mobile/services/rentals/rentals_http.dart';
import 'package:corex_mobile/utils/uuid.dart';

const _work = String.fromEnvironment('WORK');
const _agentEmail = String.fromEnvironment('AGENT_EMAIL');
const _agentPw = String.fromEnvironment('AGENT_PW');
const _tenantEmail = String.fromEnvironment('TENANT_EMAIL');
const _tenantPw = String.fromEnvironment('TENANT_PW');

const _inspectionId = 4; // draft Out Inspection, lease 2 [DEMO]
const _leaseId = 2;
const _inventoryId = 1; // draft inventory [DEMO]

final _api = StaffRentalsApi.instance;
final _queue = RentalWriteQueue.instance;
final _log = <String>[];

void say(String s) {
  _log.add(s);
  // ignore: avoid_print
  print('E2E | $s');
}

String outcome(SubmitOutcome o) => switch (o) {
      SubmitSent(:final body) =>
        'SENT duplicate=${body['duplicate']} id=${body['id']}',
      SubmitQueued(:final reason) => 'QUEUED ($reason)',
      SubmitRefused(:final error) =>
        'REFUSED ${error.statusCode} ${error.code ?? ''} ${error.message}',
      SubmitArchived(:final message) => 'ARCHIVED $message',
    };

Future<void> waitDrained(String group, {int seconds = 90}) async {
  final until = DateTime.now().add(Duration(seconds: seconds));
  while (_queue.itemsIn(group)
      .any((q) => q.state != QueuedWriteState.failed)) {
    if (DateTime.now().isAfter(until)) {
      fail('queue $group did not drain: '
          '${_queue.itemsIn(group).map((q) => '${q.label}:${q.state}:${q.error}').join('; ')}');
    }
    _queue.kick();
    await Future.delayed(const Duration(milliseconds: 500));
  }
}

void main() {
  late String photoPath;
  if (_agentEmail.isEmpty) {
    test('Staging E2E (needs --dart-define logins)', () {},
        skip: 'run with AGENT_EMAIL etc. to hit Staging');
    return;
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null; // real network for this run
    SharedPreferences.setMockInitialValues({});
    final vault = <String, String>{};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (c) async {
      final key = (c.arguments as Map?)?['key'] as String?;
      switch (c.method) {
        case 'read':
          return vault[key];
        case 'write':
          vault[key!] = (c.arguments as Map)['value'] as String;
          return null;
        case 'delete':
          vault.remove(key);
          return null;
        case 'readAll':
          return vault;
        case 'containsKey':
          return vault.containsKey(key);
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (c) async => '$_work/support');

    final image = img.Image(width: 320, height: 240);
    img.fill(image, color: img.ColorRgb8(14, 165, 233));
    photoPath = '$_work/e2e.jpg';
    File(photoPath).writeAsBytesSync(img.encodeJpg(image));

    final login = await ApiService().login(_agentEmail, _agentPw);
    await ApiService().saveToken(login['token'] as String);
    final user = login['user'] as Map;
    _queue.setSession('user:${user['id']}');
    say('agent signed in: ${user['name']} (agency ${(user['agency'] as Map)['name']})');
  });

  tearDownAll(() {
    File('$_work/e2e-report.txt').writeAsStringSync(_log.join('\n'));
  });

  test('1. visibility: rentals_enabled + per-screen flags', () async {
    final v = await ApiService().getVisibility();
    say('visibility rentals_enabled=${v.rentalsEnabled} '
        'inspections.can_act=${v.rentals.inspections.canAct} '
        'inventories.can_act=${v.rentals.inventories.canAct}');
    expect(v.rentalsEnabled, isTrue);
    expect(v.rentals.inspections.canAct, isTrue);
  });

  test('2. inspection photos: item, room, loose — both ways', () async {
    final before = await _api.inspection(_inspectionId);
    final room = before.obj('checklist')!.objs('rooms').first;
    final roomId = room.integer('id')!;
    final item = room.objs('items').firstWhere((i) => !i.flag('is_retired'));
    final itemId = item.integer('id')!;
    say('inspection #$_inspectionId ${before.str('type_label')} '
        '${before.str('status')} — ${before.objs('photos').length} photos before; '
        'room ${room.str('label')} ($roomId), item ${item.str('label')} ($itemId)');

    final sent = <String, int>{};
    for (final (what, itemArg, roomArg) in [
      ('item', itemId, null),
      ('room', null, roomId),
      ('loose', null, null),
    ]) {
      final r = await _api.addInspectionPhoto(
        inspectionRef: '$_inspectionId',
        photoPath: photoPath,
        itemId: itemArg,
        roomId: roomArg,
        label: 'E2E $what photo',
      );
      say('POST photo ($what): ${outcome(r.outcome)}'
          '${r.outcome is SubmitSent ? ' item_id=${(r.outcome as SubmitSent).body['item_id']} room_id=${(r.outcome as SubmitSent).body['room_id']}' : ''}');
      expect(r.outcome, isA<SubmitSent>());
      sent[what] = (r.outcome as SubmitSent).body.integer('id')!;
    }

    // A retry with the same key must answer duplicate, never a 2nd photo.
    final key = uuidV4();
    final first = await _queue.submit(
      audience: RentalsAudience.staff,
      path: '/mobile/rental-inspections/$_inspectionId/photos',
      label: 'E2E replay #1',
      files: {'photo': photoPath},
      fields: {'captured_at': DateTime.now().toIso8601String()},
      idempotencyKey: key,
    );
    final replay = await _queue.submit(
      audience: RentalsAudience.staff,
      path: '/mobile/rental-inspections/$_inspectionId/photos',
      label: 'E2E replay #2',
      files: {'photo': photoPath},
      fields: {'captured_at': DateTime.now().toIso8601String()},
      idempotencyKey: key,
    );
    say('replay same key: first ${outcome(first.outcome)}; second ${outcome(replay.outcome)}');
    expect((replay.outcome as SubmitSent).body['duplicate'], isTrue);
    expect((replay.outcome as SubmitSent).body['id'],
        (first.outcome as SubmitSent).body['id']);
    sent['replay'] = (first.outcome as SubmitSent).body.integer('id')!;

    final after = await _api.inspection(_inspectionId);
    final photos = after.objs('photos');
    final ids = photos.map((p) => p.integer('id')).toSet();
    final places = placeInspectionPhotos(
      photos,
      {
        for (final r in after.obj('checklist')!.objs('rooms'))
          for (final i in r.objs('items')) i.integer('id')!
      },
      {for (final r in after.obj('checklist')!.objs('rooms')) r.integer('id')!},
    );
    say('detail after: ${photos.length} photos; ours all present=${sent.values.every(ids.contains)}; '
        'item→${places.byItem[itemId]?.any((p) => p.integer('id') == sent['item'])} '
        'room→${places.byRoom[roomId]?.any((p) => p.integer('id') == sent['room'])} '
        'tray→${places.tray.any((p) => p.integer('id') == sent['loose'])}; '
        'urls signed=${photos.every((p) => (p.str('url') ?? '').contains('signature='))}');
    expect(sent.values.every(ids.contains), isTrue);
    expect(places.byItem[itemId]!.any((p) => p.integer('id') == sent['item']), isTrue);
    expect(places.byRoom[roomId]!.any((p) => p.integer('id') == sent['room']), isTrue);
    expect(places.tray.any((p) => p.integer('id') == sent['loose']), isTrue);
    final obs = after.objs('observations').where((o) => o.integer('item_id') == itemId);
    say('item photo created/attached an observation for the item: ${obs.isNotEmpty}');
    expect(_queue.itemsIn(StaffRentalsApi.inspectionGroup('$_inspectionId')), isEmpty);
  });

  test('3. Out Inspection: lease opens the existing one; a 2nd start is refused cleanly', () async {
    final page = await _api.inspections(1, {'lease_id': '$_leaseId', 'type': 'out'});
    final open = page.items.where((i) => i.str('status') != 'cancelled').toList();
    say('lease $_leaseId Out Inspections: ${open.map((i) => '#${i.integer('id')} ${i.str('status')}').join(', ')} '
        '→ the app opens #${open.first.integer('id')}');
    expect(open, isNotEmpty);

    final r = await _api.startInspection(
        leaseId: _leaseId, type: 'out', label: 'E2E start Out');
    say('POST start Out on lease $_leaseId: ${outcome(r.outcome)}');
    if (r.outcome is SubmitRefused) {
      // Refused writes wait in the queue for the person to retry/discard.
      await _queue.discard(r.id);
    }
    expect(_queue.itemsIn('lease:$_leaseId:start'), isEmpty);

    final due = await _api.inspectionsDue(1, {'type': 'out', 'status': 'all'});
    say('GET due?type=out: ${due.items.length} rows');
  });

  test('4a. inventory lines online: add → web shows it → change → remove', () async {
    final inv0 = await _api.inventory(_inventoryId);
    say('inventory #$_inventoryId ${inv0.str('status')} editable=${inv0.flag('editable')} '
        'rooms=${inv0.objs('rooms').map((r) => r.str('label')).join('/')} '
        'conditions=${inv0.objs('condition_states').map((c) => c.str('key')).join('/')}');
    expect(inv0.flag('editable'), isTrue);
    final room = inv0.objs('rooms').isEmpty ? null : inv0.objs('rooms').first;
    final cond = inv0.objs('condition_states').isEmpty
        ? null
        : inv0.objs('condition_states').first.str('key');

    final add = await _api.addInventoryLine(
      inventoryId: _inventoryId,
      description: 'E2E Wooden bed',
      roomId: room?.integer('id'),
      roomLabel: room == null ? 'Bedroom 1' : null,
      quantity: 1,
      conditionKey: cond,
    );
    say('POST line: ${outcome(add.outcome)}');
    final lineId = (add.outcome as SubmitSent).body.integer('id')!;
    var inv = await _api.inventory(_inventoryId);
    var line = inv.objs('lines').where((l) => l.integer('id') == lineId);
    say('web after add: line present=${line.isNotEmpty} '
        '${line.isEmpty ? '' : '${line.first.integer('quantity')} × ${line.first.str('description')} in ${line.first.str('room_label')} [${line.first.str('condition_key')}]'}');
    expect(line, isNotEmpty);

    final upd = await _api.updateInventoryLine(
      inventoryId: _inventoryId,
      lineRef: '$lineId',
      description: 'E2E Wooden double bed',
      roomId: room?.integer('id'),
      roomLabel: room == null ? 'Bedroom 1' : null,
      quantity: 2,
      conditionKey: cond,
    );
    say('PUT line: ${outcome(upd.outcome)}');
    inv = await _api.inventory(_inventoryId);
    line = inv.objs('lines').where((l) => l.integer('id') == lineId);
    say('web after change: ${line.first.integer('quantity')} × ${line.first.str('description')}');
    expect(line.first.str('description'), 'E2E Wooden double bed');
    expect(line.first.integer('quantity'), 2);

    final ret = await _api.retireInventoryLine(
        inventoryId: _inventoryId, lineRef: '$lineId', description: 'E2E');
    say('POST retire: ${outcome(ret.outcome)}');
    final again = await _api.retireInventoryLine(
        inventoryId: _inventoryId, lineRef: '$lineId', description: 'E2E');
    say('POST retire again: ${outcome(again.outcome)}');
    inv = await _api.inventory(_inventoryId);
    say('web after remove: line still listed=${inv.objs('lines').any((l) => l.integer('id') == lineId)}');
    expect(inv.objs('lines').any((l) => l.integer('id') == lineId), isFalse);
    expect(_queue.itemsIn(StaffRentalsApi.inventoryGroup(_inventoryId)), isEmpty);
  });

  test('4b. inventory offline: add + change + photo + remove queued, then drain', () async {
    final inv0 = await _api.inventory(_inventoryId);
    final room = inv0.objs('rooms').isEmpty ? null : inv0.objs('rooms').first;
    final group = StaffRentalsApi.inventoryGroup(_inventoryId);
    _queue.autoDrain = false; // "no signal": everything waits on the phone
    final addId = await _queue.enqueue(
      audience: RentalsAudience.staff,
      path: '/mobile/rental-inventories/$_inventoryId/lines',
      label: 'E2E offline add',
      group: group,
      fields: StaffRentalsApi.lineFields(
          description: 'E2E offline chair',
          roomId: room?.integer('id'),
          roomLabel: room == null ? 'Bedroom 1' : null,
          quantity: 4),
    );
    await _queue.enqueue(
      audience: RentalsAudience.staff,
      method: 'PUT',
      sendKey: false,
      path: '/mobile/rental-inventories/$_inventoryId/lines/{ref:$addId}',
      label: 'E2E offline change',
      group: group,
      dependsOn: addId,
      fields: StaffRentalsApi.lineFields(
          description: 'E2E offline dining chair',
          roomId: room?.integer('id'),
          roomLabel: room == null ? 'Bedroom 1' : null,
          quantity: 6),
    );
    await _queue.enqueue(
      audience: RentalsAudience.staff,
      path: '/mobile/rental-inventories/$_inventoryId/photos',
      label: 'E2E offline room photo',
      group: group,
      files: {'photo': photoPath},
      fields: {
        if (room != null) 'property_room_id': room.integer('id'),
        'captured_at': DateTime.now().toIso8601String(),
      },
    );
    say('queued offline: ${_queue.itemsIn(group).length} writes');
    _queue.autoDrain = true;
    await waitDrained(group);
    final failed = _queue.itemsIn(group);
    say('drained; left in queue: ${failed.length}'
        '${failed.isEmpty ? '' : ' → ${failed.map((q) => '${q.label}: ${q.error}').join('; ')}'}');
    final lineId = _queue.resultFor(addId);
    final inv = await _api.inventory(_inventoryId);
    final line = inv.objs('lines').where((l) => l.integer('id') == lineId);
    say('web after drain: line #$lineId ${line.isEmpty ? 'MISSING' : '${line.first.integer('quantity')} × ${line.first.str('description')}'}; '
        'room photos now: ${inv.objs('photos').length}');
    expect(failed, isEmpty);
    expect(line.first.str('description'), 'E2E offline dining chair');

    final ret = await _api.retireInventoryLine(
        inventoryId: _inventoryId, lineRef: '$lineId', description: 'E2E');
    say('cleanup retire offline line: ${outcome(ret.outcome)}');
  });

  test('5. tenant: /client/me flags + read-only Inspection / Out Inspection', () async {
    final auth = ClientAuthService();
    final login = await auth.login(
        email: _tenantEmail, password: _tenantPw, deviceName: 'E2E test');
    await auth.saveToken(login.token);
    final me = await auth.me();
    say('tenant signed in; agencies=${me.agencies.map((a) => a.name).join('/')}; '
        'rentals.tenant=${me.rentals.tenant} rentals.owner=${me.rentals.owner}');
    expect(me.rentals.tenant, isTrue);

    for (final side in [
      if (me.rentals.tenant) ClientRentalsApi.tenant,
      if (me.rentals.owner) ClientRentalsApi.owner,
    ]) {
      final name = side.isOwner ? 'owner' : 'tenant';
      final list = (await side.inspections()).objs('inspections');
      say('$name list: ${list.map((r) => '#${r.integer('id')} ${r.str('type')} ${r.str('status')} viewable=${r['viewable']}').join(', ')}');
      for (final r in list.where((r) => r.flag('viewable'))) {
        final body = await side.inspection(r.integer('id')!);
        final i = body.obj('inspection')!;
        final rooms = i.objs('rooms');
        final itemPhotos = rooms.expand((x) => x.objs('items')).expand((x) => x.objs('photos')).length;
        final roomPhotos = rooms.expand((x) => x.objs('photos')).length;
        final withMoveIn = rooms.expand((x) => x.objs('items')).where((x) => x.containsKey('move_in')).length;
        final ownerFields = side.isOwner ? const <String>[] : reportOwnerFields(i);
        say('  open $name #${i.integer('id')} ${i.str('type_label')}: rooms=${rooms.length} '
            'item photos=$itemPhotos room photos=$roomPhotos items with move_in=$withMoveIn '
            'signatures=${i.obj('signatures')} related=${i.obj('related')}'
            '${ownerFields.isEmpty ? '' : ' OWNER FIELDS IN TENANT PAYLOAD: $ownerFields'}');
        expect(ownerFields, isEmpty);
      }
      final booked = list.where((r) => r['viewable'] == false);
      for (final r in booked.take(1)) {
        try {
          await side.inspection(r.integer('id')!);
          say('  booked #${r.integer('id')} opened — UNEXPECTED');
        } on Exception catch (e) {
          say('  booked #${r.integer('id')} → $e (expected 404)');
        }
      }
    }
  });
}

