import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../../services/rentals/client_rentals_api.dart';
import '../../../services/rentals/rental_write_queue.dart';
import '../../../services/rentals/rentals_http.dart';
import '../widgets/rentals_ui.dart';
import 'client_inspection_screens.dart';
import 'client_rentals_shared.dart';

final _api = ClientRentalsApi.owner;

/// Owner (lessor) rentals home: decisions waiting, My Lease per property with
/// the tenant's name, and the owner's actions. No rent or payment status.
class OwnerRentalsHomeScreen extends StatefulWidget {
  const OwnerRentalsHomeScreen({super.key});

  @override
  State<OwnerRentalsHomeScreen> createState() => _OwnerRentalsHomeScreenState();
}

class _OwnerRentalsHomeScreenState extends State<OwnerRentalsHomeScreen> {
  final _refresh = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    RentalWriteQueue.instance.sent.addListener(_bump);
  }

  @override
  void dispose() {
    RentalWriteQueue.instance.sent.removeListener(_bump);
    _refresh.dispose();
    super.dispose();
  }

  void _bump() => _refresh.value++;

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'My rental properties',
      body: RentalsFutureView<({Json lease, Json waiting})>(
        refresh: _refresh,
        load: () async {
          final r = await Future.wait([_api.myLease(), _api.waiting()]);
          return (lease: r[0], waiting: r[1]);
        },
        builder: (context, d, _) => _body(context, d.lease, d.waiting),
      ),
    );
  }

  Widget _body(BuildContext context, Json lease, Json waiting) {
    final cards = lease.objs('properties');
    final items = waiting.objs('items');
    void push(Widget w) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      children: [
        ClientAgencyHeader(api: _api),
        const RentalsQueueBanner(),
        RentalsSection(
          title: 'Waiting for your decision (${waiting.integer('waiting_count') ?? items.length})',
          child: items.isEmpty
              ? const BodyText('Nothing is waiting for you.', muted: true)
              : Column(children: [
                  for (final i in items) OwnerWaitingRow(item: i, onDone: _bump),
                ]),
        ),
        if (cards.isEmpty)
          const RentalsEmpty(reason: 'No rental properties to show.')
        else
          for (final c in cards) MyLeaseCard(card: c, showTenantNames: true),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Wrap(spacing: 10, runSpacing: 10, children: [
            _tile(context, TablerIcons.gavel, 'Decisions',
                () => push(const OwnerDecisionsScreen())),
            _tile(context, TablerIcons.alert_triangle, 'Faults',
                () => push(const OwnerFaultsScreen())),
            _tile(context, TablerIcons.tool, 'Work orders',
                () => push(const OwnerWorkOrdersScreen())),
            _tile(context, TablerIcons.plus, 'Request work',
                () => push(const OwnerReportFaultScreen())),
            _tile(context, TablerIcons.file_text, 'Notices',
                () => push(ClientNoticesScreen(api: _api))),
            _tile(context, TablerIcons.files, 'Documents',
                () => push(ClientDocumentsScreen(api: _api))),
            _tile(context, TablerIcons.clipboard_check, 'Inspections',
                () => push(ClientInspectionsScreen(api: _api))),
            _tile(context, TablerIcons.bell, 'Notifications',
                () => push(ClientPushPreferencesScreen(api: _api))),
          ]),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, IconData icon, String label, VoidCallback on) {
    final w = (MediaQuery.of(context).size.width.clamp(0, 720) - 42) / 2;
    return SizedBox(
      width: w,
      child: RentalsActionTile(icon: icon, label: label, onTap: on),
    );
  }
}

