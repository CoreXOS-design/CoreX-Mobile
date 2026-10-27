export '../../models/rentals/paged_result.dart' show Json, MapRead, PagedResult;
import 'package:flutter/foundation.dart' show visibleForTesting;
import '../../models/rentals/paged_result.dart';
import 'rental_write_queue.dart';
import 'rentals_http.dart';


/// Staff rentals endpoints (AT-508 P1–P6), all under `/api/v1`.
///
/// Contract: hfc-dash `.ai/specs/at-508-P2P3-build-notes.md` and
/// `at-508-P5P6-build-notes.md`. Payloads are returned as maps and read with
/// the `MapRead` helpers: the screens display what the server sends (labels,
/// status wording, empty reasons) rather than re-deriving any of it.
///
/// Writes the contract marks queue-safe go through [RentalWriteQueue] with a
/// `client_idempotency_key` + `captured_at`; everything else is online-only
/// and called directly.
class StaffRentalsApi {
  StaffRentalsApi._();
  static final StaffRentalsApi instance = StaffRentalsApi._();

  final RentalsHttp _http = RentalsHttp.instance;
  final RentalWriteQueue _queue = RentalWriteQueue.instance;
  static const _aud = RentalsAudience.staff;

  Future<PagedResult<Json>> _list(String path, int page, Map<String, String> q) async {
    final body = await _http.get(_aud, path, query: {...q, 'page': page});
    return PagedResult.parse(body, (m) => m);
  }

  String get _now => isoWithOffset(DateTime.now());

  // ── P1: waiting + command centre ─────────────────────────────────────────

  /// `{waiting_count, by_type, data[], meta}`; 25 per page.
  Future<Json> waiting({int page = 1}) =>
      _http.get(_aud, '/mobile/rentals/waiting', query: {'page': page});

  Future<Json> commandCentre() => _http.get(_aud, '/rentals/command-centre');

  // ── P2: faults ───────────────────────────────────────────────────────────

  Future<Json> faultTypes({int? propertyId}) => _http.get(
      _aud, '/mobile/rental-fault-types',
      query: {'property_id': propertyId});

  /// sort: newest|oldest|status|property. status, urgency, date_from/to,
  /// archived=1.
  Future<PagedResult<Json>> faultReports(int page, Map<String, String> q) =>
      _list('/mobile/fault-reports', page, q);

  Future<Json> faultReport(int id) => _http.get(_aud, '/mobile/fault-reports/$id');

  /// Queue-safe. Returns the fault detail (+ `duplicate`).
  Future<({String id, SubmitOutcome outcome})> reportFault({
    required int propertyId,
    required String title,
    required String description,
    String? faultTypeId,
    int? leaseId,
    String? reportedByType,
    String? reportedChannel,
    String? label,
  }) =>
      _queue.submit(
        audience: _aud,
        path: '/mobile/properties/$propertyId/fault-reports',
        label: label ?? 'Fault report: $title',
        group: 'property:$propertyId',
        fields: {
          'title': title,
          'description': description,
          if (faultTypeId != null) 'rental_fault_type_id': faultTypeId,
          if (leaseId != null) 'lease_id': leaseId,
          if (reportedByType != null) 'reported_by_type': reportedByType,
          if (reportedChannel != null) 'reported_channel': reportedChannel,
          'captured_at': _now,
        },
      );

  /// Queue-safe. [faultRef] is the server id, or `{ref:<localId>}` of a fault
  /// report still in the queue.
  Future<({String id, SubmitOutcome outcome})> addFaultPhoto({
    required String faultRef,
    required String photoPath,
    String? dependsOn,
    String label = 'Fault photo',
  }) =>
      _queue.submit(
        audience: _aud,
        path: '/mobile/fault-reports/$faultRef/photos',
        label: label,
        group: 'fault:$faultRef',
        dependsOn: dependsOn,
        files: {'photo': photoPath},
        fields: {'captured_at': _now},
      );

