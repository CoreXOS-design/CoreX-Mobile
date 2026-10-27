import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../../services/rentals/rental_write_queue.dart';
import '../../../theme.dart';
import '../../../services/rentals/rentals_cache.dart';
import '../../../services/rentals/rentals_http.dart';
import '../../../services/rentals/staff_rentals_api.dart';
import '../widgets/rentals_actions.dart';
import '../widgets/rentals_ui.dart';
import '../widgets/signature_pad.dart';
import 'staff_faults_screens.dart';
import 'staff_inspection_actions.dart';

final _api = StaffRentalsApi.instance;
final _queue = RentalWriteQueue.instance;

/// The In / Out split every inspection list starts with; `null`
/// is "All", where the full type filter (interim, routine) stays available.
const _kTypeSplit = <(String?, String)>[
  ('in', 'In'),
  ('out', 'Out'),
  (null, 'All'),
];

/// Inspections: what is due (computed by the server, the web "Due" tab) and
/// the inspections already started or booked — split In / Out.
class StaffInspectionsScreen extends StatefulWidget {
  final bool canAct;
  const StaffInspectionsScreen({super.key, required this.canAct});

  @override
  State<StaffInspectionsScreen> createState() => _StaffInspectionsScreenState();
}

class _StaffInspectionsScreenState extends State<StaffInspectionsScreen> {
  String? _type = 'in';

  @override
  Widget build(BuildContext context) {
    final type = _type;
    return DefaultTabController(
      length: 2,
      child: RentalsPage(
        title: 'Inspections',
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(spacing: 8, children: [
                  for (final (v, label) in _kTypeSplit)
                    RentalsChoiceChip(
                      label: Text(label),
                      selected: type == v,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        setState(() => _type = v);
                      },
                    ),
                ]),
              ),
            ),
            const TabBar(tabs: [Tab(text: 'Due'), Tab(text: 'Inspections')]),
            const SizedBox(height: 8),
            const RentalsQueueBanner(),
            Expanded(
              child: TabBarView(children: [
                _DueList(
                    key: ValueKey('due:$type'),
                    canAct: widget.canAct,
                    type: type),
                RentalsPagedList<Json>(
                  key: ValueKey('list:$type'),
                  searchHint: 'Address, tenant or inspector',
                  refresh: _queue.sent,
                  filters: [
                    if (type == null)
                      const ListFilter(param: 'type', label: 'Type', options: [
                        ('in', 'In'),
                        ('out', 'Out'),
                        ('interim', 'Interim'),
                        ('ad_hoc', 'Routine'),
                      ]),
                    const ListFilter(param: 'status', label: 'Status', options: [
                      ('draft', 'Draft'),
                      ('in_progress', 'In progress'),
                      ('awaiting_signature', 'Awaiting signature'),
                      ('completed', 'Completed'),
                      ('cancelled', 'Cancelled'),
                    ]),
                    const ListFilter(param: 'sort', label: 'Sort', options: [
                      ('due', 'Due date'),
                      ('type', 'Type'),
                      ('status', 'Status'),
                    ]),
                  ],
                  fetch: (page, q) => _api.inspections(
                      page, {...q, if (type != null) 'type': type}),
                  itemBuilder: (context, i) => RentalsListCard(
                    title: i.obj('property')?.str('address') ?? 'Inspection',
                    subtitle: [i.str('type_label'), i.str('tenant_names')]
                        .whereType<String>()
                        .join(' · '),
                    meta: [
                      fmtDate(i.str('due_date') ?? i.str('scheduled_for')),
                      i.str('scheduled_time'),
                      i.obj('inspector')?.str('name'),
                    ].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
                    statusLabel: i.str('status_label'),
                    statusKey: i.str('status'),
                    badges: [
                      if (i.flag('has_unresolved_discrepancy'))
                        const RentalsStatusChip('Difference to resolve',
                            statusKey: 'review'),
                    ],
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => StaffInspectionScreen(
                        inspectionId: i.integer('id'),
                        propertyId: i.obj('property')?.integer('id') ?? 0,
                        title: i.obj('property')?.str('address') ?? 'Inspection',
                      ),
                    )),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _DueList extends StatelessWidget {
  final bool canAct;

  /// Fixed `type` from the In / Out split; null offers the filter.
  final String? type;
  const _DueList({super.key, required this.canAct, this.type});

  @override
  Widget build(BuildContext context) {
    return RentalsPagedList<Json>(
      searchHint: 'Address, tenant, agent or note',
      refresh: _queue.sent,
      filters: [
        const ListFilter(param: 'status', label: 'Show', options: [
          ('open', 'Open'),
          ('overdue', 'Overdue'),
          ('due', 'Due'),
          ('upcoming', 'Upcoming'),
          ('booked', 'Booked'),
          ('done', 'Done'),
          ('all', 'All'),
        ]),
        if (type == null)
          const ListFilter(param: 'type', label: 'Type', options: [
            ('in', 'Move-in'),
            ('out', 'Move-out'),
            ('interim', 'Interim'),
          ]),
        const ListFilter(param: 'sort', label: 'Sort', options: [
          ('due', 'Due date'),
          ('overdue', 'Most overdue'),
          ('property', 'Property'),
          ('type', 'Type'),
        ]),
      ],
      fetch: (page, q) =>
          _api.inspectionsDue(page, {...q, if (type != null) 'type': type!}),
      itemBuilder: (context, d) => RentalsListCard(
        title: d.obj('property')?.str('address') ?? 'Inspection',
        subtitle: [d.str('type_label'), d.str('tenant_names')]
            .whereType<String>()
            .join(' · '),
        meta: [
          'Due ${fmtDate(d.str('due_on'))}',
          if ((d.integer('days_overdue') ?? 0) > 0)
            '${d.integer('days_overdue')} days overdue',
        ].join(' · '),
        statusLabel: d.str('state_label'),
        statusKey: d.str('state'),
        highlight: d.str('state') == 'overdue',
        onTap: () => _open(context, d),
      ),
    );
  }

  Future<void> _open(BuildContext context, Json d) async {
    final propertyId = d.obj('property')?.integer('id') ?? 0;
    final title = d.obj('property')?.str('address') ?? 'Inspection';
    final existing = d.integer('inspection_id');
    if (existing != null) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => StaffInspectionScreen(
              inspectionId: existing, propertyId: propertyId, title: title)));
      return;
    }
    final reason = d.str('reason');
    if (!canAct) {
      if (reason != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(reason)));
      }
      return;
    }
    final leaseId = d.integer('lease_id');
    final type = d.str('type');
    if (leaseId == null || type == null) return;
    final how = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(title), subtitle: reason == null ? null : Text(reason)),
          ListTile(
              leading: const Icon(TablerIcons.player_play),
              title: const Text('Start now'),
              onTap: () => Navigator.pop(ctx, 'start')),
          ListTile(
              leading: const Icon(TablerIcons.calendar_plus),
              title: const Text('Schedule'),
              onTap: () => Navigator.pop(ctx, 'schedule')),
          if (d.str('source') == 'planned' && d.integer('planned_date_id') != null)
            ListTile(
                leading: const Icon(TablerIcons.calendar_event),
                title: const Text('Manage this date'),
                onTap: () => Navigator.pop(ctx, 'planned')),
        ]),
      ),
    );
    if (how == null || !context.mounted) return;
    if (how == 'schedule') {
      await scheduleInspection(context,
          leaseId: leaseId, type: type, plannedDateId: d.integer('planned_date_id'));
      return;
    }
    if (how == 'planned') {
      await plannedDateActions(context, d);
      return;
    }
    await startInspectionAndOpen(
      context,
      leaseId: leaseId,
      type: type,
      typeLabel: d.str('type_label'),
      propertyId: propertyId,
      title: title,
      reason: reason,
      plannedDateId: d.integer('planned_date_id'),
    );
  }
}