/// One owner "waiting" item: fault_report | work_order | variation.
class OwnerWaitingRow extends StatelessWidget {
  final Json item;
  final VoidCallback onDone;
  const OwnerWaitingRow({super.key, required this.item, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final kind = item.str('kind');
    return RentalsNavRow(
      icon: kind == 'variation'
          ? TablerIcons.circle_plus
          : kind == 'work_order'
              ? TablerIcons.file_invoice
              : TablerIcons.alert_triangle,
      title: item.str('title') ?? '',
      subtitle: [
        kind == 'variation'
            ? 'Extra work'
            : kind == 'work_order'
                ? 'Quote to approve'
                : 'Repair to approve',
        if (item.flag('emergency')) 'Emergency',
        if (item.str('waiting_since') != null)
          'since ${fmtMoment(item.str('waiting_since'))}',
      ].join(' · '),
      onTap: () async {
        final id = item.integer('id');
        if (id == null) return;
        if (kind == 'variation') {
          // The decisions list carries the variation's lines and revision.
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const OwnerDecisionsScreen()));
        } else {
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => kind == 'work_order'
                  ? OwnerWorkOrderScreen(workOrderId: id)
                  : OwnerFaultDetailScreen(faultId: id)));
        }
        onDone();
      },
    );
  }
}

class OwnerDecisionsScreen extends StatefulWidget {
  const OwnerDecisionsScreen({super.key});
  @override
  State<OwnerDecisionsScreen> createState() => _OwnerDecisionsScreenState();
}

class _OwnerDecisionsScreenState extends State<OwnerDecisionsScreen> {
  final _refresh = ValueNotifier<int>(0);

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'Decisions',
      body: RentalsFutureView<Json>(
        refresh: _refresh,
        load: _api.decisions,
        builder: (context, d, _) {
          final faults = d.objs('fault_reports');
          final wos = d.objs('work_orders');
          final vars = d.objs('variations');
          if (faults.isEmpty && wos.isEmpty && vars.isEmpty) {
            return ListView(children: const [
              RentalsEmpty(reason: 'Nothing is waiting for your decision.'),
            ]);
          }
          Future<void> open(Widget w) async {
            await Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => w));
            _refresh.value++;
          }

          return ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 32),
            children: [
              if (faults.isNotEmpty)
                RentalsSection(
                  title: 'Repairs to approve',
                  child: Column(children: [
                    for (final f in faults)
                      RentalsNavRow(
                        icon: TablerIcons.alert_triangle,
                        title: f.str('title') ?? '',
                        onTap: () =>
                            open(OwnerFaultDetailScreen(faultId: f.integer('id')!)),
                      ),
                  ]),
                ),
              if (wos.isNotEmpty)
                RentalsSection(
                  title: 'Quotes to approve',
                  child: Column(children: [
                    for (final w in wos)
                      RentalsNavRow(
                        icon: TablerIcons.file_invoice,
                        title: w.str('title') ?? '',
                        subtitle: w.flag('emergency') ? 'Emergency' : null,
                        onTap: () =>
                            open(OwnerWorkOrderScreen(workOrderId: w.integer('id')!)),
                      ),
                  ]),
                ),
              for (final v in vars) _variation(context, v),
            ],
          );
        },
      ),
    );
  }

  Widget _variation(BuildContext context, Json v) {
    return RentalsSection(
      title: 'Extra work · ${v.str('title') ?? ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (v.str('reason') != null) BodyText(v.str('reason')!),
          for (final l in v.objs('lines'))
            KeyValueRow(
                '${l.str('quantity') ?? ''} ${l.str('unit') ?? ''}'.trim(),
                [l.str('description'), l.str('total')]
                    .whereType<String>()
                    .join(' · ')),
          KeyValueRow('Agreed so far', v.str('baseline_amount')),
          KeyValueRow('Extra', v.str('extra_amount')),
          KeyValueRow('New total', v.str('new_total')),
          if (v.str('term_text') != null) BodyText(v.str('term_text')!, muted: true),
          if (v.objs('photos').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: RentalsPhotoGrid([
                for (final p in v.objs('photos'))
                  if (p.str('url') != null) p.str('url')!,
              ]),
            ),
          const SizedBox(height: 10),
          _ApproveDeclineRow(
            onApprove: () => _decideVariation(context, v, 'approve'),
            onDecline: () => _decideVariation(context, v, 'decline'),
          ),
        ],
      ),
    );
  }

  Future<void> _decideVariation(
      BuildContext context, Json v, String decision) async {
    final note = await askNote(context,
        title: decision == 'approve' ? 'Approve the extra work?' : 'Decline the extra work?',
        label: 'Note (optional)');
    if (note == null || !context.mounted) return;
    final res = await runAction(
      context,
      () => _api.variationDecision(v.integer('id')!,
          decision: decision, revision: v.integer('revision') ?? 1, note: note),
      successText: decision == 'approve' ? 'Approved.' : 'Declined.',
    );
    // A 409 means the request changed meanwhile: reloading shows the new one.
    _refresh.value++;
    if (res == null) return;
  }
}

