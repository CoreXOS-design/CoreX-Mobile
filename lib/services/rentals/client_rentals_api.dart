export '../../models/rentals/paged_result.dart' show Json, MapRead;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../models/rentals/paged_result.dart';
import 'rental_write_queue.dart';
import 'rentals_http.dart';


/// Tenant (lessee) and owner (lessor) rentals endpoints under
/// `/api/v1/client/rentals` (tenant) and `/client/rentals/landlord` (owner).
///
/// One login can be both; every call carries `X-Portal-Role` for its side
/// (see [RentalsAudience]). Lists here are not paginated (the server returns
/// the full array), except documents.
///
/// Every write in this group is replay-safe on the server (`portal.once`):
/// the queue's `client_idempotency_key` makes a retry answer 200
/// `duplicate: true` instead of a second record. `captured_at` is only read on
/// the tenant fault report.
///
/// Rules (Johan): no rent or payment anywhere; the tenant is shown nothing
/// about the owner. That is why the tenant `leases/{id}` (it carries rent,
/// deposit and the owner's names) and the tenant `overview` (unmasked notice
/// wording) have no method here at all: `my-lease` is the tenant's lease view.
class ClientRentalsApi {
  final RentalsAudience aud;
  ClientRentalsApi._(this.aud);

  static final tenant = ClientRentalsApi._(RentalsAudience.tenant);
  static final owner = ClientRentalsApi._(RentalsAudience.owner);

  final RentalsHttp _http = RentalsHttp.instance;
  final RentalWriteQueue _queue = RentalWriteQueue.instance;

  bool get isOwner => aud == RentalsAudience.owner;

  String get _base =>
      isOwner ? '/client/rentals/landlord' : '/client/rentals';

  Future<Json> _get(String path, [Map<String, dynamic>? q]) =>
      _http.get(aud, '$_base$path', query: q);

  Future<({String id, SubmitOutcome outcome})> _write(
    String path, {
    required String label,
    Json fields = const {},
    List<String> photos = const [],
    String method = 'POST',
    String? group,
  }) =>
      _queue.submit(
        audience: aud,
        path: '$_base$path',
        label: label,
        method: method,
        group: group,
        fields: fields,
        files: {
          for (var i = 0; i < photos.length; i++) 'photos[$i]': photos[i],
        },
        multipart: photos.isNotEmpty,
      );

  // ── Shared (both sides) ──────────────────────────────────────────────────

  /// Agency name + logo for the header. Neutral: no side gate.
  Future<Json> branding() =>
      _http.get(aud, '/client/rentals/branding');

  /// Tenant: `{waiting_count, items:[{kind:"work_check", work_order_id, ...}]}`.
  /// Owner: `{waiting_count, items:[{kind: fault_report|work_order|variation, id, ...}]}`.
  Future<Json> waiting() => _get('/waiting');

  /// Tenant `{leases:[card]}`; owner `{properties:[card + tenant_names]}`.
  Future<Json> myLease() => _get('/my-lease');

  Future<Json> pushPreferences() => _get('/push-preferences');

  Future<Json> setPushPreferences(Map<String, bool> prefs) =>
      _http.put(aud, '$_base/push-preferences', body: {'preferences': prefs});

  Future<Json> notices() => _get('/notices');

  Future<({String id, SubmitOutcome outcome})> giveNotice({
    required int leaseId,
    required String noticeDate,
    required String intendedEndDate,
    String? reason,
  }) =>
      _write('/notices',
          label: 'Notice',
          fields: {
            'lease_id': leaseId,
            'notice_date': noticeDate,
            'intended_end_date': intendedEndDate,
            if (reason != null && reason.isNotEmpty) 'reason': reason,
          });

  /// Paginated: `{documents:[...], meta:{page, pages, ...}}`.
  Future<Json> documents({int page = 1, String? q, String? type}) =>
      _get('/documents', {'page': page, 'q': q, 'type': type});

  /// Downloads a document (a token-protected stream) to a temp file.
  Future<File> downloadDocument(String url, String fileName) async {
    final dir = await getTemporaryDirectory();
    return _http.download(aud, url, dir: dir, fileName: fileName);
  }

  Future<Json> inspections() => _get('/inspections');

  /// A sent inspection, read-only: `{inspection: {…}}`. A 404 means not
  /// theirs, only a booked date, or not sent yet — never retried. Photo urls
  /// are signed and expire: fetch fresh on every open, never cache.
  Future<Json> inspection(int id) => _get('/inspections/$id');

  Future<Json> faultTypes(int propertyId) =>
      _get('/properties/$propertyId/fault-types');

  Future<Json> faultReports() => _get('/fault-reports');

  Future<Json> faultReport(int id) => _get('/fault-reports/$id');

  Future<Json> workOrders() => _get('/work-orders');

  Future<Json> workOrder(int id) => _get('/work-orders/$id');

  // ── Tenant writes ────────────────────────────────────────────────────────