  /// Online-only (one decision ever; a retry is a harmless 422).
  Future<Json> recordApproval(int faultId, Json fields) =>
      _http.post(_aud, '/mobile/fault-reports/$faultId/approval', body: fields);

  Future<Json> setOutcome(int faultId, Json fields) =>
      _http.post(_aud, '/mobile/fault-reports/$faultId/outcome', body: fields);

  // ── P2: work orders ──────────────────────────────────────────────────────

  /// sort: newest|due|status. status, date_from/to, archived=1.
  Future<PagedResult<Json>> workOrders(int page, Map<String, String> q) =>
      _list('/mobile/work-orders', page, q);

  Future<Json> workOrder(int id) => _http.get(_aud, '/mobile/work-orders/$id');

  /// Online-only — the contract gives work-order creation no idempotency key,
  /// so a blind retry would raise a second one. Never queued.
  Future<Json> createWorkOrder(int propertyId, Json fields) => _http.post(
      _aud, '/mobile/properties/$propertyId/work-orders',
      body: {...fields, 'captured_at': _now});

  /// Queue-safe. photo_type: reported|in_progress|completed.
  Future<({String id, SubmitOutcome outcome})> addWorkOrderPhoto({
    required int workOrderId,
    required String photoPath,
    required String photoType,
  }) =>
      _queue.submit(
        audience: _aud,
        path: '/mobile/work-orders/$workOrderId/photos',
        label: 'Work order WO-$workOrderId photo',
        group: 'work_order:$workOrderId',
        files: {'photo': photoPath},
        fields: {'photo_type': photoType, 'captured_at': _now},
      );

  Future<Json> assignSupplier(int id, int supplierId, {String? tradeType}) =>
      _http.post(_aud, '/mobile/work-orders/$id/assign-supplier', body: {
        'agency_service_provider_id': supplierId,
        if (tradeType != null) 'trade_type': tradeType,
      });

  Future<Json> contractorResponse(int id, String response, {String? reason}) =>
      _http.post(_aud, '/mobile/work-orders/$id/contractor-response', body: {
        'response': response,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      });

  /// Online-only; the invoice number is the natural duplicate guard.
  Future<Json> fileInvoice(int id,
          {required Map<String, dynamic> fields, required String documentPath}) =>
      _http.multipart(_aud, '/mobile/work-orders/$id/invoices',
          fields: fields, files: [RentalsFilePart('document', documentPath)]);

  Future<Json> completeWorkOrder(int id, Json fields) =>
      _http.post(_aud, '/mobile/work-orders/$id/complete', body: {
        ...fields,
        'pending_client_items': _queue.pendingCount('work_order:$id'),
      });

  // ── P3: leases + notices ─────────────────────────────────────────────────

  /// sort: end_date|start_date|property|status, direction, status,
  /// expiring_within_days, date_from/to (on the end date).
  Future<PagedResult<Json>> leases(int page, Map<String, String> q) =>
      _list('/mobile/leases', page, q);

  Future<Json> lease(int id) => _http.get(_aud, '/mobile/leases/$id');

  /// status: received (default) | accepted | rejected | withdrawn | all.
  Future<PagedResult<Json>> notices(int page, Map<String, String> q) =>
      _list('/mobile/rental-notices', page, q);

  // ── P5: inspections ──────────────────────────────────────────────────────

  Future<Json> checklist(int propertyId) => _http
      .get(_aud, '/mobile/properties/$propertyId/rental-inspection-items');

  /// sort: due|type|status, type, status, lease_id, date_from/to.
  Future<PagedResult<Json>> inspections(int page, Map<String, String> q) =>
      _list('/mobile/rental-inspections', page, q);

  /// The full resync source after a reinstall / new phone.
  Future<Json> inspection(int id) =>
      _http.get(_aud, '/mobile/rental-inspections/$id');