class _ApproveDeclineRow extends StatelessWidget {
  final VoidCallback onApprove;
  final VoidCallback onDecline;
  const _ApproveDeclineRow({required this.onApprove, required this.onDecline});

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: ElevatedButton(onPressed: onApprove, child: const Text('Approve')),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: onDecline,
            child: const Text('Decline'),
          ),
        ),
      ]);
}

/// A dialog asking for a note. Returns the text ('' when left empty), or null
/// when cancelled. [minLength] > 0 makes it required.
Future<String?> askNote(BuildContext context,
    {required String title, required String label, int minLength = 0}) async {
  final c = TextEditingController();
  final v = await showDialog<String>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setState) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          maxLength: 2000,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          TextButton(
            onPressed: c.text.trim().length < minLength
                ? null
                : () => Navigator.pop(d, c.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
  c.dispose();
  return v;
}

class OwnerFaultsScreen extends StatelessWidget {
  const OwnerFaultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'Faults',
      body: Column(children: [
        const RentalsQueueBanner(),
        Expanded(
          child: RentalsFutureView<Json>(
            refresh: RentalWriteQueue.instance.sent,
            load: _api.faultReports,
            builder: (context, d, _) {
              final rows = d.objs('fault_reports');
              if (rows.isEmpty) {
                return ListView(children: const [
                  RentalsEmpty(reason: 'There are no faults to show.'),
                ]);
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final f = rows[i];
                  return RentalsListCard(
                    title: f.str('title') ?? 'Fault',
                    meta: fmtMoment(f.str('reported_at')),
                    statusLabel: f.str('end_state') ?? f.str('status_label'),
                    statusKey: f.str('status'),
                    highlight: f.flag('needs_decision'),
                    badges: [
                      if (f.flag('needs_decision'))
                        const RentalsStatusChip('Your decision',
                            statusKey: 'awaiting'),
                    ],
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            OwnerFaultDetailScreen(faultId: f.integer('id')!))),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

class OwnerFaultDetailScreen extends StatefulWidget {
  final int faultId;
  const OwnerFaultDetailScreen({super.key, required this.faultId});

  @override
  State<OwnerFaultDetailScreen> createState() => _OwnerFaultDetailScreenState();
}

class _OwnerFaultDetailScreenState extends State<OwnerFaultDetailScreen> {
  final _refresh = ValueNotifier<int>(0);

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'Fault',
      body: RentalsFutureView<Json>(
        refresh: _refresh,
        load: () => _api.faultReport(widget.faultId),
        builder: (context, d, _) => _body(context, d.obj('fault_report') ?? d),
      ),
    );
  }

  Widget _body(BuildContext context, Json f) {
    final actions = f.obj('owner_actions');
    final hold = actions?.obj('hold');
    final decision = f.obj('decision');
    final wo = f.obj('work_order');
    final selfResolved = f.flag('self_resolved');
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      children: [
        RentalsSection(
          title: f.str('title') ?? 'Fault',
          trailing: RentalsStatusChip(f.str('status_label') ?? '',
              statusKey: f.str('status')),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (f.str('description') != null) BodyText(f.str('description')!),
              if (f.str('tenant_description') != null)
                BodyText(f.str('tenant_description')!),
              if (f.str('agent_note') != null) ...[
                const SizedBox(height: 6),
                BodyText('From your agent: ${f.str('agent_note')}', muted: true),
              ],
              const SizedBox(height: 6),
              KeyValueRow('Property', f.str('property') ?? f.obj('property')?.str('address')),
              KeyValueRow('Category', f.str('category')),
              KeyValueRow('Reported', fmtMoment(f.str('reported_at'))),
              KeyValueRow('Sent to you', fmtMoment(f.str('sent_to_owner_at'))),
              KeyValueRow('Earlier report', f.obj('reported_before')?.str('text')),
              if (f.obj('arranged')?.str('text') != null)
                KeyValueRow('Arranged', f.obj('arranged')!.str('text')),
              if (f.obj('authorisation') != null)
                KeyValueRow(f.obj('authorisation')!.str('title') ?? 'Authorised',
                    f.obj('authorisation')!.str('sentence')),
              if (decision != null)
                KeyValueRow(
                    'Your decision',
                    [
                      decision.str('decision'),
                      decision.str('contractor'),
                      decision.str('reason'),
                      fmtMoment(decision.str('at')),
                    ].whereType<String>().where((e) => e.isNotEmpty).join(' · ')),
              if (hold != null) KeyValueRow('On hold', hold.str('line')),
            ],
          ),
        ),
        if (f.objs('timeline').isNotEmpty)
          RentalsSection(title: 'Progress', child: RentalsTimeline(f.objs('timeline'))),
        if (f.objs('photos').isNotEmpty)
          RentalsSection(
            title: 'Photos',
            child: RentalsPhotoGrid([
              for (final p in f.objs('photos'))
                if (p.str('url') != null) p.str('url')!,
            ]),
          ),
        if (wo != null)
          RentalsSection(
            title: 'Repair',
            child: Column(children: [
              KeyValueRow('Stage', wo.str('stage_label')),
              KeyValueRow('Who', wo.str('who_label')),
              KeyValueRow('Contractor', wo.str('contractor_name')),
              KeyValueRow('Call-out', wo.str('contractor_callout')),
              KeyValueRow('Appointment', fmtMoment(wo.str('appointment_at'))),
              if (wo.integer('id') != null)
                KeyValueRow('Details', 'Open',
                    icon: TablerIcons.chevron_right,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            OwnerWorkOrderScreen(workOrderId: wo.integer('id')!)))),
            ]),
          ),
        if (actions != null && actions.objs('queries').isNotEmpty)
          RentalsSection(
            title: 'Your questions',
            child: Column(children: [
              for (final q in actions.objs('queries'))
                KeyValueRow(q.str('question') ?? '',
                    q.str('answer') ?? 'Waiting for your agent'),
            ]),
          ),
        if (f.flag('awaiting_decision'))
          RentalsSection(
            title: 'Your decision',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (f.obj('proposed') != null)
                  BodyText(
                      'Your agent suggests ${f.obj('proposed')!.str('name') ?? ''}. '
                      '${f.obj('proposed')!.str('callout') ?? ''}'),
                if (!f.flag('has_contractor'))
                  const BodyText(
                      'There is no contractor on file for this kind of work.',
                      muted: true),
                const SizedBox(height: 10),
                _ApproveDeclineRow(
                  onApprove: () => _approve(context, f),
                  onDecline: () => _decline(context),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            if (actions != null && actions.flag('show')) ...[
              if (hold == null && actions.flag('can_stop'))
                _btn(TablerIcons.player_pause, 'Stop the work',
                    () => _stop(context)),
              if (hold != null)
                _btn(TablerIcons.player_play, 'Let it carry on',
                    () => _run(context, () => _api.faultResume(widget.faultId),
                        'The work can carry on.')),
              _btn(TablerIcons.help, 'Ask your agent', () => _query(context)),
            ],
            if (selfResolved && f.obj('repair_asked') == null)
              _btn(TablerIcons.tool, 'Have it repaired anyway',
                  () => _repairAnyway(context)),
          ]),
        ),
      ],
    );
  }

  Widget _btn(IconData icon, String label, VoidCallback on) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
        icon: Icon(icon, size: 18),
        label: Text(label),
        onPressed: on,
      );

  Future<void> _run(BuildContext context, Future<Json> Function() call,
      String done) async {
    await runAction(context, call, successText: done);
    _refresh.value++;
  }

  Future<void> _approve(BuildContext context, Json f) async {
    final contractors = f.objs('contractors');
    final proposed = f.obj('proposed');
    final choice = await showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _WhoHandlesSheet(
          contractors: contractors, proposedName: proposed?.str('name')),
    );
    if (choice == null || !context.mounted) return;
    await _run(
        context,
        () => _api.faultDecision(widget.faultId, {'decision': 'approve', ...choice}),
        'Approved. Your agent has been told.');
  }

  Future<void> _decline(BuildContext context) async {
    final note = await askNote(context,
        title: 'Decline the repair', label: 'Why? (required)', minLength: 1);
    if (note == null || !context.mounted) return;
    await _run(
        context,
        () => _api.faultDecision(
            widget.faultId, {'decision': 'decline', 'note': note}),
        'Declined. Your agent has been told.');
  }

  Future<void> _stop(BuildContext context) async {
    final reason = await askNote(context,
        title: 'Stop the work?', label: 'Why? (required)', minLength: 3);
    if (reason == null || !context.mounted) return;
    await _run(context, () => _api.faultStop(widget.faultId, reason),
        'Stopped. Your agent has been told.');
  }

  Future<void> _query(BuildContext context) async {
    final note = await askNote(context,
        title: 'Ask your agent', label: 'Your question', minLength: 3);
    if (note == null || !context.mounted) return;
    await _run(context, () => _api.faultQuery(widget.faultId, note),
        'Sent to your agent.');
  }

  Future<void> _repairAnyway(BuildContext context) async {
    final c = await askNote(context,
        title: 'Have it repaired anyway?', label: 'Comment (optional)');
    if (c == null || !context.mounted) return;
    await _run(context, () => _api.repairRequest(widget.faultId, comment: c),
        'Your agent has been asked to arrange it.');
  }
}