/// Confirms, starts (queued when offline) and opens an inspection of [type]
/// on a lease. Shared by the Due list and the lease file's "Start Out
/// Inspection".
Future<void> startInspectionAndOpen(
  BuildContext context, {
  required int leaseId,
  required String type,
  String? typeLabel,
  required int propertyId,
  required String title,
  String? reason,
  int? plannedDateId,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dlg) => AlertDialog(
      title: Text('Start the ${typeLabel ?? ''} inspection?'),
      content: Text([title, if (reason != null) reason].join('\n\n')),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dlg, false),
            child: const Text('Not now')),
        TextButton(
            onPressed: () => Navigator.pop(dlg, true),
            child: const Text('Start')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  // Cache the checklist while there may still be signal, so an offline
  // start has something to walk through.
  final session = _queue.sessionKey;
  try {
    final c = await _api.checklist(propertyId);
    await RentalsCache.write(session, 'checklist:$propertyId', c);
  } catch (_) {}

  final r = await _api.startInspection(
    leaseId: leaseId,
    type: type,
    plannedDateId: plannedDateId,
    label: '${typeLabel ?? 'Inspection'} at $title',
  );
  if (!context.mounted) return;
  switch (r.outcome) {
    case SubmitSent(:final body):
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => StaffInspectionScreen(
              inspectionId: body.integer('id'),
              propertyId: propertyId,
              title: title,
              initialDetail: body)));
    case SubmitQueued():
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => StaffInspectionScreen(
              startLocalId: r.id, propertyId: propertyId, title: title)));
    default:
      showSubmitOutcome(context, r.outcome);
  }
}

/// The walkthrough. Works without signal once it has been opened (or its
/// checklist cached): every observation, photo, note, attendance mark and
/// signature is queued with its own key and capture time, and shown here as
/// "waiting to send" until the server has it.
class StaffInspectionScreen extends StatefulWidget {
  final int? inspectionId;

  /// Queue id of an inspection started offline, until the server answers.
  final String? startLocalId;
  final int propertyId;
  final String title;
  final Json? initialDetail;

  const StaffInspectionScreen({
    super.key,
    this.inspectionId,
    this.startLocalId,
    required this.propertyId,
    required this.title,
    this.initialDetail,
  }) : assert(inspectionId != null || startLocalId != null);

  @override
  State<StaffInspectionScreen> createState() => _StaffInspectionScreenState();
}

class _StaffInspectionScreenState extends State<StaffInspectionScreen> {
  int? _id;
  Json? _detail;
  Json? _checklist;
  bool _loading = true;
  bool _offline = false;
  Object? _error;

  String get _ref => _id != null ? '$_id' : '{ref:${widget.startLocalId}}';
  String? get _dependsOn => _id == null ? widget.startLocalId : null;
  String? get _session => _queue.sessionKey;

  @override
  void initState() {
    super.initState();
    _id = widget.inspectionId;
    _detail = widget.initialDetail;
    _queue.addListener(_onQueue);
    _queue.sent.addListener(_onSent);
    _load();
  }

  @override
  void dispose() {
    _queue.removeListener(_onQueue);
    _queue.sent.removeListener(_onSent);
    super.dispose();
  }

  void _onQueue() {
    if (mounted) setState(() {});
  }