  /// Queue-safe. Starting a scheduled (booked) inspection is NOT this — the
  /// draft already exists; open it instead.
  Future<({String id, SubmitOutcome outcome})> startInspection({
    required int leaseId,
    required String type,
    int? plannedDateId,
    required String label,
  }) =>
      _queue.submit(
        audience: _aud,
        path: '/mobile/rental-inspections',
        label: label,
        group: 'lease:$leaseId:start',
        fields: {
          'lease_id': leaseId,
          'type': type,
          if (plannedDateId != null) 'planned_date_id': plannedDateId,
          'captured_at': _now,
        },
      );

  static String inspectionGroup(String inspectionRef) =>
      'inspection:$inspectionRef';

  /// Queue-safe. [inspectionRef] is an id or `{ref:<localId>}`.
  Future<({String id, SubmitOutcome outcome})> recordObservation({
    required String inspectionRef,
    required int itemId,
    required String condition,
    String? notes,
    required String label,
    String? dependsOn,
  }) =>
      _queue.submit(
        audience: _aud,
        path: '/mobile/rental-inspections/$inspectionRef/observations',
        label: label,
        group: inspectionGroup(inspectionRef),
        dependsOn: dependsOn,
        fields: {
          'item_id': itemId,
          'condition': condition,
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
          'captured_at': _now,
        },
      );

  /// Queue-safe. One photo filed the way the web files it: against a
  /// checklist [itemId] (the item needs no condition first — the server
  /// creates its pending observation), a [roomId] (a general photo of the
  /// room), or neither (loose, to the "Unsorted photos" tray). Never both.
  ///
  /// Call it straight after the shutter: the key and `captured_at` are minted
  /// here and resent unchanged on every retry.
  Future<({String id, SubmitOutcome outcome})> addInspectionPhoto({
    required String inspectionRef,
    required String photoPath,
    int? itemId,
    int? roomId,
    required String label,
    String? dependsOn,
  }) {
    assert(itemId == null || roomId == null, 'file to an item OR a room');
    return _queue.submit(
      audience: _aud,
      path: '/mobile/rental-inspections/$inspectionRef/photos',
      label: label,
      group: inspectionGroup(inspectionRef),
      dependsOn: dependsOn,
      files: {'photo': photoPath},
      fields: {
        if (itemId != null) 'item_id': itemId,
        if (itemId == null && roomId != null) 'room_id': roomId,
        'captured_at': _now,
      },
    );
  }

  Future<({String id, SubmitOutcome outcome})> addRoomNote({
    required String inspectionRef,
    required int roomId,
    required String note,
    required String label,
    String? dependsOn,
  }) =>
      _queue.submit(
        audience: _aud,
        path: '/mobile/rental-inspections/$inspectionRef/rooms/$roomId/notes',
        label: label,
        group: inspectionGroup(inspectionRef),
        dependsOn: dependsOn,
        fields: {'note': note, 'captured_at': _now},
      );

  /// Last write wins, no key. Online-only (a 409 once locked).
  Future<Json> setOverallNotes(int inspectionId, String? notes) => _http.post(
      _aud, '/mobile/rental-inspections/$inspectionId/overall-notes',
      body: {'overall_notes': notes});

  Future<({String id, SubmitOutcome outcome})> recordAttendance({
    required String inspectionRef,
    required Json fields,
    required String label,
    String? dependsOn,
  }) =>
      _queue.submit(
        audience: _aud,
        path: '/mobile/rental-inspections/$inspectionRef/attendance',
        label: label,
        group: inspectionGroup(inspectionRef),
        dependsOn: dependsOn,
        fields: {...fields, 'captured_at': _now},
      );

  /// Idempotent by content; online-only.
  Future<Json> resolveDiscrepancy(int inspectionId, int discrepancyId,
          {required int acceptedObservationId, String? note}) =>
      _http.post(
          _aud,
          '/mobile/rental-inspections/$inspectionId/discrepancies/'
          '$discrepancyId/resolve',
          body: {
            'accepted_observation_id': acceptedObservationId,
            if (note != null && note.isNotEmpty) 'resolution_note': note,
          });