class _WhoHandlesSheet extends StatefulWidget {
  final List<Json> contractors;
  final String? proposedName;
  const _WhoHandlesSheet({required this.contractors, this.proposedName});
  @override
  State<_WhoHandlesSheet> createState() => _WhoHandlesSheetState();
}

class _WhoHandlesSheetState extends State<_WhoHandlesSheet> {
  String? _who;
  int? _contractorId;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _valid =>
      _who != null && (_who != 'list' || _contractorId != null);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Who should do the repair?',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _who,
                onChanged: (v) => setState(() => _who = v),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (widget.proposedName != null)
                    RadioListTile<String>(
                      value: 'proposed',
                      title: Text('Yes, send ${widget.proposedName}'),
                    ),
                  if (widget.contractors.isNotEmpty)
                    const RadioListTile<String>(
                      value: 'list',
                      title: Text('A contractor from the list'),
                    ),
                  const RadioListTile<String>(
                    value: 'agency',
                    title: Text('Let my agent choose'),
                  ),
                  const RadioListTile<String>(
                    value: 'own',
                    title: Text('I will use my own contractor'),
                  ),
                ]),
              ),
              if (_who == 'list')
                RadioGroup<int>(
                  groupValue: _contractorId,
                  onChanged: (v) => setState(() => _contractorId = v),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (final c in widget.contractors)
                      RadioListTile<int>(
                        value: c.integer('id')!,
                        title: Text(c.str('name') ?? ''),
                        subtitle: c.str('phone') == null
                            ? null
                            : Text(c.str('phone')!),
                      ),
                  ]),
                ),
              if (_who == 'own') ...[
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Contractor name'),
                ),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Contractor phone'),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _note,
                maxLength: 2000,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _valid
                    ? () => Navigator.pop(context, <String, dynamic>{
                          'handled_by': _who,
                          if (_who == 'list')
                            'agency_service_provider_id': _contractorId,
                          if (_who == 'own' && _name.text.trim().isNotEmpty)
                            'contractor_name': _name.text.trim(),
                          if (_who == 'own' && _phone.text.trim().isNotEmpty)
                            'contractor_phone': _phone.text.trim(),
                          if (_note.text.trim().isNotEmpty)
                            'note': _note.text.trim(),
                        })
                    : null,
                child: const Text('Approve'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OwnerWorkOrdersScreen extends StatelessWidget {
  const OwnerWorkOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'Work orders',
      body: RentalsFutureView<Json>(
        load: _api.workOrders,
        builder: (context, d, _) {
          final rows = d.objs('work_orders');
          if (rows.isEmpty) {
            return ListView(children: const [
              RentalsEmpty(reason: 'There are no work orders to show.'),
            ]);
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final w = rows[i];
              final client = w.obj('client') ?? const {};
              return RentalsListCard(
                title: w.str('title') ?? 'Work order',
                subtitle: client.str('property_address'),
                meta: fmtMoment(client.str('appointment_at')),
                statusLabel: client.str('stage_label') ?? w.str('status'),
                statusKey: client.str('stage') ?? w.str('status'),
                highlight: w.str('owner_approval_status') == 'pending',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        OwnerWorkOrderScreen(workOrderId: w.integer('id')!))),
              );
            },
          );
        },
      ),
    );
  }
}

