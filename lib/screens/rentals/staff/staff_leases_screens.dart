import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../../providers/rentals_access_provider.dart';
import '../../../services/rentals/rentals_http.dart';
import '../../../services/rentals/staff_rentals_api.dart';
import '../widgets/rentals_actions.dart';
import '../widgets/rentals_ui.dart';
import 'staff_faults_screens.dart';
import 'staff_inspections_screens.dart';
import 'staff_lease_actions.dart';

final _api = StaffRentalsApi.instance;

class StaffLeasesScreen extends StatelessWidget {
  final bool initialExpiring;
  const StaffLeasesScreen({super.key, this.initialExpiring = false});

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'Leases',
      body: RentalsPagedList<Json>(
        searchHint: 'Address, tenant, owner or L-ref',
        initialFilters: initialExpiring
            ? const {'expiring_within_days': '60'}
            : const {},
        filters: const [
          ListFilter(param: 'expiring_within_days', label: 'Expiring', options: [
            ('30', 'Within 30 days'),
            ('60', 'Within 60 days'),
            ('90', 'Within 90 days'),
          ]),
          ListFilter(param: 'status', label: 'Status', options: [
            ('active', 'Active'),
            ('signed_awaiting_start', 'Signed, not started'),
            ('draft', 'Draft'),
            ('expired', 'Expired'),
            ('cancelled', 'Cancelled'),
          ]),
          ListFilter(param: 'sort', label: 'Sort', options: [
            ('end_date', 'End date'),
            ('start_date', 'Start date'),
            ('property', 'Property'),
            ('status', 'Status'),
          ]),
        ],
        fetch: _api.leases,
        itemBuilder: (context, l) => _LeaseCard(lease: l),
      ),
    );
  }
}

class _LeaseCard extends StatelessWidget {
  final Json lease;
  const _LeaseCard({required this.lease});

  @override
  Widget build(BuildContext context) {
    final l = lease;
    final tenants =
        l.objs('tenants').map((t) => t.str('name')).whereType<String>().join(', ');
    final days = l.integer('days_left');
    return RentalsListCard(
      title: l.obj('property')?.str('address') ?? l.str('reference') ?? 'Lease',
      subtitle: tenants,
      meta: [
        l.str('reference'),
        l.flag('is_month_to_month')
            ? 'Month to month'
            : l.str('end_date') == null
                ? null
                : 'Ends ${fmtDate(l.str('end_date'))}${days == null ? '' : ' · $days days'}',
      ].whereType<String>().join(' · '),
      statusLabel: l.str('status_label'),
      statusKey: l.str('status'),
      badges: [
        if (l.flag('has_notice'))
          const RentalsStatusChip('Notice given', statusKey: 'notice'),
      ],
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => StaffLeaseFileScreen(leaseId: l.integer('id')!))),
    );
  }
}

/// The lease file (from the web Lease Hub's own service), plus the actions
/// the `can` block allows. Renewal drafts and uploads are web-only: they
/// carry the rent, and the app shows no money.
class StaffLeaseFileScreen extends StatefulWidget {
  final int leaseId;
  const StaffLeaseFileScreen({super.key, required this.leaseId});

  @override
  State<StaffLeaseFileScreen> createState() => _StaffLeaseFileScreenState();
}

