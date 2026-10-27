import 'package:flutter/material.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../../services/rentals/client_rentals_api.dart';
import '../../../services/rentals/rentals_http.dart';
import '../../../theme.dart';
import '../widgets/rentals_ui.dart';

// The tenant's and the owner's view of their home's inspections: read-only,
// condition only (no money), wording neutral. The tenant payload carries
// nothing about the lessor and these screens read only the fields named in
// the contract, so nothing else can ever be shown.

/// The web's own naming (`RentalInspection::typeName`) built from the server's
/// `type_label`: "In-inspection", "Out-inspection", "Routine inspection".
String inspectionTypeName(String? type, String? typeLabel) => switch (type) {
      'in' || 'out' => typeLabel == null ? 'Inspection' : '$typeLabel-inspection',
      _ => typeLabel == null ? 'Inspection' : '$typeLabel inspection',
    };

/// Inspections of my home(s): sent ones open; a booked date is a date only.
class ClientInspectionsScreen extends StatelessWidget {
  final ClientRentalsApi api;
  const ClientInspectionsScreen({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'Inspections',
      body: RentalsFutureView<Json>(
        load: api.inspections,
        builder: (context, d, _) {
          final rows = d.objs('inspections');
          if (rows.isEmpty) {
            return ListView(children: const [
              RentalsEmpty(reason: 'No inspections yet.'),
            ]);
          }
          // Inspection, Out Inspection, then any other kind; newest first in each
          // (booked dates, being upcoming, lead). The rows carry no tenancy,
          // so the owner's earlier tenancies fall into date order.
          int rank(Json r) => switch (r.str('type')) {
                'in' => 0,
                'out' => 1,
                _ => 2,
              };
          final sorted = [...rows]..sort((a, b) {
              final t = rank(a).compareTo(rank(b));
              if (t != 0) return t;
              return (b.str('date') ?? '').compareTo(a.str('date') ?? '');
            });
          final children = <Widget>[];
          String? heading;
          for (final r in sorted) {
            final h = inspectionTypeName(r.str('type'), r.str('type_label'));
            if (h != heading) {
              heading = h;
              children.add(Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                child: BodyText(h, muted: true),
              ));
            }
            children.add(Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _row(context, r),
            ));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: children,
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, Json r) {
    final viewable = r.flag('viewable');
    final id = r.integer('id');
    final date = fmtDate(r.str('date'));
    return RentalsListCard(
      title: inspectionTypeName(r.str('type'), r.str('type_label')),
      meta: viewable
          ? [
              date,
              if (r.str('completed_at') != null)
                'completed ${fmtMoment(r.str('completed_at'))}',
            ].where((e) => e.isNotEmpty).join(' · ')
          : [
              'Booked for $date',
              r.str('time'),
            ].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
      statusLabel: r.str('status_label'),
      statusKey: r.str('status'),
      onTap: viewable && id != null
          ? () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  ClientInspectionDetailScreen(api: api, inspectionId: id)))
          : null,
    );
  }
}

/// One sent inspection, room by room. Fetched fresh on every open: the photo
/// links are signed and expire, so nothing here is cached.
class ClientInspectionDetailScreen extends StatefulWidget {
  final ClientRentalsApi api;
  final int inspectionId;
  const ClientInspectionDetailScreen(
      {super.key, required this.api, required this.inspectionId});

  @override
  State<ClientInspectionDetailScreen> createState() =>
      _ClientInspectionDetailScreenState();
}