class OwnerWorkOrderScreen extends StatefulWidget {
  final int workOrderId;
  const OwnerWorkOrderScreen({super.key, required this.workOrderId});
  @override
  State<OwnerWorkOrderScreen> createState() => _OwnerWorkOrderScreenState();
}

class _OwnerWorkOrderScreenState extends State<OwnerWorkOrderScreen> {
  final _refresh = ValueNotifier<int>(0);

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'Work order',
      body: RentalsFutureView<Json>(
        refresh: _refresh,
        load: () => _api.workOrder(widget.workOrderId),
        builder: (context, d, _) => _body(context, d.obj('work_order') ?? d),
      ),
    );
  }

  Widget _body(BuildContext context, Json w) {
    final quote = w.obj('quote');
    final pending = w.str('owner_approval_status') == 'pending';
    final finished = w.obj('reported_finished');
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      children: [
        RentalsSection(
          title: w.str('title') ?? 'Work order',
          trailing: RentalsStatusChip(w.str('stage_label') ?? '',
              statusKey: w.str('stage')),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (w.str('description') != null) BodyText(w.str('description')!),
              const SizedBox(height: 6),
              KeyValueRow('Property', w.str('property_address')),
              KeyValueRow('Who', w.str('who_label')),
              KeyValueRow('Contractor', w.str('contractor_name')),
              KeyValueRow('Contractor phone', w.str('contractor_phone'),
                  icon: TablerIcons.phone,
                  onTap: w.str('contractor_phone') == null
                      ? null
                      : () => dialPhone(w.str('contractor_phone')!)),
              KeyValueRow('Call-out', w.str('contractor_callout')),
              KeyValueRow('Appointment', fmtMoment(w.str('appointment_at'))),
              KeyValueRow('Appointment note', w.str('appointment_note')),
              KeyValueRow('Completed', fmtMoment(w.str('completed_at'))),
              if (finished != null)
                KeyValueRow('Reported finished',
                    '${finished.str('by') ?? ''} · ${fmtMoment(finished.str('at'))}'),
              if (w.str('owner_progress_note') != null)
                BodyText(w.str('owner_progress_note')!, muted: true),
            ],
          ),
        ),
        if (quote != null)
          RentalsSection(
            title: 'Quote',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KeyValueRow('Amount', quote.str('amount')),
                KeyValueRow('Date', fmtDate(quote.str('quote_date'))),
                if (quote.str('details') != null) BodyText(quote.str('details')!),
                if (quote.str('document_url') != null)
                  KeyValueRow('Document', 'Open',
                      icon: TablerIcons.file,
                      onTap: () =>
                          _openFile(context, quote.str('document_url')!, 'quote.pdf')),
                if (pending) ...[
                  const SizedBox(height: 10),
                  _ApproveDeclineRow(
                    onApprove: () => _decide(context, 'approve', quote),
                    onDecline: () => _decide(context, 'decline', quote),
                  ),
                ],
              ],
            ),
          ),
        if (pending && quote == null)
          RentalsSection(
            title: 'Your decision',
            child: _ApproveDeclineRow(
              onApprove: () => _decide(context, 'approve', null),
              onDecline: () => _decide(context, 'decline', null),
            ),
          ),
        if (w.objs('photos').isNotEmpty)
          RentalsSection(
            title: 'Photos',
            child: RentalsPhotoGrid([
              for (final p in w.objs('photos'))
                if (p.str('url') != null) p.str('url')!,
            ]),
          ),
        if (w.objs('invoices').isNotEmpty)
          RentalsSection(
            title: 'Invoices shared with you',
            child: Column(children: [
              for (final i in w.objs('invoices'))
                KeyValueRow(i.str('invoice_number') ?? 'Invoice',
                    [fmtDate(i.str('invoice_date')), i.str('supplier')]
                        .whereType<String>()
                        .where((e) => e.isNotEmpty)
                        .join(' · '),
                    icon: TablerIcons.file,
                    onTap: i.str('view_url') == null
                        ? null
                        : () => _openFile(context, i.str('view_url')!,
                            i.str('file_name') ?? 'invoice.pdf')),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            if (w.flag('owner_can_appoint'))
              _btn(TablerIcons.calendar, 'Set the appointment',
                  () => _appointment(context)),
            if (w.flag('owner_can_start'))
              _btn(TablerIcons.player_play, 'The work has started',
                  () => _progress(context, 'started')),
            if (w.flag('owner_can_finish'))
              _btn(TablerIcons.circle_check, 'The work is finished',
                  () => _progress(context, 'finished')),
          ]),
        ),
      ],
    );
  }

  Widget _btn(IconData icon, String label, VoidCallback on) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
        icon: Icon(icon, size: 18),
        label: Text(label),
        onPressed: on,
      );

  Future<void> _openFile(BuildContext context, String url, String name) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final f = await _api.downloadDocument(url, name);
      await OpenFilex.open(f.path);
    } on RentalsApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _decide(BuildContext context, String decision, Json? quote) async {
    final note = await askNote(context,
        title: decision == 'approve' ? 'Approve this?' : 'Decline this?',
        label: decision == 'approve' ? 'Note (optional)' : 'Why? (required)',
        minLength: decision == 'decline' ? 1 : 0);
    if (note == null || !context.mounted) return;
    await runAction(
      context,
      () => _api.workOrderDecision(widget.workOrderId,
          decision: decision, note: note, quote: quote),
      successText: decision == 'approve' ? 'Approved.' : 'Declined.',
    );
    // Also after a 409 (the quote changed): reload so the new one shows.
    _refresh.value++;
  }

  Future<void> _appointment(BuildContext context) async {
    final day = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: DateTime.now(),
    );
    if (day == null || !context.mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    if (time == null || !context.mounted) return;
    final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    final note = await askNote(context,
        title: 'Appointment note', label: 'Note (optional)');
    if (note == null || !context.mounted) return;
    await runAction(
      context,
      () => _api.setAppointment(widget.workOrderId, isoWithOffset(at), note: note),
      successText: 'Appointment set.',
    );
    _refresh.value++;
  }

  Future<void> _progress(BuildContext context, String action) async {
    final note = await askNote(context,
        title: action == 'started' ? 'The work has started' : 'The work is finished',
        label: 'Note (optional)');
    if (note == null || !context.mounted) return;
    final r = await _api.workProgress(widget.workOrderId, action: action, note: note);
    if (!context.mounted) return;
    showSubmitOutcome(context, r.outcome, sentText: 'Thanks — noted.');
    _refresh.value++;
  }
}