  /// Queue-safe. `signature_image` is a base64 PNG data-URI; `wet_ink_file`
  /// goes as a file.
  Future<({String id, SubmitOutcome outcome})> recordSignature({
    required String inspectionRef,
    required Json fields,
    String? wetInkPath,
    required String label,
    String? dependsOn,
  }) =>
      _queue.submit(
        audience: _aud,
        path: '/mobile/rental-inspections/$inspectionRef/signatures',
        label: label,
        group: inspectionGroup(inspectionRef),
        dependsOn: dependsOn,
        files: {if (wetInkPath != null) 'wet_ink_file': wetInkPath},
        fields: {...fields, 'captured_at': _now},
      );

  /// Online-only. Sends what this phone still holds unsent; the server
  /// refuses with 409 `items_pending` while that is above zero.
  ///
  /// [startLocalId] is the queue id of an offline start, whose follow-up
  /// writes were grouped under `{ref:<localId>}` before the server id existed.
  Future<Json> completeInspection(int inspectionId,
      {bool acknowledgeWarnings = false, String? startLocalId}) {
    var pending = _queue.pendingCount(inspectionGroup('$inspectionId'));
    if (startLocalId != null) {
      pending += _queue.pendingCount(inspectionGroup('{ref:$startLocalId}'));
    }
    return _http.post(
        _aud, '/mobile/rental-inspections/$inspectionId/complete', body: {
      'pending_client_items': pending,
      if (acknowledgeWarnings) 'acknowledge_warnings': true,
    });
  }

  // ── P6: due list + inventories ───────────────────────────────────────────

  /// status: open (default) | all | overdue | due | upcoming | booked | done |
  /// skipped | lease_ended; type: in|out|interim; sort: due|property|type|
  /// status|overdue.
  Future<PagedResult<Json>> inspectionsDue(int page, Map<String, String> q) =>
      _list('/mobile/rental-inspections/due', page, q);

  /// sort: created|property|status.
  Future<PagedResult<Json>> inventories(int page, Map<String, String> q) =>
      _list('/mobile/rental-inventories', page, q);

  Future<Json> inventory(int id) =>
      _http.get(_aud, '/mobile/rental-inventories/$id');

  static String inventoryGroup(int inventoryId) => 'inventory:$inventoryId';

  /// The line fields both add and change take: a [description], and a room —
  /// [roomId] from the inventory's `rooms[]`, or a typed [roomLabel].
  @visibleForTesting
  static Map<String, dynamic> lineFields({
    required String description,
    int? roomId,
    String? roomLabel,
    int? quantity,
    String? conditionKey,
  }) =>
      {
        'description': description,
        if (roomId != null)
          'property_room_id': roomId
        else
          'room_label': roomLabel,
        // Blank (unknown) is sent as null so a change can clear it.
        'quantity': quantity,
        'condition_key': conditionKey,
      };

  /// Queue-safe (keyed): a typed line. A retry of the same key answers with
  /// the same line (`duplicate: true`).
  Future<({String id, SubmitOutcome outcome})> addInventoryLine({
    required int inventoryId,
    required String description,
    int? roomId,
    String? roomLabel,
    int? quantity,
    String? conditionKey,
  }) =>
      _queue.submit(
        audience: _aud,
        path: '/mobile/rental-inventories/$inventoryId/lines',
        label: 'Inventory item: $description',
        group: inventoryGroup(inventoryId),
        fields: lineFields(
            description: description,
            roomId: roomId,
            roomLabel: roomLabel,
            quantity: quantity,
            conditionKey: conditionKey),
      );