  /// Works offline. [selfChecks] is sent as the JSON string the server
  /// expects (`[{"text","ticked"}]`).
  Future<({String id, SubmitOutcome outcome})> reportFault({
    required int propertyId,
    int? faultTypeId,
    bool otherType = false,
    String? title,
    String? description,
    required String resolution,
    bool urgent = false,
    List<Json> selfChecks = const [],
    List<String> photos = const [],
  }) =>
      _write('/properties/$propertyId/fault-reports',
          label: 'Fault report: ${title ?? description ?? 'Other'}',
          photos: photos,
          fields: {
            'resolution': resolution,
            if (otherType) 'other_type': true,
            if (!otherType && faultTypeId != null)
              'rental_fault_type_id': faultTypeId,
            if (title != null && title.isNotEmpty) 'title': title,
            if (description != null && description.isNotEmpty)
              'description': description,
            if (resolution == 'still_a_problem') 'urgent': urgent,
            if (selfChecks.isNotEmpty) 'self_checks': jsonEncode(selfChecks),
            'captured_at': isoWithOffset(DateTime.now()),
          });

  Future<({String id, SubmitOutcome outcome})> addToFault(int faultId,
          {String? note, List<String> photos = const []}) =>
      _write('/fault-reports/$faultId/notes',
          label: 'Note on your fault',
          group: 'fault:$faultId',
          photos: photos,
          fields: {if (note != null && note.isNotEmpty) 'note': note});

  Future<({String id, SubmitOutcome outcome})> withdrawFault(
          int faultId, String reason) =>
      _write('/fault-reports/$faultId/withdraw',
          label: 'Withdraw fault', fields: {'reason': reason});

  /// "Is it fixed?" — [fixed] false needs a note of at least 5 characters.
  Future<({String id, SubmitOutcome outcome})> completionResponse(
          int workOrderId,
          {required bool fixed,
          String? note,
          List<String> photos = const []}) =>
      _write('/work-orders/$workOrderId/completion-response',
          label: fixed ? 'Work confirmed fixed' : 'Work not fixed yet',
          photos: photos,
          fields: {
            'fixed': fixed,
            if (note != null && note.isNotEmpty) 'note': note,
          });

  /// Tenant: started | finished | not_fixed (with photos).
  /// Owner: started | finished (no photos).
  Future<({String id, SubmitOutcome outcome})> workProgress(int workOrderId,
          {required String action,
          String? note,
          List<String> photos = const []}) =>
      _write('/work-orders/$workOrderId/progress',
          label: 'Work progress: $action',
          photos: isOwner ? const [] : photos,
          fields: {
            'action': action,
            if (note != null && note.isNotEmpty) 'note': note,
          });

  // ── Owner writes ─────────────────────────────────────────────────────────

  Future<Json> properties() => _get('/properties');

  Future<Json> decisions() => _get('/decisions');

  Future<({String id, SubmitOutcome outcome})> ownerReportFault({
    required int propertyId,
    int? faultTypeId,
    String? title,
    String? description,
    String? comment,
    List<String> photos = const [],
  }) =>
      _write('/properties/$propertyId/fault-reports',
          label: 'Fault report: ${title ?? description ?? ''}',
          photos: photos,
          fields: {
            if (faultTypeId != null) 'rental_fault_type_id': faultTypeId,
            if (title != null && title.isNotEmpty) 'title': title,
            if (description != null && description.isNotEmpty)
              'description': description,
            if (comment != null && comment.isNotEmpty) 'comment': comment,
          });

  /// decision: approve | decline; handled_by: own | list | agency | proposed.
  Future<Json> faultDecision(int faultId, Json fields) =>
      _http.post(aud, '$_base/fault-reports/$faultId/decision', body: fields);

  Future<Json> faultQuery(int faultId, String note) => _http.post(
      aud, '$_base/fault-reports/$faultId/query',
      body: {'note': note});

  Future<Json> faultStop(int faultId, String reason) => _http.post(
      aud, '$_base/fault-reports/$faultId/stop',
      body: {'reason': reason});

  Future<Json> faultResume(int faultId) =>
      _http.post(aud, '$_base/fault-reports/$faultId/resume');

  Future<Json> repairRequest(int faultId, {String? comment}) => _http.post(
      aud, '$_base/fault-reports/$faultId/repair-request',
      body: {if (comment != null && comment.isNotEmpty) 'comment': comment});

  /// Echo back the quote snapshot from the GET exactly; a changed quote
  /// answers 409 and the screen must reload.
  Future<Json> workOrderDecision(int id,
          {required String decision, String? note, Json? quote}) =>
      _http.post(aud, '$_base/work-orders/$id/decision', body: {
        'decision': decision,
        if (note != null && note.isNotEmpty) 'note': note,
        if (quote != null) ...{
          'quote_id': quote['id'],
          'quote_revision': quote['revision'],
          'quote_amount': quote['amount'],
        },
      });

  Future<Json> setAppointment(int id, String appointmentAt, {String? note}) =>
      _http.post(aud, '$_base/work-orders/$id/appointment', body: {
        'appointment_at': appointmentAt,
        if (note != null && note.isNotEmpty) 'note': note,
      });

  Future<Json> variationDecision(int id,
          {required String decision, required int revision, String? note}) =>
      _http.post(aud, '$_base/variations/$id/decision', body: {
        'decision': decision,
        'revision': revision,
        if (note != null && note.isNotEmpty) 'note': note,
      });
}