/// "Request work / report a problem" for one of the owner's properties.
class OwnerReportFaultScreen extends StatefulWidget {
  const OwnerReportFaultScreen({super.key});
  @override
  State<OwnerReportFaultScreen> createState() => _OwnerReportFaultScreenState();
}

class _OwnerReportFaultScreenState extends State<OwnerReportFaultScreen> {
  List<Json>? _properties;
  int? _propertyId;
  List<Json> _types = const [];
  int? _typeId;
  int _maxPhotos = 6;
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _comment = TextEditingController();
  List<XFile> _photos = const [];
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadProperties();
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _loadProperties() async {
    try {
      final r = await _api.properties();
      final list = r.objs('properties');
      if (!mounted) return;
      setState(() {
        _properties = list;
        _error = null;
      });
      if (list.length == 1) _pick(list.first.integer('id'));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _pick(int? id) async {
    setState(() {
      _propertyId = id;
      _typeId = null;
      _types = const [];
    });
    if (id == null) return;
    try {
      final t = await _api.faultTypes(id);
      if (!mounted) return;
      setState(() {
        _types = t.objs('fault_types');
        _maxPhotos =
            (t.obj('limits')?.integer('max_photos') ?? 6).clamp(1, 10);
      });
    } catch (_) {
      // The type is optional; without signal the request goes untyped.
    }
  }

  @override
  Widget build(BuildContext context) {
    final props = _properties;
    return RentalsPage(
      title: 'Request work',
      body: _error != null
          ? RentalsError(error: _error!, onRetry: _loadProperties)
          : props == null
              ? const RentalsLoading()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: _propertyId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Property'),
                      items: [
                        for (final p in props)
                          DropdownMenuItem(
                              value: p.integer('id'),
                              child: Text(p.str('address') ?? '')),
                      ],
                      onChanged: _pick,
                    ),
                    const SizedBox(height: 12),
                    if (_types.isNotEmpty)
                      DropdownButtonFormField<int>(
                        initialValue: _typeId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'What needs doing? (optional)'),
                        items: [
                          for (final t in _types)
                            DropdownMenuItem(
                                value: t.integer('id'),
                                child: Text([t.str('name'), t.str('category')]
                                    .whereType<String>()
                                    .join(' · '))),
                        ],
                        onChanged: (v) => setState(() => _typeId = v),
                      ),
                    TextField(
                      controller: _title,
                      maxLength: 191,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    TextField(
                      controller: _desc,
                      maxLength: 5000,
                      minLines: 3,
                      maxLines: 8,
                      decoration: const InputDecoration(labelText: 'Details'),
                    ),
                    TextField(
                      controller: _comment,
                      maxLength: 2000,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                          labelText: 'Comment to your agent (optional)'),
                    ),
                    const SizedBox(height: 8),
                    BodyText('Photos (up to $_maxPhotos)', muted: true),
                    const SizedBox(height: 8),
                    PhotoPickerRow(
                        photos: _photos,
                        max: _maxPhotos,
                        onChanged: (p) => setState(() => _photos = p)),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _propertyId == null || _busy ? null : _submit,
                      child: const Text('Send to your agent'),
                    ),
                  ],
                ),
    );
  }

  Future<void> _submit() async {
    if (_typeId == null && _title.text.trim().isEmpty && _desc.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Choose what needs doing, or write the details.')));
      return;
    }
    setState(() => _busy = true);
    final r = await _api.ownerReportFault(
      propertyId: _propertyId!,
      faultTypeId: _typeId,
      title: _title.text.trim(),
      description: _desc.text.trim(),
      comment: _comment.text.trim(),
      photos: [for (final p in _photos) p.path],
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (showSubmitOutcome(context, r.outcome, sentText: 'Sent to your agent.')) {
      Navigator.of(context).pop();
    }
  }
}