class _ClientInspectionDetailScreenState
    extends State<ClientInspectionDetailScreen> {
  Json? _inspection;
  Object? _error;
  bool _loading = true;

  /// One re-fetch for expired photo links per open / refresh, never a loop.
  bool _photoRefetchUsed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _inspection == null;
      _error = null;
    });
    try {
      final body = await widget.api.inspection(widget.inspectionId);
      final insp = body.obj('inspection');
      if (!widget.api.isOwner && insp != null) reportOwnerFields(insp);
      if (!mounted) return;
      setState(() {
        _inspection = insp;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _refresh() {
    _photoRefetchUsed = false;
    return _load();
  }

  void _onPhotoError() {
    if (_photoRefetchUsed || !mounted) return;
    _photoRefetchUsed = true;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final i = _inspection;
    final e = _error;
    return RentalsPage(
      title: i == null
          ? 'Inspection'
          : inspectionTypeName(i.str('type'), i.str('type_label')),
      body: _loading
          ? const RentalsLoading()
          : i == null && e is RentalsApiException && e.statusCode == 404
              // Not theirs, a booked date only, or not sent yet: no retry.
              ? ListView(children: [
                  RentalsEmpty(
                      reason: e.message.isNotEmpty
                          ? e.message
                          : 'Inspection not found.'),
                ])
              : i == null
                  ? RentalsError(error: e ?? 'error', onRetry: _refresh)
                  : RefreshIndicator(
                      onRefresh: _refresh, child: _body(context, i)),
    );
  }

  Widget _body(BuildContext context, Json i) {
    final isOut = i.str('type') == 'out';
    final header = i.obj('header');
    final signatures = i.obj('signatures');
    final related = i.obj('related');
    final meters = i.objs('meters');
    final others = i.objs('other_items');
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 40),
      children: [
        RentalsSection(
          title: i.obj('property')?.str('address') ?? 'My home',
          trailing: RentalsStatusChip(
              i.str('type_label') ??
                  inspectionTypeName(i.str('type'), null),
              statusKey: null),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KeyValueRow('Date', fmtDate(i.str('date'))),
              KeyValueRow('Completed', fmtMoment(i.str('completed_at'))),
              if (header != null) ...[
                KeyValueRow('Electricity meter',
                    header.str('electricity_meter_reading')),
                KeyValueRow(
                    'Water meter', header.str('water_meter_reading')),
                KeyValueRow('Furnished',
                    displayValue(header.str('furnished_status'))),
                KeyValueRow('Keys',
                    _countWith(header.integer('keys_count'),
                        header.str('keys_description'))),
                KeyValueRow('Remotes',
                    _countWith(header.integer('remotes_count'),
                        header.str('remotes_description'))),
              ],
            ],
          ),
        ),
        if (related != null && related.integer('id') != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: ElevatedButton.icon(
              icon: const Icon(TablerIcons.arrows_exchange),
              label: Text('View '
                  '${inspectionTypeName(related.str('type'), related.str('type_label'))}'),
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => ClientInspectionDetailScreen(
                      api: widget.api,
                      inspectionId: related.integer('id')!),
                ),
              ),
            ),
          ),
        for (final room in i.objs('rooms'))
          _section(context,
              title: room.str('label') ?? 'Room',
              note: room.str('note'),
              items: room.objs('items'),
              photos: room.objs('photos'),
              isOut: isOut),
        if (meters.isNotEmpty)
          _section(context,
              title: 'Meters', items: meters, photos: const [], isOut: isOut),
        if (others.isNotEmpty)
          _section(context,
              title: 'Other items',
              items: others,
              photos: const [],
              isOut: isOut),
        if (i.str('overall_notes') != null)
          RentalsSection(
            title: 'Overall notes',
            child: BodyText(i.str('overall_notes')!),
          ),
        if (signatures != null)
          RentalsSection(
            title: 'Signatures',
            child: Column(children: [
              _signed(context, 'You', signatures.flag('you_signed')),
              _signed(context, 'Agent', signatures.flag('agent_signed')),
              // Owner only; a tenant's payload never carries it, and the
              // tenant view never reads it.
              if (widget.api.isOwner && signatures.containsKey('tenant_signed'))
                _signed(context, 'Tenant', signatures.flag('tenant_signed')),
            ]),
          ),
      ],
    );
  }

  static Widget _signed(BuildContext context, String who, bool done) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(
            child: Text(who,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary(context))),
          ),
          RentalsStatusChip(done ? 'Signed' : 'Pending',
              statusKey: done ? 'signed' : 'pending',
              icon: done ? TablerIcons.check : TablerIcons.clock),
        ]),
      );

  static String? _countWith(int? n, String? description) {
    if (n == null && (description == null || description.isEmpty)) {
      return null;
    }
    return [
      if (n != null) '$n',
      if (description != null && description.isNotEmpty) description,
    ].join(' — ');
  }

  Widget _section(
    BuildContext context, {
    required String title,
    String? note,
    required List<Json> items,
    required List<Json> photos,
    required bool isOut,
  }) {
    return RentalsSection(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (note != null && note.isNotEmpty) ...[
            BodyText(note, muted: true),
            const SizedBox(height: 8),
          ],
          for (final item in items) _item(context, item, isOut),
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 8),
            const RentalsSubLabel('Room photos'),
            _photos(photos),
          ],
        ],
      ),
    );
  }

  Widget _item(BuildContext context, Json item, bool isOut) {
    final condition = item.str('condition');
    final moveIn = item.obj('move_in');
    final changed = isOut &&
        moveIn != null &&
        moveIn.str('condition') != null &&
        moveIn.str('condition') != condition;
    final photos = item.objs('photos');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(item.str('label') ?? 'Item',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (changed)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: RentalsStatusChip('Changed', statusKey: 'review'),
              ),
            if (condition != null)
              // Neutral: the condition words are the agency's own.
              RentalsStatusChip(displayValue(condition), statusKey: null),
          ]),
          if (item.str('notes') != null && item.str('notes')!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: BodyText(item.str('notes')!),
            ),
          // An Out Inspection shows each item's (in) Inspection record beside it; an Inspection
          // has no `move_in` key at all.
          if (isOut && item.containsKey('move_in'))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: BodyText(
                moveIn == null
                    ? 'Not recorded at the In-inspection'
                    : [
                        'At the In-inspection: ${displayValue(moveIn.str('condition'))}',
                        if (moveIn.str('notes') != null &&
                            moveIn.str('notes')!.isNotEmpty)
                          moveIn.str('notes')!,
                      ].join(' — '),
                muted: true,
              ),
            ),
          if (photos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _photos(photos),
            ),
        ],
      ),
    );
  }

  Widget _photos(List<Json> photos) {
    final shown = photos.where((p) => p.str('url') != null).toList();
    return RentalsPhotoGrid(
      [for (final p in shown) p.str('url')!],
      captions: [
        for (final p in shown)
          [
            if (p.str('taken_at') != null)
              'Taken ${fmtMoment(p.str('taken_at'))}',
            if (p.flag('added_after_signing')) 'added after signing',
          ].join(' · '),
      ],
      emptyText: null,
      onLoadError: _onPhotoError,
    );
  }
}

/// The tenant must see nothing about the lessor, and the server sends none.
/// If an owner field ever turns up in a tenant payload that is a server bug:
/// log it loudly (it is never displayed — the screen reads named fields only).
@visibleForTesting
List<String> reportOwnerFields(Json payload) {
  final found = <String>[];
  void walk(Object? v, String path) {
    if (v is Map) {
      v.forEach((k, child) {
        final key = k.toString().toLowerCase();
        final here = path.isEmpty ? '$k' : '$path.$k';
        if (key.contains('landlord') ||
            key.contains('owner') ||
            key.contains('lessor') ||
            key == 'tenant_signed') {
          found.add(here);
        }
        walk(child, here);
      });
    } else if (v is List) {
      for (var i = 0; i < v.length; i++) {
        walk(v[i], '$path[$i]');
      }
    }
  }

  walk(payload, '');
  if (found.isNotEmpty) {
    debugPrint('[rentals] SERVER BUG: owner field(s) in a tenant inspection '
        'payload, not shown: ${found.join(', ')}');
  }
  return found;
}