class _StaffLeaseFileScreenState extends State<StaffLeaseFileScreen> {
  final _refresh = ValueNotifier<int>(0);

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'L-${widget.leaseId}',
      body: RentalsFutureView<Json>(
        refresh: _refresh,
        load: () => _api.lease(widget.leaseId),
        builder: (context, l, reload) => _body(context, l),
      ),
    );
  }

  Widget _body(BuildContext context, Json l) {
    final signing = l.obj('signing');
    final notice = l.obj('notice');
    final renewal = l.obj('renewal');
    final open = l.obj('open_items');
    final can = l.obj('can') ?? const {};
    final next = l.obj('next_step');
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      children: [
        RentalsSection(
          title: l.obj('property')?.str('address') ?? 'Lease',
          trailing: RentalsStatusChip(l.str('status_label') ?? '',
              statusKey: l.str('status')),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (next?.str('label') != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: RentalsStatusChip('Next: ${next!.str('label')}',
                      statusKey: 'review', icon: TablerIcons.arrow_right),
                ),
              KeyValueRow('Agreement', l.str('agreement_label')),
              KeyValueRow('Type', l.str('lease_type')),
              KeyValueRow('Starts', fmtDate(l.str('start_date'))),
              KeyValueRow(
                  'Ends',
                  l.flag('is_month_to_month')
                      ? 'Month to month'
                      : fmtDate(l.str('end_date'))),
              KeyValueRow('Days left', l.integer('days_left')?.toString()),
              KeyValueRow('Owner agent', l.obj('owner_agent')?.str('name')),
              KeyValueRow('Tenant agent', l.obj('tenant_agent')?.str('name')),
            ],
          ),
        ),
        RentalsSection(
          title: 'Tenants',
          child: Column(children: [
            for (final t in l.objs('tenants')) _person(t),
          ]),
        ),
        RentalsSection(
          title: 'Owners',
          child: Column(children: [
            for (final t in l.objs('owners')) _person(t),
          ]),
        ),
        if (l.objs('lifecycle').isNotEmpty)
          RentalsSection(
            title: 'Lifecycle',
            child: RentalsTimeline([
              for (final s in l.objs('lifecycle'))
                {
                  'label': s.str('label'),
                  'state': s.str('state') == 'pending' ? 'todo' : 'done',
                  'current': s.str('state') == 'current',
                },
            ]),
          ),
        if (_moveOutDue(l) &&
            context.watch<RentalsAccess>().staffScreens.inspections.canAct)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: ElevatedButton.icon(
              icon: const Icon(TablerIcons.door_exit),
              label: const Text('Start out-inspection'),
              onPressed: () => _startMoveOut(context, l),
            ),
          ),
        if (notice != null && notice.flag('active'))
          RentalsSection(
            title: 'Notice',
            child: Column(children: [
              KeyValueRow('Given by',
                  kGivenByLabels[notice.str('given_by')] ?? displayValue(notice.str('given_by'))),
              KeyValueRow('Notice date', fmtDate(notice.str('notice_date'))),
              KeyValueRow('Move-out', fmtDate(notice.str('move_out_date'))),
              KeyValueRow('Outcome',
                  kNoticeOutcomeLabels[notice.str('outcome')] ?? displayValue(notice.str('outcome'))),
              KeyValueRow('Note', notice.str('note')),
              KeyValueRow('To review', notice.integer('notices_to_review')?.toString()),
            ]),
          ),
        if (renewal != null)
          RentalsSection(
            title: 'Renewal',
            child: Column(children: [
              KeyValueRow('In progress',
                  renewal.flag('has_renewal_in_progress') ? 'Yes' : 'No'),
              KeyValueRow('Signed, awaiting start',
                  renewal.flag('renewal_signed_awaiting_start') ? 'Yes' : null),
              KeyValueRow('Expiry notice sent',
                  fmtMoment(renewal.str('expiry_notice_sent_at'))),
            ]),
          ),
        if (signing != null)
          RentalsSection(
            title: 'Signing',
            child: Column(children: [
              KeyValueRow('Status', signing.str('label')),
              KeyValueRow('Signed', fmtMoment(signing.str('signed_at'))),
              for (final s in signing.objs('signers'))
                KeyValueRow('${s.str('role') ?? ''} ${s.str('name') ?? ''}'.trim(),
                    s.str('status')),
            ]),
          ),
        if (open != null)
          RentalsSection(
            title: 'Open items',
            child: Column(children: [
              KeyValueRow('Faults', open.integer('faults')?.toString()),
              KeyValueRow('Work orders', open.integer('work_orders')?.toString()),
              KeyValueRow('Inspections', open.integer('inspections')?.toString()),
            ]),
          ),
        RentalsSection(
          title: 'Documents',
          child: l.objs('documents').isEmpty
              ? const BodyText('No documents.', muted: true)
              : Column(children: [
                  for (final d in l.objs('documents'))
                    KeyValueRow(d.str('name') ?? 'Document',
                        fmtMoment(d.str('added_at'))),
                  const BodyText(
                      'Documents open on the web for now (no download link '
                      'in the app API yet).',
                      muted: true),
                ]),
        ),
        if (can.flag('renew') || can.flag('review_notices'))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              if (can.flag('renew') && !l.flag('is_month_to_month'))
                _btn(TablerIcons.repeat, 'Go month to month',
                    () => _monthToMonth(context)),
              if (can.flag('renew') && l.flag('is_month_to_month'))
                _btn(TablerIcons.arrow_back_up, 'Undo month to month',
                    () => _post(context, 'month-to-month/reverse', const {},
                        'Month to month reversed.')),
              if (can.flag('review_notices')) ...[
                if (notice != null && notice.flag('active')) ...[
                  _btn(TablerIcons.switch_horizontal, 'Change outcome',
                      () => _outcome(context)),
                  _btn(TablerIcons.arrow_back_up, 'Reverse notice',
                      () => _post(context, 'notice/reverse', const {},
                          'Notice reversed.')),
                ],
              ],
            ]),
          ),
        RentalsActionsSection(
          actions: leaseActionButtons(
            context,
            l,
            reload: () => _refresh.value++,
            onArchived: () {
              if (mounted) Navigator.of(context).pop();
            },
          ),
        ),
      ],
    );
  }

  /// Only what the server says: its lifecycle marks the `out_inspection` step
  /// current. Nothing is worked out here. (`next_step` would be the better
  /// signal, but the phone's payload carries its sentence only, no key.)
  static const kGivenByLabels = {
    'tenant': 'The tenant',
    'landlord': 'The landlord',
  };

  /// The web's own words (`LeaseRenewalService`); the lease payload sends
  /// only the code.
  static const kNoticeOutcomeLabels = {
    'readvertise': 'Back on the market',
    'withdraw': 'Withdrawn',
    'leave': 'Left as is',
  };

  static bool _moveOutDue(Json l) {
    for (final s in l.objs('lifecycle')) {
      if (s.str('key') == 'out_inspection') return s.str('state') == 'current';
    }
    return false;
  }

  /// Opens the lease's Out Inspection when one already exists (booked or under
  /// way — the server would refuse a second), otherwise starts one.
  Future<void> _startMoveOut(BuildContext context, Json l) async {
    final propertyId = l.obj('property')?.integer('id');
    final title = l.obj('property')?.str('address') ?? 'L-${widget.leaseId}';
    if (propertyId == null) return;
    Json? existing;
    try {
      final page = await _api.inspections(
          1, {'lease_id': '${widget.leaseId}', 'type': 'out'});
      for (final i in page.items) {
        if (i.str('status') != 'cancelled') {
          existing = i;
          break;
        }
      }
    } on RentalsApiException catch (e) {
      // Offline: fall through to a queued start; anything else is a refusal.
      if (!e.isNetwork) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
        return;
      }
    }
    if (!context.mounted) return;
    if (existing != null) {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => StaffInspectionScreen(
              inspectionId: existing!.integer('id'),
              propertyId: propertyId,
              title: title)));
    } else {
      await startInspectionAndOpen(context,
          leaseId: widget.leaseId,
          type: 'out',
          typeLabel: 'Out',
          propertyId: propertyId,
          title: title);
    }
    _refresh.value++;
  }

  Widget _person(Json p) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeyValueRow('Name', p.str('name')),
          KeyValueRow('Phone', p.str('phone'),
              icon: TablerIcons.phone,
              onTap: p.str('phone') == null ? null : () => dialPhone(p.str('phone')!)),
          KeyValueRow('Email', p.str('email'),
              icon: TablerIcons.mail,
              onTap: p.str('email') == null ? null : () => sendEmail(p.str('email')!)),
        ],
      );

  Widget _btn(IconData icon, String label, VoidCallback on) =>
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
        icon: Icon(icon, size: 18),
        label: Text(label),
        onPressed: on,
      );

  /// The existing `/leases/{id}/renewal/*` routes (JSON; refusals come back as
  /// `{error:{field:[msg]}}`, which [RentalsHttp] reads as the message).
  Future<void> _post(BuildContext context, String action, Json body,
      String done) async {
    final res = await runAction(
      context,
      () => RentalsHttp.instance.post(RentalsAudience.staff,
          '/leases/${widget.leaseId}/renewal/$action',
          body: body),
      successText: done,
    );
    if (res != null) _refresh.value++;
  }

  Future<void> _monthToMonth(BuildContext context) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Continue month to month?'),
        content: TextField(
          controller: note,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _post(context, 'month-to-month',
          {if (note.text.trim().isNotEmpty) 'note': note.text.trim()},
          'Now month to month.');
    }
    note.dispose();
  }

  Future<void> _outcome(BuildContext context) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final o in const [
            ('readvertise',
                'Put back on the market, available from the day after move-out'),
            ('withdraw',
                'Withdraw the property (landlord is taking it back / property is lost)'),
            ('leave', 'Leave as is for now'),
          ])
            ListTile(title: Text(o.$2), onTap: () => Navigator.pop(ctx, o.$1)),
        ]),
      ),
    );
    if (v != null && context.mounted) {
      await _post(context, 'notice/change-outcome', {'notice_outcome': v},
          'Outcome changed.');
    }
  }

}