  void _onSent() {
    if (_id == null && widget.startLocalId != null) {
      final resolved = _queue.resultFor(widget.startLocalId!);
      if (resolved != null) _id = resolved;
    }
    // Pull the server's view once the queue for this inspection drains.
    if (_id != null && _pendingItems().isEmpty) _load(quiet: true);
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = _detail == null);
    if (_id == null && widget.startLocalId != null) {
      _id = _queue.resultFor(widget.startLocalId!);
    }
    try {
      if (_id != null) {
        final d = await _api.inspection(_id!);
        await RentalsCache.write(
            _session, 'inspection:$_id', withoutPhotoUrls(d));
        _detail = d;
        _checklist = d.obj('checklist');
      } else {
        final c = await _api.checklist(widget.propertyId);
        await RentalsCache.write(_session, 'checklist:${widget.propertyId}', c);
        _checklist = c;
      }
      _offline = false;
      _error = null;
    } on RentalsApiException catch (e) {
      if (e.isArchived) {
        _error = e;
      } else {
        final cached = _id != null
            ? await RentalsCache.read(_session, 'inspection:$_id')
            : await RentalsCache.read(_session, 'checklist:${widget.propertyId}');
        if (cached != null) {
          if (_id != null) {
            _detail = cached;
            _checklist = cached.obj('checklist');
          } else {
            _checklist = cached;
          }
          _offline = true;
        } else if (_detail == null) {
          _error = e;
        }
      }
    }
    _checklist ??= _detail?.obj('checklist');
    if (mounted) setState(() => _loading = false);
  }

  Json get _vocab => _detail ?? _checklist ?? const {};

  List<Json> get _conditions => _vocab.objs('condition_states');

  List<QueuedRentalWrite> _pendingItems() => [
        ..._queue.itemsIn(StaffRentalsApi.inspectionGroup(_ref)),
        if (widget.startLocalId != null && _id != null)
          ..._queue.itemsIn(StaffRentalsApi.inspectionGroup(
              '{ref:${widget.startLocalId}}')),
      ];

  /// item id → condition key of an observation still on this phone.
  Map<int, String> get _pendingByItem {
    final out = <int, String>{};
    for (final q in _pendingItems()) {
      if (!q.path.endsWith('/observations')) continue;
      final item = q.fields['item_id'];
      final cond = q.fields['condition'];
      if (item is int && cond is String) out[item] = cond;
    }
    return out;
  }

  Json? _observation(int? id) {
    if (id == null) return null;
    for (final o in _detail?.objs('observations') ?? const <Json>[]) {
      if (o.integer('id') == id) return o;
    }
    return null;
  }

  String _conditionLabel(String? key) => conditionLabel(_conditions, key);

  bool get _locked =>
      _detail != null &&
      (_detail!.flag('signed_locked') || _detail!['is_recordable'] == false);

  bool get _closed =>
      _detail?.str('status') == 'completed' ||
      _detail?.str('status') == 'cancelled';

  /// New photos are refused (409) once the report is locked or closed.
  bool get _canPhotograph => !_locked && !_closed;

  // ── photos ───────────────────────────────────────────────────────────────

  /// One expired-link re-fetch per open / manual refresh, never a loop.
  bool _photoRefetchUsed = false;

  void _onPhotoError() {
    if (_photoRefetchUsed || _offline || _id == null || !mounted) return;
    _photoRefetchUsed = true;
    _load(quiet: true);
  }

  Future<void> _refresh() {
    _photoRefetchUsed = false;
    return _load();
  }

  /// Placed from the detail's `photos[]` — every live photo, the web's too —
  /// never from observations: on its checklist item, else under its room (a
  /// general photo of the room), else the "Unsorted photos" tray.
  PhotoPlaces _placePhotos(Set<int> itemIds, Set<int> roomIds) {
    final places = placeInspectionPhotos(
        _detail?.objs('photos') ?? const <Json>[], itemIds, roomIds);
    // Photos still on this phone, where they were filed.
    for (final q in _pendingItems()) {
      if (!q.path.endsWith('/photos') || q.path.contains('/observations/')) {
        continue;
      }
      final file = q.files['photo'];
      if (file == null) continue;
      final item = q.fields['item_id'];
      final room = q.fields['room_id'];
      if (item is int && itemIds.contains(item)) {
        places.pendingByItem.putIfAbsent(item, () => []).add(file);
      } else if (room is int && roomIds.contains(room)) {
        places.pendingByRoom.putIfAbsent(room, () => []).add(file);
      } else {
        places.pendingTray.add(file);
      }
    }
    return places;
  }

  Widget _photoGrid(List<Json> photos, List<String> pendingFiles) {
    final shown = photos.where((p) => p.str('url') != null).toList();
    return RentalsPhotoGrid(
      [for (final p in shown) p.str('url')!],
      captions: [for (final p in shown) _photoCaption(p)],
      pendingFiles: pendingFiles,
      onLoadError: _onPhotoError,
      emptyText: null,
    );
  }

  static String _photoCaption(Json p) => [
        if (p.str('taken_at') != null) 'Taken ${fmtMoment(p.str('taken_at'))}',
        if (p.flag('added_after_signing')) 'added after signing',
      ].join(' · ');

  Future<void> _takePhoto(BuildContext context,
      {int? itemId, int? roomId, required String where}) async {
    final f = await PhotoPickerRow.takeOne(context);
    if (f == null || !context.mounted) return;
    final r = await _api.addInspectionPhoto(
      inspectionRef: _ref,
      photoPath: f.path,
      itemId: itemId,
      roomId: roomId,
      label: 'Photo: $where',
      dependsOn: _dependsOn,
    );
    if (!context.mounted) return;
    final out = r.outcome;
    if (out is SubmitSent && out.body.str('message') != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(out.body.str('message')!)));
    } else {
      showSubmitOutcome(context, out, sentText: 'Photo added.');
    }
    // The detail is the source of truth: re-read it so this photo and any
    // added on the web meanwhile show together.
    if (out is SubmitSent) unawaited(_load(quiet: true));
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return RentalsPage(
      title: widget.title,
      subtitle: d == null
          ? (_id == null ? 'Starting… waiting for signal' : null)
          : [d.str('type_label'), d.str('status_label')]
              .whereType<String>()
              .join(' · '),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(TablerIcons.refresh),
          onPressed: _refresh,
        ),
      ],
      body: _loading
          ? const RentalsLoading()
          : _error != null && _checklist == null
              ? RentalsError(error: _error!, onRetry: _refresh)
              : RefreshIndicator(onRefresh: _refresh, child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final d = _detail;
    final checklist = _checklist ?? const <String, dynamic>{};
    final rooms = checklist.objs('rooms');
    final meters = checklist.objs('meters');
    final others = checklist.objs('other_items');
    final pending = _pendingByItem;
    final readiness = d?.obj('readiness');
    final places = _placePhotos(
      {
        for (final i in [
          for (final r in rooms) ...r.objs('items'),
          ...meters,
          ...others,
        ])
          if (i.integer('id') != null && !i.flag('is_retired')) i.integer('id')!,
      },
      {for (final r in rooms) if (r.integer('id') != null) r.integer('id')!},
    );

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 40),
      children: [
        RentalsQueueBanner(group: StaffRentalsApi.inspectionGroup(_ref)),
        if (_offline)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: RentalsAlert(
                'Offline — showing what this phone last saw. Keep recording; '
                'it all sends when there is signal.'),
          ),
        if (checklist.obj('meta')?.str('empty_reason') != null ||
            (d != null && rooms.isEmpty && meters.isEmpty && others.isEmpty)) ...[
          if (checklist.obj('meta')?.str('empty_reason') != null)
            RentalsEmpty(reason: checklist.obj('meta')!.str('empty_reason')),
          if (!_closed && !_locked)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: ServerActionButton(
                icon: TablerIcons.layout_list,
                label: 'Build rooms from the standard checklist',
                onPressed: () async {
                  if (await seedStandardChecklist(context, widget.propertyId)) {
                    _load(quiet: true);
                  }
                },
              ),
            ),
        ],
        if (readiness?.str('message') != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: RentalsAlert(readiness!.str('message')!,
                tone: RentalsAlertTone.warning),
          ),
        if (_locked)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: RentalsAlert(
                'Someone has signed, so the report is locked. Evidence captured '
                'before the lock still sends and is marked "added after signing".'),
          ),
        if (d != null) _headerSection(context, d),
        for (final room in rooms)
          _roomSection(context, room, room.objs('items'), pending, places),
        if (meters.isNotEmpty)
          _roomSection(context, {'label': 'Meters'}, meters, pending, places),
        if (others.isNotEmpty)
          _roomSection(context, {'label': 'Other'}, others, pending, places),
        if (places.tray.isNotEmpty ||
            places.pendingTray.isNotEmpty ||
            _canPhotograph)
          RentalsSection(
            title: 'Unsorted photos',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_canPhotograph)
                RentalsSectionAction(
                  icon: TablerIcons.camera_plus,
                  tooltip: 'Add an unsorted photo',
                  onPressed: () => _takePhoto(context, where: 'unsorted'),
                ),
              if (_canPhotograph && _id != null && d != null &&
                  d.objs('photos').any((p) => !p.flag('archived')))
                RentalsSectionAction(
                  icon: TablerIcons.arrows_sort,
                  tooltip: 'Sort photos',
                  onPressed: () => _sortPhotos(context),
                ),
            ]),
            child: places.tray.isEmpty && places.pendingTray.isEmpty
                ? const BodyText(
                    'Photos not yet filed to a room or item land here.',
                    muted: true)
                : _photoGrid(places.tray, places.pendingTray),
          ),
        if (d != null) ..._afterChecklist(context, d),
        if (d == null && _id == null)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: RentalsAlert(
                'The start is waiting for signal. You can record observations '
                'now; attendance, signatures and completing need the server.'),
          ),
      ],
    );
  }

  /// The report's header block as the server holds it (meters, keys,
  /// remotes, furnished, property type, move-in date on an Out).
  Widget _headerSection(BuildContext context, Json d) {
    final h = d.obj('header') ?? const {};
    String? count(String countKey, String noteKey) => [
          h.integer(countKey)?.toString() ?? h.str(countKey),
          h.str(noteKey),
        ].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
    return RentalsSection(
      title: 'Details',
      trailing: _id == null || _closed || _locked
          ? null
          : RentalsSectionAction(
              icon: TablerIcons.pencil,
              tooltip: 'Edit details',
              onPressed: () async {
                if (await editInspectionDetails(context, d)) _load(quiet: true);
              },
            ),
      child: Column(children: [
        KeyValueRow('Electricity meter', h.str('electricity_meter_reading')),
        KeyValueRow('Water meter', h.str('water_meter_reading')),
        KeyValueRow('Furnished', displayValue(h.str('furnished_status'))),
        KeyValueRow('Property type', displayValue(h.str('property_type'))),
        KeyValueRow('Keys', count('keys_count', 'keys_description')),
        KeyValueRow('Remotes', count('remotes_count', 'remotes_description')),
        KeyValueRow('Move-in date', fmtDate(h.str('move_in_date_recorded'))),
        if (h.values.every((v) => v == null))
          const BodyText('Nothing recorded yet.', muted: true),
      ]),
    );
  }

  Widget _roomSection(BuildContext context, Json room, List<Json> items,
      Map<int, String> pending, PhotoPlaces places) {
    final roomId = room.integer('id');
    final roomLabel = room.str('label') ?? '';
    final notes = (_detail?.objs('room_notes') ?? const <Json>[])
        .where((n) => n.integer('room_id') == roomId)
        .toList();
    final roomPhotos = places.byRoom[roomId] ?? const <Json>[];
    final roomPending = places.pendingByRoom[roomId] ?? const <String>[];
    return RentalsSection(
      title: room.str('label') ?? 'Room',
      trailing: roomId == null
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: [
              if (_canPhotograph)
                RentalsSectionAction(
                  icon: TablerIcons.camera_plus,
                  tooltip: 'Photo of $roomLabel',
                  onPressed: () =>
                      _takePhoto(context, roomId: roomId, where: roomLabel),
                ),
              RentalsSectionAction(
                icon: TablerIcons.note,
                tooltip: 'Note for $roomLabel',
                onPressed: () => _addRoomNote(context, roomId, roomLabel),
              ),
              // Room N/A, All good, add an item: online only, the server's.
              if (_id != null && !_closed && !_locked && _detail != null)
                RentalsSectionAction(
                  icon: TablerIcons.dots,
                  tooltip: 'More for $roomLabel',
                  onPressed: () async {
                    if (await roomActions(context, _detail!, room)) {
                      _load(quiet: true);
                    }
                  },
                ),
            ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items.where((i) => !i.flag('is_retired')))
            _itemRow(context, room, item, pending, places),
          if (roomPhotos.isNotEmpty || roomPending.isNotEmpty) ...[
            const Divider(height: 20),
            const RentalsSubLabel('Room photos'),
            _photoGrid(roomPhotos, roomPending),
          ],
          if (notes.isNotEmpty) ...[
            const Divider(height: 20),
            const RentalsSubLabel('Note'),
            BodyText(notes.last.str('note') ?? ''),
          ],
        ],
      ),
    );
  }

  Widget _itemRow(BuildContext context, Json room, Json item,
      Map<int, String> pending, PhotoPlaces places) {
    final id = item.integer('id')!;
    final local = pending[id];
    final latest = _observation(item.integer('latest_observation_id'));
    final cond = local ?? latest?.str('condition');
    final photos = places.byItem[id] ?? const <Json>[];
    final photosPending = places.pendingByItem[id] ?? const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => _observe(context, room, item, latest),
          // Raise a fault report from it, rename, retire: online only.
          onLongPress: _id == null || _detail == null
              ? null
              : () async {
                  if (await itemActions(context, _detail!, item, latest)) {
                    _load(quiet: true);
                  }
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  cond == null ? TablerIcons.circle : TablerIcons.circle_check,
                  size: 18,
                  color: cond == null ? null : conditionColor(_conditions, cond),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(item.str('label') ?? 'Item',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPrimary(context))),
                ),
                if (cond != null)
                  RentalsStatusChip(
                      local != null
                          ? '${_conditionLabel(cond)} · waiting'
                          : _conditionLabel(cond),
                      color: conditionColor(_conditions, cond)),
                if (latest?.str('discrepancy_id') != null)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(TablerIcons.alert_triangle,
                        size: 16, color: Color(0xFFF59E0B)),
                  ),
                if (_canPhotograph)
                  IconButton(
                    tooltip: 'Photo of this item',
                    icon: Icon(TablerIcons.camera_plus,
                        size: 18, color: AppTheme.textSecondary(context)),
                    onPressed: () => _takePhoto(context,
                        itemId: id,
                        where: '${room.str('label') ?? ''} · '
                            '${item.str('label') ?? ''}'),
                  )
                else
                  const SizedBox(height: 40),
              ],
            ),
          ),
        ),
        if (photos.isNotEmpty || photosPending.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 28, bottom: 8),
            child: _photoGrid(photos, photosPending),
          ),
      ],
    );
  }

  List<Widget> _afterChecklist(BuildContext context, Json d) {
    final discrepancies =
        d.objs('discrepancies').where((x) => !x.flag('resolved')).toList();
    final attendance = d.obj('attendance');
    final board = attendance?.obj('board');
    final signatures = d.obj('signatures');
    final closed = d.str('status') == 'completed' || d.str('status') == 'cancelled';
    return [
      if (discrepancies.isNotEmpty)
        RentalsSection(
          title: 'Differences to resolve',
          child: Column(children: [
            for (final x in discrepancies)
              RentalsNavRow(
                icon: TablerIcons.alert_triangle,
                title: _itemLabel(x.integer('item_id')),
                subtitle:
                    '${(x['observation_ids'] as List? ?? const []).length} records differ',
                onTap: _id == null ? null : () => _resolve(context, x),
              ),
          ]),
        ),
      if (attendance != null && attendance.flag('required') && board != null)
        RentalsSection(
          title:
              'Attendance (${board.integer('recorded') ?? 0}/${board.integer('expected') ?? 0})',
          trailing: closed || _id == null
              ? null
              : RentalsSectionAction(
                  icon: TablerIcons.mail_forward,
                  tooltip: 'Record an invitation given',
                  onPressed: () async {
                    if (await recordInvitation(context, _id!, board.objs('rows'))) {
                      _load(quiet: true);
                    }
                  },
                ),
          child: Column(children: [
            for (final row in board.objs('rows'))
              RentalsNavRow(
                icon: TablerIcons.user_check,
                title: row.str('name') ?? displayValue(row.str('party_role')),
                subtitle: [
                  displayValue(row.str('party_role')),
                  _attendanceText(row),
                ].where((e) => e.isNotEmpty).join(' · '),
                onTap: closed ? null : () => _attendance(context, row),
              ),
          ]),
        ),
      if (signatures != null && signatures.flag('required'))
        RentalsSection(
          title: 'Signatures',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final s in signatures.objs('entries')
                  .where((e) => !e.flag('superseded')))
                KeyValueRow(
                  displayValue(s.str('party_role')),
                  displayValue(s.str('disposition')),
                  // A paper scan that came out badly can be replaced.
                  icon: s.str('disposition') == 'wet_ink' && !closed
                      ? TablerIcons.replace
                      : null,
                  onTap: s.str('disposition') == 'wet_ink' && !closed && _id != null
                      ? () async {
                          if (await supersedeWetInk(context, _id!, s.integer('id')!)) {
                            _load(quiet: true);
                          }
                        }
                      : null,
                ),
              for (final o in signatures.objs('outstanding'))
                RentalsNavRow(
                  icon: TablerIcons.signature,
                  title: o.str('name') ?? displayValue(o.str('party_role')),
                  subtitle:
                      '${displayValue(o.str('party_role'))} · Outstanding',
                  onTap: closed ? null : () => _partySignature(context, o),
                ),
              // The agent signs last: offered only once the server lists no
              // one else as outstanding and no paper signature is awaited.
              // The agent is never offered a refusal.
              if (!signatures.flag('agent_signed') &&
                  signatures.objs('outstanding').isEmpty &&
                  !signatures.objs('entries').any((e) =>
                      !e.flag('superseded') &&
                      e.str('disposition') == 'awaiting_wet_ink') &&
                  !closed)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    style:
                        OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    icon: const Icon(TablerIcons.signature, size: 18),
                    label: const Text('Sign as the agent (last)'),
                    onPressed: () => _agentSignature(context),
                  ),
                ),
            ],
          ),
        ),
      RentalsSection(
        title: 'Overall notes',
        trailing: closed || _id == null
            ? null
            : RentalsSectionAction(
                icon: TablerIcons.pencil,
                tooltip: 'Edit overall notes',
                onPressed: () => _overallNotes(context, d.str('overall_notes')),
              ),
        child: BodyText(d.str('overall_notes') ?? 'None.',
            muted: d.str('overall_notes') == null),
      ),
      if (!closed && _id != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: ElevatedButton.icon(
            icon: const Icon(TablerIcons.circle_check),
            label: Text(_pendingItems().isEmpty
                ? 'Complete inspection'
                : 'Complete (${_pendingItems().length} still sending)'),
            onPressed: () => _complete(context),
          ),
        ),
      if (_id != null)
        RentalsActionsSection(
          actions: inspectionActionButtons(
            context,
            d,
            reload: () => _load(quiet: true),
            onArchived: () {
              if (mounted) Navigator.of(context).pop();
            },
          ),
        ),
    ];
  }

  /// Every live photo, to file under a room / item, unfile or archive.
  Future<void> _sortPhotos(BuildContext context) async {
    final d = _detail;
    if (d == null) return;
    final photos =
        d.objs('photos').where((p) => !p.flag('archived') && p.str('url') != null).toList();
    final picked = await showModalBottomSheet<Json>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Which photo?')),
          for (final p in photos)
            ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(p.str('url')!,
                    width: 48, height: 48, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(TablerIcons.photo_off)),
              ),
              title: Text(_photoPlace(p)),
              subtitle: Text(_photoCaption(p)),
              onTap: () => Navigator.pop(ctx, p),
            ),
        ]),
      ),
    );
    if (picked == null || !context.mounted) return;
    if (await photoActions(context, d, picked)) _load(quiet: true);
  }

  String _photoPlace(Json p) {
    final rooms = _checklist?.objs('rooms') ?? const <Json>[];
    for (final r in rooms) {
      for (final i in r.objs('items')) {
        if (i.integer('id') == p.integer('item_id')) {
          return '${r.str('label') ?? ''} · ${i.str('label') ?? ''}';
        }
      }
      if (r.integer('id') == p.integer('room_id')) return r.str('label') ?? 'Room';
    }
    return 'Unsorted';
  }

  String _itemLabel(int? itemId) {
    for (final o in _detail?.objs('observations') ?? const <Json>[]) {
      if (o.integer('item_id') == itemId) return o.str('item_label') ?? 'Item';
    }
    return 'Item';
  }

  String _attendanceText(Json row) {
    final a = row['attendance'];
    if (a is Map) {
      return (a['outcome'] ?? a['label'] ?? 'Recorded').toString();
    }
    if (a is String && a.isNotEmpty) return a;
    final pending = _pendingItems().any((q) =>
        q.path.endsWith('/attendance') &&
        q.fields['party_role'] == row['party_role'] &&
        (q.fields['party_contact_id'] == row['contact_id'] ||
            q.fields['party_user_id'] == row['user_id']));
    return pending ? 'Waiting to send' : 'Not recorded';
  }

  // ── actions ──────────────────────────────────────────────────────────────

  Future<void> _observe(
      BuildContext context, Json room, Json item, Json? latest) async {
    if (_conditions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('The condition list has not loaded yet. '
              'Open this inspection once with signal.')));
      return;
    }
    final result = await showModalBottomSheet<_ObservationInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ObservationSheet(
        title: '${room.str('label') ?? ''} · ${item.str('label') ?? ''}',
        conditions: _conditions,
        latest: latest,
      ),
    );
    if (result == null || !context.mounted) return;
    final label = '${room.str('label') ?? ''} · ${item.str('label') ?? ''}';
    final r = await _api.recordObservation(
      inspectionRef: _ref,
      itemId: item.integer('id')!,
      condition: result.condition,
      notes: result.notes,
      label: 'Observation: $label',
      dependsOn: _dependsOn,
    );
    if (r.outcome is! SubmitRefused && r.outcome is! SubmitArchived) {
      // Filed against the item (the endpoint the web uses), so they show on
      // it however the observation itself fares.
      for (var i = 0; i < result.photos.length; i++) {
        await _api.addInspectionPhoto(
          inspectionRef: _ref,
          itemId: item.integer('id')!,
          photoPath: result.photos[i].path,
          label: 'Photo ${i + 1}: $label',
          dependsOn: _dependsOn,
        );
      }
    }
    if (!context.mounted) return;
    final out = r.outcome;
    if (out is SubmitSent && out.body.str('discrepancy_id') != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Recorded. This differs from another person\'s '
              'record of the item — resolve it before completing.')));
    } else if (out is SubmitSent && out.body.str('message') != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(out.body.str('message')!)));
    } else {
      showSubmitOutcome(context, out, sentText: 'Recorded.');
    }
    if (out is SubmitSent) unawaited(_load(quiet: true));
  }

  Future<void> _addRoomNote(BuildContext context, int roomId, String room) async {
    final text = await _prompt(context, 'Note for $room', maxLength: 4000);
    if (text == null || text.isEmpty || !context.mounted) return;
    final r = await _api.addRoomNote(
        inspectionRef: _ref,
        roomId: roomId,
        note: text,
        label: 'Note: $room',
        dependsOn: _dependsOn);
    if (!context.mounted) return;
    showSubmitOutcome(context, r.outcome, sentText: 'Note saved.');
    if (r.outcome is SubmitSent) unawaited(_load(quiet: true));
  }

  Future<void> _overallNotes(BuildContext context, String? current) async {
    final text = await _prompt(context, 'Overall notes',
        initial: current, maxLength: 4000);
    if (text == null || !context.mounted) return;
    final res = await runAction(
        context, () => _api.setOverallNotes(_id!, text.isEmpty ? null : text),
        successText: 'Saved.');
    if (res != null) unawaited(_load(quiet: true));
  }

  Future<void> _resolve(BuildContext context, Json x) async {
    final ids = (x['observation_ids'] as List? ?? const [])
        .whereType<num>()
        .map((e) => e.toInt())
        .toList();
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Which record is right?')),
          for (final id in ids)
            Builder(builder: (_) {
              final o = _observation(id);
              return ListTile(
                title: Text(_conditionLabel(o?.str('condition'))),
                subtitle: Text([o?.str('notes'), fmtMoment(o?.str('captured_at'))]
                    .whereType<String>()
                    .where((e) => e.isNotEmpty)
                    .join(' · ')),
                onTap: () => Navigator.pop(ctx, id),
              );
            }),
        ]),
      ),
    );
    if (picked == null || !context.mounted) return;
    final res = await runAction(
        context,
        () => _api.resolveDiscrepancy(_id!, x.integer('id')!,
            acceptedObservationId: picked),
        successText: 'Difference resolved.');
    if (res != null) unawaited(_load(quiet: true));
  }

  Future<void> _attendance(BuildContext context, Json row) async {
    final fields = await showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AttendanceSheet(row: row),
    );
    if (fields == null || !context.mounted) return;
    final r = await _api.recordAttendance(
        inspectionRef: _ref,
        fields: fields,
        label: 'Attendance: ${row.str('name') ?? row.str('party_role')}',
        dependsOn: _dependsOn);
    if (!context.mounted) return;
    showSubmitOutcome(context, r.outcome, sentText: 'Attendance recorded.');
    if (r.outcome is SubmitSent) unawaited(_load(quiet: true));
  }

  Future<void> _partySignature(BuildContext context, Json party) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              title: Text('${party.str('name') ?? ''} signs now'),
              leading: const Icon(TablerIcons.signature),
              onTap: () => Navigator.pop(ctx, 'signed')),
          ListTile(
              title: const Text('Refused to sign'),
              leading: const Icon(TablerIcons.ban),
              onTap: () => Navigator.pop(ctx, 'refused')),
          ListTile(
              title: const Text('Will sign on paper'),
              leading: const Icon(TablerIcons.file),
              onTap: () => Navigator.pop(ctx, 'awaiting_wet_ink')),
          ListTile(
              title: const Text('Signed on paper (photograph it)'),
              leading: const Icon(TablerIcons.camera),
              onTap: () => Navigator.pop(ctx, 'wet_ink')),
        ]),
      ),
    );
    if (choice == null || !context.mounted) return;
    final fields = <String, dynamic>{
      'party_role': party.str('party_role'),
      'party_contact_id': party.integer('party_contact_id'),
      'disposition': choice,
    };
    String? wetInk;
    if (choice == 'signed') {
      final png =
          await SignaturePadScreen.capture(context, party.str('name') ?? 'Sign');
      if (png == null) return;
      fields['signature_image'] = png;
    } else if (choice == 'refused') {
      if (!context.mounted) return;
      final refusal = await _pickRefusal(context);
      if (refusal == null) return;
      fields['refusal_reason_preset'] = refusal.$1;
      if (refusal.$2.isNotEmpty) fields['refusal_reason_note'] = refusal.$2;
    } else if (choice == 'wet_ink') {
      if (!context.mounted) return;
      final f = await PhotoPickerRow.takeOne(context);
      if (f == null) return;
      wetInk = f.path;
    }
    if (!context.mounted) return;
    final r = await _api.recordSignature(
        inspectionRef: _ref,
        fields: fields,
        wetInkPath: wetInk,
        label: 'Signature: ${party.str('name') ?? party.str('party_role')}',
        dependsOn: _dependsOn);
    if (!context.mounted) return;
    showSubmitOutcome(context, r.outcome, sentText: 'Saved.');
    if (r.outcome is SubmitSent) unawaited(_load(quiet: true));
  }

  Future<(String, String)?> _pickRefusal(BuildContext context) async {
    final presets = _vocab.objs('refusal_reason_presets');
    final key = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final p in presets)
            ListTile(
                title: Text(p.str('label') ?? p.str('key') ?? ''),
                onTap: () => Navigator.pop(ctx, p.str('key'))),
        ]),
      ),
    );
    if (key == null || !context.mounted) return null;
    final note = await _prompt(context,
        key == 'other' ? 'Why? (required)' : 'Anything to add? (optional)',
        maxLength: 2000);
    if (note == null) return null;
    if (key == 'other' && note.isEmpty) return null;
    return (key, note);
  }

  Future<void> _agentSignature(BuildContext context) async {
    final png = await SignaturePadScreen.capture(context, 'Your signature');
    if (png == null || !context.mounted) return;
    final r = await _api.recordSignature(
        inspectionRef: _ref,
        fields: {
          'party_role': 'agent',
          'disposition': 'signed',
          'signing_method': 'drawn',
          'signature_image': png,
        },
        label: 'Your signature',
        dependsOn: _dependsOn);
    if (!context.mounted) return;
    showSubmitOutcome(context, r.outcome, sentText: 'Signed.');
    if (r.outcome is SubmitSent) unawaited(_load(quiet: true));
  }

  Future<void> _complete(BuildContext context, {bool ack = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final d = await _api.completeInspection(_id!,
          acknowledgeWarnings: ack, startLocalId: widget.startLocalId);
      await RentalsCache.write(
          _session, 'inspection:$_id', withoutPhotoUrls(d));
      if (!mounted) return;
      setState(() => _detail = d);
      messenger.showSnackBar(
          const SnackBar(content: Text('Inspection completed.')));
    } on RentalsApiException catch (e) {
      if (!context.mounted) return;
      if (e.code == 'needs_acknowledgement') {
        final warnings = (e.body['warnings'] as List? ?? const [])
            .map((w) => w is Map ? (w['message'] ?? w['text'] ?? '$w') : '$w')
            .join('\n• ');
        final go = await showDialog<bool>(
          context: context,
          builder: (dlg) => AlertDialog(
            title: const Text('Complete anyway?'),
            content: Text(
                '${e.message}${warnings.isEmpty ? '' : '\n\n• $warnings'}'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dlg, false),
                  child: const Text('Go back')),
              TextButton(
                  onPressed: () => Navigator.pop(dlg, true),
                  child: const Text('Complete')),
            ],
          ),
        );
        if (go == true && context.mounted) await _complete(context, ack: true);
        return;
      }
      if (e.code == 'items_pending') {
        // Keep the screen open and nudge the queue; it finishes syncing.
        _queue.kick();
      }
      final ungraded = (e.body['ungraded_items'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => '${m['room_label'] ?? ''} · ${m['item_label'] ?? ''}')
          .toList();
      await showDialog<void>(
        context: context,
        builder: (dlg) => AlertDialog(
          title: const Text('Not completed yet'),
          content: Text([
            e.isNetwork ? 'Completing needs signal.' : e.message,
            if (ungraded.isNotEmpty) '\n${ungraded.join('\n')}',
          ].join('\n')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dlg), child: const Text('OK')),
          ],
        ),
      );
    }
  }

  Future<String?> _prompt(BuildContext context, String title,
      {String? initial, int? maxLength}) async {
    final c = TextEditingController(text: initial);
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          minLines: 2,
          maxLines: 6,
          maxLength: maxLength,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(d, c.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    c.dispose();
    return v;
  }
}

