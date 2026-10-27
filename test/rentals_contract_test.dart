import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/widgets.dart';

import 'package:corex_mobile/models/client_models.dart';
import 'package:corex_mobile/models/visibility.dart';
import 'package:corex_mobile/providers/rentals_access_provider.dart';
import 'package:corex_mobile/screens/rentals/client/client_inspection_screens.dart';
import 'package:corex_mobile/screens/rentals/client/owner_rentals_screens.dart';
import 'package:corex_mobile/screens/rentals/staff/staff_inspections_screens.dart';
import 'package:corex_mobile/services/rentals/staff_rentals_api.dart';
import 'package:corex_mobile/screens/rentals/client/tenant_rentals_screens.dart';
import 'package:corex_mobile/screens/notifications/notifications_screen.dart';
import 'package:corex_mobile/screens/rentals/staff/staff_faults_screens.dart';
import 'package:corex_mobile/screens/rentals/staff/staff_leases_screens.dart';
import 'package:corex_mobile/screens/rentals/staff/staff_maintenance_actions.dart';
import 'package:corex_mobile/screens/rentals/staff/staff_work_orders_screens.dart';
import 'package:corex_mobile/services/deep_link_router.dart';
import 'package:corex_mobile/services/messaging_service.dart';
import 'package:corex_mobile/services/rentals/rental_write_queue.dart';
import 'package:corex_mobile/services/rentals/rentals_http.dart';
import 'package:corex_mobile/utils/uuid.dart';