  /// Queue-safe by nature (a PUT of the whole line); the server takes no key.
  /// [lineRef] is the line id, or `{ref:<localId>}` of an add still queued.
  Future<({String id, SubmitOutcome outcome})> updateInventoryLine({
    required int inventoryId,
    required String lineRef,
    required String description,
    int? roomId,
    String? roomLabel,
    int? quantity,
    String? conditionKey,
    String? dependsOn,
  }) =>
      _queue.submit(
        audience: _aud,
        method: 'PUT',
        sendKey: false,
        path: '/mobile/rental-inventories/$inventoryId/lines/$lineRef',
        label: 'Inventory item changed: $description',
        group: inventoryGroup(inventoryId),
        dependsOn: dependsOn,
        fields: lineFields(
            description: description,
            roomId: roomId,
            roomLabel: roomLabel,
            quantity: quantity,
            conditionKey: conditionKey),
      );

  /// Queue-safe: repeating is harmless (`duplicate: true`). The line is kept
  /// on record, never deleted.
  Future<({String id, SubmitOutcome outcome})> retireInventoryLine({
    required int inventoryId,
    required String lineRef,
    required String description,
    String? dependsOn,
  }) =>
      _queue.submit(
        audience: _aud,
        sendKey: false,
        path: '/mobile/rental-inventories/$inventoryId/lines/$lineRef/retire',
        label: 'Inventory item removed: $description',
        group: inventoryGroup(inventoryId),
        dependsOn: dependsOn,
      );

  // ── Parity actions (online only) ─────────────────────────────────────────
  //
  // hfc-dash `.ai/specs/at-508-mobile-parity-addendum.md`: each is the web's
  // own action. Not queueable — they need signal and a deliberate tap. The
  // answer is shown as the server words it (see rentals_actions.dart).

  /// One web action: [method] POST / PUT / PATCH / DELETE on [path].
  Future<Json> act(String method, String path, [Json? body]) {
    switch (method) {
      case 'PUT':
        return _http.put(_aud, path, body: body);
      case 'PATCH':
        return _http.patch(_aud, path, body: body);
      case 'DELETE':
        return _http.delete(_aud, path, body: body);
      default:
        return _http.post(_aud, path, body: body);
    }
  }

  /// A web action that carries a file (scan, proof photo, signed copy).
  Future<Json> actWithFiles(String path, Json fields, Map<String, String> files) =>
      _http.multipart(_aud, path,
          fields: fields,
          files: [for (final e in files.entries) RentalsFilePart(e.key, e.value)]);

  /// The contractors to pick from (`agency_service_provider_id`).
  Future<PagedResult<Json>> suppliers(int page, Map<String, String> q) =>
      _list('/mobile/rental-suppliers', page, q);

  /// The web job-card list (rows carry no money).
  Future<PagedResult<Json>> jobCards(int page, Map<String, String> q) =>
      _list('/mobile/rental-job-cards', page, q);

  Future<Json> jobCard(int id) => _http.get(_aud, '/mobile/rental-job-cards/$id');

  /// The inspection signing-links panel.
  Future<Json> signingLinks(int inspectionId) =>
      _http.get(_aud, '/mobile/rental-inspections/$inspectionId/signing-links');

  Future<Json> signingQr(int inspectionId, int linkId) => _http.get(_aud,
      '/mobile/rental-inspections/$inspectionId/signing-links/$linkId/qr');

  Future<Json> inventoryComparison(int inventoryId) =>
      _http.get(_aud, '/mobile/rental-inventories/$inventoryId/comparison');

  Future<Json> inventoryInspectionPhotos(int inventoryId, {int? roomId}) =>
      _http.get(_aud, '/mobile/rental-inventories/$inventoryId/inspection-photos',
          query: {'property_room_id': roomId});

  Future<({String id, SubmitOutcome outcome})> addInventoryPhoto({
    required int inventoryId,
    required String photoPath,
    int? roomId,
    int? lineId,
    required String label,
  }) =>
      _queue.submit(
        audience: _aud,
        path: '/mobile/rental-inventories/$inventoryId/photos',
        label: label,
        group: inventoryGroup(inventoryId),
        files: {'photo': photoPath},
        fields: {
          if (roomId != null) 'property_room_id': roomId,
          if (lineId != null) 'rental_inventory_line_id': lineId,
          'captured_at': _now,
        },
      );
}