/// Where each inspection photo shows on the walkthrough.
class PhotoPlaces {
  final byItem = <int, List<Json>>{};
  final byRoom = <int, List<Json>>{};
  final tray = <Json>[];
  final pendingByItem = <int, List<String>>{};
  final pendingByRoom = <int, List<String>>{};
  final pendingTray = <String>[];
}

/// The web's filing rule over the detail's `photos[]`: on its checklist item
/// (one of [itemIds]), else under its room (one of [roomIds]), else the
/// "Unsorted photos" tray. Archived photos are left out.
@visibleForTesting
PhotoPlaces placeInspectionPhotos(
    List<Json> photos, Set<int> itemIds, Set<int> roomIds) {
  final places = PhotoPlaces();
  for (final p in photos) {
    if (p.flag('archived')) continue;
    final item = p.integer('item_id');
    final room = p.integer('room_id');
    if (item != null && itemIds.contains(item)) {
      places.byItem.putIfAbsent(item, () => []).add(p);
    } else if (room != null && roomIds.contains(room)) {
      places.byRoom.putIfAbsent(room, () => []).add(p);
    } else {
      places.tray.add(p);
    }
  }
  return places;
}

/// A copy of an inspection detail for the offline cache, without the photo
/// links: they are signed and expire, so they are never kept.
Json withoutPhotoUrls(Json detail) {
  final copy = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(detail)) as Map);
  void strip(Object? photos) {
    if (photos is! List) return;
    for (final p in photos) {
      if (p is Map) p.remove('url');
    }
  }

  strip(copy['photos']);
  for (final o in copy['observations'] as List? ?? const []) {
    if (o is Map) strip(o['photos']);
  }
  return copy;
}