/// AT-508 rentals: the client-side halves of the server's offline and
/// visibility contract (hfc-dash `.ai/specs/at-508-*`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('idempotency key', () {
    test('is a v4 uuid the server accepts', () {
      final re = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      final keys = {for (var i = 0; i < 200; i++) uuidV4()};
      expect(keys.length, 200, reason: 'keys must not repeat');
      for (final k in keys) {
        expect(re.hasMatch(k), isTrue, reason: k);
        // Client portal rule: ^[A-Za-z0-9._:-]{8,80}$
        expect(RegExp(r'^[A-Za-z0-9._:-]{8,80}$').hasMatch(k), isTrue);
      }
    });
  });

  group('captured_at', () {
    test('carries the phone offset, so it is not read as UTC', () {
      final s = isoWithOffset(DateTime(2026, 10, 25, 9, 14, 3));
      expect(s, matches(RegExp(r'^2026-10-25T09:14:03[+-]\d{2}:\d{2}$')));
      expect(DateTime.parse(s).toLocal(), DateTime(2026, 10, 25, 9, 14, 3));
    });
  });

  group('rentals visibility', () {
    test('a server without the rentals block hides every screen', () {
      final d =
          VisibilityDescriptor.fromJson({'contacts': {}, 'properties': {}});
      expect(d.rentals.any, isFalse);
    });

    test('can_act never outruns can_view', () {
      final r = RentalScreens.fromJson({
        'fault_reports': {'can_view': true, 'can_act': true, 'scope': 'branch'},
        'work_orders': {'can_view': false, 'can_act': true, 'scope': null},
      });
      expect(r.faultReports.canView, isTrue);
      expect(r.faultReports.canAct, isTrue);
      expect(r.faultReports.scope, 'branch');
      expect(r.workOrders.canAct, isFalse);
      expect(r.inspections.canView, isFalse);
      expect(r.any, isTrue);
    });

    test('rentals_enabled false hides every screen, whatever can_view says',
        () {
      final d = VisibilityDescriptor.fromJson({
        'rentals': {
          'waiting': {'can_view': true, 'can_act': true, 'scope': 'own'},
        },
        'rentals_enabled': false,
      });
      expect(d.rentalsEnabled, isFalse);
      expect(d.rentals.any, isFalse);
      expect(d.rentals.waiting.canView, isFalse);
    });

    test('rentals_enabled true keeps the per-screen flags', () {
      final d = VisibilityDescriptor.fromJson({
        'rentals': {
          'waiting': {'can_view': true, 'can_act': false, 'scope': 'own'},
        },
        'rentals_enabled': true,
      });
      expect(d.rentals.waiting.canView, isTrue);
      expect(d.rentals.waiting.canAct, isFalse);
      expect(d.rentals.leases.canView, isFalse);
    });
  });

  group('inspection photos (web ⇄ app)', () {
    Json photo(int id, {int? item, int? room, bool archived = false}) => {
          'id': id,
          'item_id': item,
          'room_id': room,
          'url': 'https://x/$id?signature=s',
          'archived': archived,
        };

    test('placed by item, else room, else the unsorted tray', () {
      final p = placeInspectionPhotos([
        photo(1, item: 587, room: 14), // item wins over its room
        photo(2, room: 14), // general room photo (web)
        photo(3), // loose, the web tray
        photo(4, item: 999, room: 14), // retired / unknown item → its room
        photo(5, item: 999), // unknown item, no room → tray
        photo(6, item: 587, archived: true),
      ], {
        587
      }, {
        14
      });
      expect(p.byItem[587]!.map((e) => e['id']), [1]);
      expect(p.byRoom[14]!.map((e) => e['id']), [2, 4]);
      expect(p.tray.map((e) => e['id']), [3, 5]);
    });

    test('signed links never reach the offline cache', () {
      final d = {
        'id': 3,
        'photos': [photo(1, item: 587)],
        'observations': [
          {
            'id': 25,
            'photos': [photo(1, item: 587)]
          }
        ],
      };
      final cached = withoutPhotoUrls(d);
      expect((cached['photos'] as List).first.containsKey('url'), isFalse);
      expect(
          ((cached['observations'] as List).first['photos'] as List)
              .first
              .containsKey('url'),
          isFalse);
      // The live detail keeps its links.
      expect((d['photos'] as List).first['url'], isNotNull);
    });
  });

  group('inventory lines', () {
    test('a picked room goes as property_room_id, a typed one as room_label',
        () {
      final picked = StaffRentalsApi.lineFields(
          description: 'Wooden double bed',
          roomId: 191,
          quantity: 1,
          conditionKey: 'good');
      expect(picked['property_room_id'], 191);
      expect(picked.containsKey('room_label'), isFalse);
      expect(picked['quantity'], 1);
      expect(picked['condition_key'], 'good');

      final typed = StaffRentalsApi.lineFields(
          description: 'Bed', roomLabel: 'Bedroom 1');
      expect(typed['room_label'], 'Bedroom 1');
      expect(typed.containsKey('property_room_id'), isFalse);
      // Blank quantity is "unknown", sent as null so a change can clear it.
      expect(typed.containsKey('quantity'), isTrue);
      expect(typed['quantity'], isNull);
    });
  });

  group('tenant inspection view', () {
    test('an owner field in a tenant payload is reported', () {
      expect(
          reportOwnerFields({
            'rooms': [],
            'signatures': {'you_signed': true, 'agent_signed': true},
          }),
          isEmpty);
      expect(
          reportOwnerFields({
            'parties': {
              'landlord': {'name': 'x'}
            },
            'signatures': {'tenant_signed': true},
          }),
          containsAll(['parties.landlord', 'signatures.tenant_signed']));
    });
  });

  group('client rentals sides', () {
    test('an old /client/me without the key is neither side', () {
      final s = ClientRentalSides.fromJson(null);
      expect(s.tenant, isFalse);
      expect(s.owner, isFalse);
    });

    test('only a literal true counts', () {
      final s = ClientRentalSides.fromJson({'tenant': true, 'owner': 'yes'});
      expect(s.tenant, isTrue);
      expect(s.owner, isFalse);
    });
  });

  group('rental deep links / pushes', () {
    Widget? open(RentalsAccess a, String audience,
            [String type = 'work_order', int? id = 5]) =>
        DeepLinkRouter.rentalScreen(a, audience, type, id);

    const buyer = RentalsAccess();
    const tenant = RentalsAccess(tenant: true);
    const owner = RentalsAccess(owner: true);
    const both = RentalsAccess(tenant: true, owner: true);

    test('a buyer / seller with neither side goes nowhere', () {
      for (final aud in ['tenant', 'owner', 'client', 'staff']) {
        expect(open(buyer, aud), isNull, reason: aud);
      }
    });

    test('each side only opens its own screens', () {
      expect(open(tenant, 'tenant'), isA<TenantWorkOrderScreen>());
      expect(open(tenant, 'owner'), isNull);
      expect(open(owner, 'owner'), isA<OwnerWorkOrderScreen>());
      expect(open(owner, 'tenant'), isNull);
      expect(open(both, 'owner'), isA<OwnerWorkOrderScreen>());
      expect(open(both, 'tenant'), isA<TenantWorkOrderScreen>());
    });

    test('no audience opens the only side this person has', () {
      expect(open(owner, 'client'), isA<OwnerWorkOrderScreen>());
      expect(open(tenant, 'client'), isA<TenantWorkOrderScreen>());
    });

    test('staff with Rentals off, or without that screen, go Home', () {
      expect(open(const RentalsAccess(), 'staff'), isNull);
      // Work orders hidden: Home, not the rentals hub or a 403 page.
      expect(
          open(
              const RentalsAccess(
                  staffScreens: RentalScreens(
                waiting: RentalScreenAccess(canView: true, canAct: true),
                faultReports: RentalScreenAccess.hidden,
                workOrders: RentalScreenAccess.hidden,
                leases: RentalScreenAccess.hidden,
                notices: RentalScreenAccess.hidden,
                inspections: RentalScreenAccess.hidden,
                inventories: RentalScreenAccess.hidden,
              )),
              'staff'),
          isNull);
    });

    group('agent pushes (target + target_id)', () {
      const all = RentalScreenAccess(canView: true, canAct: true);
      const agent = RentalsAccess(
          staffScreens: RentalScreens(
        waiting: all,
        faultReports: all,
        workOrders: all,
        leases: all,
        notices: all,
        inspections: all,
        inventories: all,
      ));

      test('each target opens its record', () {
        expect(open(agent, 'agent', 'fault', 7), isA<StaffFaultDetailScreen>());
        expect(open(agent, 'agent', 'work_order', 7),
            isA<StaffWorkOrderDetailScreen>());
        expect(open(agent, 'agent', 'lease', 7), isA<StaffLeaseFileScreen>());
        expect(
            open(agent, 'agent', 'lease_notice', 7), isA<StaffNoticesScreen>());
        expect(open(agent, 'agent', 'inspection', 7),
            isA<StaffInspectionScreen>());
      });

      test('a job card opens its screen (parity: the web job-card actions)', () {
        expect(open(agent, 'agent', 'job_card', 7), isA<StaffJobCardScreen>());
      });

      test('a target with no app screen lands on the notifications list', () {
        expect(
            open(agent, 'agent', 'application', 7), isA<NotificationsScreen>());
      });

      test('a target is the app route, ahead of the web action_url', () {
        final url = MessagingService.resolveAction({
          'event_key': 'rental.fault.reported',
          'subject_type': r'App\Models\RentalFaultReport',
          'subject_id': '42',
          'action_url': '/corex/rental-fault-reports/42',
          'target': 'fault',
          'target_id': '42',
        });
        final uri = Uri.parse(url!);
        expect(uri.scheme, 'corex-rental');
        expect(uri.host, 'agent');
        expect(uri.pathSegments, ['fault', '42']);
      });

      test('no target keeps the old action_url behaviour', () {
        expect(
            MessagingService.resolveAction(
                {'action_url': '/properties/3', 'target': ''}),
            '/properties/3');
      });

      test('an alert with no target and no link opens the notifications list',
          () {
        expect(
            MessagingService.resolveAction(
                {'event_key': 'rental_lease.renewed', 'test': '1'}),
            DeepLinkRouter.notificationsLink);
      });

      test('every record screen is checked for 403/404 before it opens', () {
        for (final t in ['fault', 'work_order', 'lease', 'inspection', 'job_card']) {
          expect(DeepLinkRouter.rentalProbe(open(agent, 'agent', t, 7)!),
              isNotNull,
              reason: t);
        }
        // Lists and the notifications fallback have nothing to check.
        expect(
            DeepLinkRouter.rentalProbe(
                open(agent, 'agent', 'lease_notice', 7)!),
            isNull);
      });
    });

    test('client record screens are checked before they open', () {
      for (final (side, aud) in [(tenant, 'tenant'), (owner, 'owner')]) {
        for (final t in ['fault', 'work_order', 'inspection']) {
          expect(DeepLinkRouter.rentalProbe(open(side, aud, t, 7)!), isNotNull,
              reason: '$aud $t');
        }
      }
    });

    test('a client push naming no record opens nothing', () {
      expect(
          MessagingService.resolveAction({
            'type': 'rental',
            'category': 'appointment',
            'action_url': '/somewhere',
          }),
          isNull);
    });

    test('client inspection_ready opens the report', () {
      expect(open(tenant, 'tenant', 'inspection', 9),
          isA<ClientInspectionDetailScreen>());
      expect(open(owner, 'owner', 'inspection', 9),
          isA<ClientInspectionDetailScreen>());
      expect(open(tenant, 'owner', 'inspection', 9), isNull);
      final url = MessagingService.resolveAction({
        'type': 'rental',
        'category': 'inspection_ready',
        'audience': 'tenant',
        'subject_type': 'inspection',
        'subject_id': '9',
      });
      expect(Uri.parse(url!).pathSegments, ['inspection', '9']);
    });
  });

  group('list meta', () {
    test('uses last_page when sent', () {
      final p = PagedResult.parse({
        'data': [
          {'id': 1}
        ],
        'meta': {
          'page': 1,
          'per_page': 25,
          'total': 27,
          'last_page': 2,
          'empty_reason': null
        },
      }, (m) => m);
      expect(p.lastPage, 2);
      expect(p.items.single.integer('id'), 1);
    });

    test('works out the last page when only total + per_page are sent', () {
      final p = PagedResult.parse({
        'data': const [],
        'meta': {
          'page': 1,
          'per_page': 25,
          'total': 51,
          'empty_reason': 'Nothing is waiting for you.'
        },
      }, (m) => m);
      expect(p.lastPage, 3);
      expect(p.emptyReason, 'Nothing is waiting for you.');
    });
  });

  group('queue outcomes', () {
    test('only network / 5xx / 429 / "still being sent" are retried', () {
      expect(RentalsApiException(0, 'offline').isTransient, isTrue);
      expect(RentalsApiException(503, 'down').isTransient, isTrue);
      expect(RentalsApiException(429, 'slow down').isTransient, isTrue);
      expect(
          RentalsApiException(409,
                  'That is still being sent — please wait a moment before trying again.')
              .isTransient,
          isTrue);
      // Named conflicts are rule refusals: never retried blindly.
      expect(RentalsApiException(409, 'x', code: 'items_pending').isTransient,
          isFalse);
      expect(RentalsApiException(409, 'x', code: 'key_reused').isTransient,
          isFalse);
      for (final s in [403, 404, 422]) {
        expect(RentalsApiException(s, 'no').isTransient, isFalse, reason: '$s');
      }
    });

    test('410 / code archived means drop it', () {
      expect(RentalsApiException(410, 'gone').isArchived, isTrue);
      expect(
          RentalsApiException(404, 'x', code: 'archived').isArchived, isTrue);
      expect(RentalsApiException(404, 'x').isArchived, isFalse);
    });

    test('a queued write keeps its key and intent across a restart', () {
      final item = QueuedRentalWrite(
        id: 'local-1',
        audience: RentalsAudience.staff,
        sessionKey: 'user:7',
        method: 'POST',
        path: '/mobile/rental-inspections/{ref:abc}/observations',
        multipart: false,
        fields: {'item_id': 587, 'condition': 'damaged'},
        files: const {},
        idempotencyKey: 'f8467a23-31f8-4b72-8bba-ea168c5c3309',
        sendKey: true,
        label: 'Observation',
        group: 'inspection:{ref:abc}',
        dependsOn: 'abc',
        state: QueuedWriteState.sending,
        createdAt: 1,
      );
      final back = QueuedRentalWrite.fromJson(item.toJson())!;
      expect(back.idempotencyKey, item.idempotencyKey);
      expect(back.path, item.path);
      expect(back.dependsOn, 'abc');
      expect(back.fields['item_id'], 587);
      // In-flight is never persisted: a kill mid-request comes back pending.
      expect(back.state, QueuedWriteState.pending);
    });

    test('pending counts are per signed-in person and per group', () async {
      SharedPreferences.setMockInitialValues({});
      final q = RentalWriteQueue.instance..autoDrain = false;
      q.setSession('user:1');
      await q.enqueue(
          audience: RentalsAudience.staff,
          path: '/mobile/rental-inspections/9/observations',
          label: 'a',
          group: 'inspection:9');
      await q.enqueue(
          audience: RentalsAudience.staff,
          path: '/mobile/rental-inspections/9/observations',
          label: 'b',
          group: 'inspection:9');
      expect(q.pendingCount('inspection:9'), 2);
      expect(q.pendingCount('inspection:10'), 0);

      // Someone else signs in on the phone: they never see (or send) it.
      q.setSession('user:2');
      expect(q.pendingCount('inspection:9'), 0);
      expect(q.items, isEmpty);

      q.setSession('user:1');
      expect(q.pendingCount('inspection:9'), 2);
      for (final i in List.of(q.items)) {
        await q.discard(i.id);
      }
      q.setSession(null);
    });
  });
}