/// Bumped after an accept / correction / archive so the list re-reads.
final _noticesRefresh = ValueNotifier<int>(0);

/// Notices tenants / owners gave that wait for review. A tap opens the lease,
/// accepts (with the correcting date), corrects or archives it — never a
/// reject (Johan: an agency acts on a notice, it does not refuse it).
class StaffNoticesScreen extends StatelessWidget {
  const StaffNoticesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'Notices to review',
      body: RentalsPagedList<Json>(
        refresh: _noticesRefresh,
        searchHint: 'Address, tenant, who gave it, reason',
        filters: const [
          ListFilter(param: 'status', label: 'Status', options: [
            ('received', 'Needs review'),
            ('accepted', 'Accepted'),
            ('rejected', 'Rejected'),
            ('withdrawn', 'Withdrawn'),
            ('all', 'All'),
          ]),
        ],
        fetch: (page, q) => _api.notices(page, resolveDateFilter(q)),
        itemBuilder: (context, n) {
          final age = n.integer('age_days');
          return RentalsListCard(
            title: n.obj('property')?.str('address') ?? 'Notice',
            subtitle: [
              n.str('given_by_label'),
              n.str('given_by_name'),
              n.str('reason'),
            ].whereType<String>().join(' · '),
            meta: [
              'Given ${fmtDate(n.str('notice_date'))}',
              if (n.str('intended_end_date') != null)
                'ends ${fmtDate(n.str('intended_end_date'))}',
              if (age != null) '$age days waiting',
            ].join(' · '),
            statusLabel: n.str('status_label'),
            statusKey: n.str('status'),
            // Open the lease, accept, correct or archive. Never reject.
            onTap: () async {
              final changed = await receivedNoticeActions(context, n,
                  openLease: () {
                if (n.integer('lease_id') == null) return;
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        StaffLeaseFileScreen(leaseId: n.integer('lease_id')!)));
              });
              if (changed) _noticesRefresh.value++;
            },
          );
        },
      ),
    );
  }
}