class _ObservationInput {
  final String condition;
  final String? notes;
  final List<XFile> photos;
  const _ObservationInput(this.condition, this.notes, this.photos);
}

class _ObservationSheet extends StatefulWidget {
  final String title;
  final List<Json> conditions;
  final Json? latest;
  const _ObservationSheet(
      {required this.title, required this.conditions, this.latest});
  @override
  State<_ObservationSheet> createState() => _ObservationSheetState();
}

class _ObservationSheetState extends State<_ObservationSheet> {
  String? _condition;
  final _notes = TextEditingController();
  List<XFile> _photos = const [];

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  bool get _needsNotes {
    for (final c in widget.conditions) {
      if (c.str('key') == _condition) return c.flag('requires_notes');
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final latest = widget.latest;
    return SheetForm(
      title: widget.title,
      submitLabel: 'Record',
      busy: false,
      onSubmit: _condition == null ||
              (_needsNotes && _notes.text.trim().isEmpty)
          ? null
          : () => Navigator.pop(context,
              _ObservationInput(_condition!, _notes.text.trim(), _photos)),
      children: [
        if (latest != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: BodyText(
                'Last recorded: ${conditionLabel(widget.conditions, latest.str('condition'))}'
                '${latest.str('notes') == null ? '' : ' — ${latest.str('notes')}'}',
                muted: true),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in widget.conditions)
              RentalsChoiceChip(
                label: Text(c.str('label') ?? c.str('key') ?? ''),
                selected: _condition == c.str('key'),
                color: conditionColor(widget.conditions, c.str('key')),
                onSelected: (_) => setState(() => _condition = c.str('key')),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          maxLength: 4000,
          minLines: 2,
          maxLines: 5,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              labelText: _needsNotes ? 'Notes (required)' : 'Notes'),
        ),
        PhotoPickerRow(
            photos: _photos, onChanged: (p) => setState(() => _photos = p)),
      ],
    );
  }
}

class _AttendanceSheet extends StatefulWidget {
  final Json row;
  const _AttendanceSheet({required this.row});
  @override
  State<_AttendanceSheet> createState() => _AttendanceSheetState();
}

class _AttendanceSheetState extends State<_AttendanceSheet> {
  String? _outcome;
  String _as = 'self';
  final _name = TextEditingController();
  final _note = TextEditingController();
  TimeOfDay? _arrived;

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _needsName => _as == 'representative' || _as == 'other';

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    return SheetForm(
      title: 'Was ${row.str('name') ?? 'this person'} there?',
      submitLabel: 'Save',
      busy: false,
      onSubmit: _outcome == null || (_needsName && _name.text.trim().isEmpty)
          ? null
          : () {
              final role = row.str('party_role');
              Navigator.pop(context, <String, dynamic>{
                'party_role': role,
                if (row.integer('contact_id') != null)
                  'party_contact_id': row.integer('contact_id'),
                if (row.integer('user_id') != null)
                  'party_user_id': row.integer('user_id'),
                'outcome': _outcome,
                'attended_as': _as,
                if (_needsName) 'attendee_name': _name.text.trim(),
                if (_arrived != null)
                  'arrived_at':
                      '${_arrived!.hour.toString().padLeft(2, '0')}:${_arrived!.minute.toString().padLeft(2, '0')}',
                if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
              });
            },
      children: [
        OptionField(
          label: 'Outcome',
          value: _outcome,
          options: const [
            ('attended', 'Attended'),
            ('did_not_attend', 'Did not attend'),
          ],
          onChanged: (v) => setState(() => _outcome = v),
        ),
        if (_outcome == 'attended') ...[
          OptionField(
            label: 'Attended as',
            value: _as,
            options: const [
              ('self', 'Themselves'),
              ('representative', 'A representative'),
              ('co_occupant', 'A co-occupant'),
              ('other', 'Someone else'),
            ],
            onChanged: (v) => setState(() => _as = v ?? 'self'),
          ),
          if (_needsName)
            TextField(
              controller: _name,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Name of attendee'),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(TablerIcons.clock),
            label: Text(_arrived == null
                ? 'Arrival time (optional)'
                : 'Arrived ${_arrived!.format(context)}'),
            onPressed: () async {
              final t = await showTimePicker(
                  context: context, initialTime: TimeOfDay.now());
              if (t != null) setState(() => _arrived = t);
            },
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _note,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
      ],
    );
  }
}
