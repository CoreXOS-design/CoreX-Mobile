import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../../services/rentals/rental_write_queue.dart';
import '../../../services/rentals/staff_rentals_api.dart';
import '../widgets/rentals_actions.dart';
import '../widgets/rentals_ui.dart';
import 'staff_lease_picker.dart';
import 'staff_maintenance_actions.dart';
import 'staff_work_orders_screens.dart';

final _api = StaffRentalsApi.instance;

/// Staff fault list: search, status / urgency / date filters, 25 per page.
class StaffFaultsScreen extends StatelessWidget {
  final bool canAct;
  const StaffFaultsScreen({super.key, required this.canAct});

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'Faults',
      floatingActionButton: canAct
          ? FloatingActionButton.extended(
              icon: const Icon(TablerIcons.plus),
              label: const Text('Report a fault'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const StaffReportFaultScreen())),
            )
          : null,
      body: Column(
        children: [
          const RentalsQueueBanner(),
          Expanded(
            child: RentalsPagedList<Json>(
              searchHint: 'Address, tenant, fault type or FR-ref',
              refresh: RentalWriteQueue.instance.sent,
              filters: const [
                ListFilter(param: 'status', label: 'Status', options: [
                  ('reported', 'Reported'),
                  ('under_review', 'Under review'),
                  ('awaiting_approval', 'Awaiting approval'),
                  ('approved', 'Approved'),
                  ('declined', 'Declined'),
                  ('work_order_raised', 'Work order raised'),
                  ('owner_handling', 'Owner handling'),
                  ('resolved', 'Resolved'),
                  ('cancelled', 'Cancelled'),
                ]),
                ListFilter(param: 'urgency', label: 'Urgency', options: [
                  ('emergency', 'Emergency'),
                  ('urgent', 'Urgent'),
                  ('routine', 'Routine'),
                ]),
                ListFilter(param: 'sort', label: 'Sort', options: [
                  ('newest', 'Newest'),
                  ('oldest', 'Oldest'),
                  ('status', 'Status'),
                  ('property', 'Property'),
                ]),
                ListFilter(param: 'date_from', label: 'Reported', options: [
                  ('__7', 'Last 7 days'),
                  ('__30', 'Last 30 days'),
                  ('__90', 'Last 90 days'),
                ]),
              ],
              fetch: (page, q) => _api.faultReports(page, resolveDateFilter(q)),
              itemBuilder: (context, f) => FaultListCard(fault: f),
            ),
          ),
        ],
      ),
    );
  }
}

/// `date_from=__N` is the list's shorthand for "the last N days"; the server
/// only ever sees a real date.
Map<String, String> resolveDateFilter(Map<String, String> q) {
  final v = q['date_from'];
  if (v == null || !v.startsWith('__')) return q;
  final days = int.tryParse(v.substring(2)) ?? 30;
  return {
    ...q,
    'date_from': ymd(DateTime.now().subtract(Duration(days: days))),
  };
}

class FaultListCard extends StatelessWidget {
  final Json fault;
  const FaultListCard({super.key, required this.fault});

  @override
  Widget build(BuildContext context) {
    final property = fault.obj('property');
    final emergency = fault.flag('is_emergency');
    return RentalsListCard(
      title: '${fault.str('reference') ?? ''} · ${fault.str('title') ?? ''}',
      subtitle: [
        property?.str('address'),
        fault.str('tenant_names'),
      ].whereType<String>().join(' · '),
      meta: fmtMoment(fault.str('reported_at')),
      statusLabel: fault.str('status_label'),
      statusKey: fault.str('status'),
      highlight: emergency,
      badges: [
        if (emergency)
          const RentalsStatusChip('Emergency',
              statusKey: 'emergency', icon: TablerIcons.alert_octagon),
        if (fault.str('fault_type') != null)
          RentalsStatusChip(fault.str('fault_type')!, statusKey: 'type'),
        if (fault.flag('archived'))
          const RentalsStatusChip('Archived', statusKey: 'cancelled'),
      ],
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => StaffFaultDetailScreen(faultId: fault.integer('id')!),
      )),
    );
  }
}

/// One fault: photos, timeline, owner decision, work order; actions to add a
/// photo, record the owner's decision and set the outcome.
class StaffFaultDetailScreen extends StatefulWidget {
  final int faultId;
  const StaffFaultDetailScreen({super.key, required this.faultId});

  @override
  State<StaffFaultDetailScreen> createState() => _StaffFaultDetailScreenState();
}

class _StaffFaultDetailScreenState extends State<StaffFaultDetailScreen> {
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
      title: 'FR-${widget.faultId}',
      body: RentalsFutureView<Json>(
        refresh: _refresh,
        load: () => _api.faultReport(widget.faultId),
        builder: (context, f, reload) => _body(context, f),
      ),
    );
  }

  Widget _body(BuildContext context, Json f) {
    final property = f.obj('property');
    final type = f.obj('fault_type_detail');
    final wo = f.obj('work_order');
    final archived = f.flag('archived');
    final closed = f.str('status') == 'resolved' || f.str('status') == 'cancelled';
    final approvals = f.objs('approvals');
    final photos = f.objs('photos');
    final timeline = f.objs('timeline');

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      children: [
        RentalsQueueBanner(group: 'fault:${widget.faultId}'),
        RentalsSection(
          title: f.str('title') ?? 'Fault',
          trailing: RentalsStatusChip(f.str('status_label') ?? '',
              statusKey: f.str('status')),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (f.flag('is_emergency'))
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: RentalsStatusChip('Emergency',
                      statusKey: 'emergency',
                      icon: TablerIcons.alert_octagon),
                ),
              if (archived)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: RentalsStatusChip('Archived', statusKey: 'cancelled'),
                ),
              if (f.str('description') != null) BodyText(f.str('description')!),
              const SizedBox(height: 8),
              KeyValueRow('Property', property?.str('address')),
              KeyValueRow('Tenant', f.str('tenant_names')),
              KeyValueRow('Fault type', type?.str('name')),
              KeyValueRow('Category', type?.str('category')),
              KeyValueRow('Urgency', type?.str('urgency')),
              KeyValueRow('Reported', fmtMoment(f.str('reported_at'))),
              KeyValueRow('Reported by', f.str('reported_by')),
              KeyValueRow('Outcome', f.str('outcome')),
              KeyValueRow('Outcome note', f.str('outcome_note')),
              KeyValueRow('Repaired', fmtDate(f.str('repaired_at'))),
              KeyValueRow('Cancel reason', f.str('cancel_reason')),
            ],
          ),
        ),
        if (timeline.isNotEmpty)
          RentalsSection(title: 'Progress', child: RentalsTimeline(timeline)),
        RentalsSection(
          title: 'Photos',
          trailing: archived || closed
              ? null
              : TextButton.icon(
                  style: TextButton.styleFrom(minimumSize: const Size(0, 32)),
                  icon: const Icon(TablerIcons.camera_plus, size: 16),
                  label: const Text('Add'),
                  onPressed: () => _addPhoto(context),
                ),
          child: RentalsPhotoGrid([
            for (final p in photos)
              if (p.str('url') != null) p.str('url')!,
          ]),
        ),
        RentalsSection(
          title: 'Owner decision',
          child: approvals.isEmpty
              ? BodyText(
                  'No decision recorded. '
                  '(${f.str('owner_approval_status') ?? 'not required'})',
                  muted: true)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final a in approvals) ...[
                      KeyValueRow('Decision', a.str('decision')),
                      KeyValueRow('Route', a.str('approval_route')),
                      KeyValueRow('Evidence', a.str('evidence_type')),
                      KeyValueRow('Note', a.str('evidence_text')),
                      KeyValueRow('Decided', fmtMoment(a.str('decided_at'))),
                      KeyValueRow('Recorded by', a.str('recorded_by')),
                      KeyValueRow('Contractor', a.str('contractor_name')),
                      KeyValueRow('Contractor phone', a.str('contractor_phone'),
                          onTap: a.str('contractor_phone') == null
                              ? null
                              : () => dialPhone(a.str('contractor_phone')!)),
                      const Divider(),
                    ],
                  ],
                ),
        ),
        if (wo != null)
          RentalsSection(
            title: 'Work order',
            child: KeyValueRow(
              wo.str('reference') ?? 'Work order',
              wo.str('status_label'),
              icon: TablerIcons.chevron_right,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    StaffWorkOrderDetailScreen(workOrderId: wo.integer('id')!),
              )),
            ),
          ),
        if (!archived && !closed)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (approvals.isEmpty && wo == null)
                  _action(context, TablerIcons.gavel, 'Record owner decision',
                      () => _recordApproval(context, f)),
                _action(context, TablerIcons.circle_check, 'Set outcome',
                    () => _setOutcome(context)),
                // Raising a work order from the fault is the web's own action
                // (More actions below), so it stays linked to this fault.
              ],
            ),
          ),
        RentalsActionsSection(
          title: 'More actions',
          actions: faultActionButtons(
            context,
            f,
            reload: _bump,
            onArchived: () {
              if (mounted) Navigator.of(context).pop();
            },
            openWorkOrder: (id) => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => StaffWorkOrderDetailScreen(workOrderId: id))),
          ),
        ),
      ],
    );
  }

  Widget _action(
          BuildContext context, IconData icon, String label, VoidCallback on) =>
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
        icon: Icon(icon, size: 18),
        label: Text(label),
        onPressed: on,
      );

  Future<void> _addPhoto(BuildContext context) async {
    final f = await PhotoPickerRow.takeOne(context);
    if (f == null || !context.mounted) return;
    final r = await _api.addFaultPhoto(
      faultRef: '${widget.faultId}',
      photoPath: f.path,
      label: 'Photo for FR-${widget.faultId}',
    );
    if (!context.mounted) return;
    showSubmitOutcome(context, r.outcome, sentText: 'Photo added.');
    _bump();
  }

  Future<void> _recordApproval(BuildContext context, Json fault) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ApprovalSheet(faultId: widget.faultId),
    );
    if (done == true) _bump();
  }

  Future<void> _setOutcome(BuildContext context) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OutcomeSheet(faultId: widget.faultId),
    );
    if (done == true) _bump();
  }
}

/// Bottom-sheet form wrapper with keyboard padding and a submit button.
class SheetForm extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final String submitLabel;
  final bool busy;
  final VoidCallback? onSubmit;

  const SheetForm({
    super.key,
    required this.title,
    required this.children,
    required this.submitLabel,
    required this.busy,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ...children,
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: busy ? null : onSubmit,
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(submitLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A labelled dropdown over `(value, label)` options.
class OptionField extends StatelessWidget {
  final String label;
  final String? value;
  final List<(String, String)> options;
  final ValueChanged<String?> onChanged;
  const OptionField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final o in options)
              DropdownMenuItem(value: o.$1, child: Text(o.$2)),
          ],
          onChanged: onChanged,
        ),
      );
}

class _ApprovalSheet extends StatefulWidget {
  final int faultId;
  const _ApprovalSheet({required this.faultId});
  @override
  State<_ApprovalSheet> createState() => _ApprovalSheetState();
}

class _ApprovalSheetState extends State<_ApprovalSheet> {
  String? _decision;
  String? _route;
  String? _evidence;
  final _text = TextEditingController();
  final _contractor = TextEditingController();
  final _contractorPhone = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    _contractor.dispose();
    _contractorPhone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SheetForm(
      title: 'Record the owner\'s decision',
      submitLabel: 'Save decision',
      busy: _busy,
      onSubmit: _decision == null || _evidence == null ? null : _submit,
      children: [
        const BodyText(
            'What the owner told you (WhatsApp, email or by phone). One '
            'decision is recorded per fault.',
            muted: true),
        const SizedBox(height: 12),
        OptionField(
          label: 'Decision',
          value: _decision,
          options: const [('approved', 'Approved'), ('declined', 'Declined')],
          onChanged: (v) => setState(() => _decision = v),
        ),
        if (_decision == 'approved')
          OptionField(
            label: 'Who appoints the contractor',
            value: _route,
            options: const [
              ('owner_handles', 'The owner handles it'),
              ('agency_appoints', 'The agency appoints'),
            ],
            onChanged: (v) => setState(() => _route = v),
          ),
        OptionField(
          label: 'How the owner told you',
          value: _evidence,
          options: const [
            ('whatsapp', 'WhatsApp'),
            ('email', 'Email'),
            ('verbal_note', 'Phone / in person'),
          ],
          onChanged: (v) => setState(() => _evidence = v),
        ),
        TextField(
          controller: _text,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
              labelText: _decision == 'declined'
                  ? 'Reason the owner gave'
                  : 'What the owner said'),
        ),
        if (_decision == 'approved' && _route == 'owner_handles') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _contractor,
            decoration:
                const InputDecoration(labelText: 'Owner\'s contractor (optional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contractorPhone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
                labelText: 'Contractor phone (optional)'),
          ),
        ],
        if (_decision == 'approved' && _route == 'agency_appoints')
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: BodyText(
                'Choose the agency contractor on the web for now — the app '
                'has no contractor list to pick from yet.',
                muted: true),
          ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final res = await runAction(
      context,
      () => _api.recordApproval(widget.faultId, {
        'decision': _decision,
        if (_route != null) 'approval_route': _route,
        'evidence_type': _evidence,
        'evidence_text': _text.text.trim(),
        if (_contractor.text.trim().isNotEmpty)
          'contractor_name': _contractor.text.trim(),
        if (_contractorPhone.text.trim().isNotEmpty)
          'contractor_phone': _contractorPhone.text.trim(),
      }),
      successText: 'Decision recorded.',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (res != null) Navigator.pop(context, true);
  }
}

class _OutcomeSheet extends StatefulWidget {
  final int faultId;
  const _OutcomeSheet({required this.faultId});
  @override
  State<_OutcomeSheet> createState() => _OutcomeSheetState();
}

class _OutcomeSheetState extends State<_OutcomeSheet> {
  String? _outcome;
  DateTime? _repairedAt;
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _needsDate =>
      _outcome == 'repaired' || _outcome == 'repaired_partially';

  @override
  Widget build(BuildContext context) {
    return SheetForm(
      title: 'Close the fault',
      submitLabel: 'Save outcome',
      busy: _busy,
      onSubmit: _outcome == null ? null : _submit,
      children: [
        OptionField(
          label: 'Outcome',
          value: _outcome,
          options: const [
            ('repaired', 'Repaired'),
            ('repaired_partially', 'Partly repaired'),
            ('not_repaired', 'Not repaired'),
            ('owner_declined', 'Owner declined'),
            ('tenant_liable', 'Tenant liable'),
            ('resolved_by_first_aid', 'Resolved by first aid'),
          ],
          onChanged: (v) => setState(() => _outcome = v),
        ),
        if (_needsDate)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(TablerIcons.calendar),
              label: Text(_repairedAt == null
                  ? 'When was it repaired?'
                  : 'Repaired ${fmtDate(ymd(_repairedAt!))}'),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                  initialDate: DateTime.now(),
                );
                if (d != null) setState(() => _repairedAt = d);
              },
            ),
          ),
        TextField(
          controller: _note,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Note'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final res = await runAction(
      context,
      () => _api.setOutcome(widget.faultId, {
        'outcome': _outcome,
        if (_note.text.trim().isNotEmpty) 'outcome_note': _note.text.trim(),
        if (_repairedAt != null) 'repaired_at': ymd(_repairedAt!),
      }),
      successText: 'Fault closed.',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (res != null) Navigator.pop(context, true);
  }
}

/// Staff report-a-fault. Works offline: the report and its photos are queued
/// with one idempotency key each and send themselves when there is signal.
class StaffReportFaultScreen extends StatefulWidget {
  final PickedLease? lease;
  const StaffReportFaultScreen({super.key, this.lease});

  @override
  State<StaffReportFaultScreen> createState() => _StaffReportFaultScreenState();
}

class _StaffReportFaultScreenState extends State<StaffReportFaultScreen> {
  PickedLease? _lease;
  List<Json> _types = const [];
  String? _typeId;
  String _reportedBy = 'agent_noticed';
  String _channel = 'app';
  final _title = TextEditingController();
  final _desc = TextEditingController();
  List<XFile> _photos = const [];
  bool _busy = false;
  bool _typesFailed = false;

  @override
  void initState() {
    super.initState();
    _lease = widget.lease;
    if (_lease != null) _loadTypes();
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    setState(() => _typesFailed = false);
    try {
      final r = await _api.faultTypes(propertyId: _lease!.propertyId);
      if (!mounted) return;
      setState(() {
        _types = r.objs('data');
        final other = r.obj('other_option');
        if (other != null) {
          _types = [..._types, {...other, 'is_other': true}];
        }
      });
    } catch (_) {
      // Offline: the report can still go without a type (it is then
      // classified on the web).
      if (mounted) setState(() => _typesFailed = true);
    }
  }

  Json? get _selectedType {
    for (final t in _types) {
      if (t['id']?.toString() == _typeId) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final type = _selectedType;
    return RentalsPage(
      title: 'Report a fault',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 52), alignment: Alignment.centerLeft),
            icon: const Icon(TablerIcons.home),
            label: Text(_lease == null
                ? 'Choose the property / tenancy'
                : '${_lease!.address}${_lease!.tenantNames.isEmpty ? '' : ' · ${_lease!.tenantNames}'}'),
            onPressed: () async {
              final l = await pickLease(context);
              if (l == null) return;
              setState(() {
                _lease = l;
                _typeId = null;
                _types = const [];
              });
              _loadTypes();
            },
          ),
          const SizedBox(height: 12),
          if (_lease != null && _types.isNotEmpty)
            OptionField(
              label: 'Fault type',
              value: _typeId,
              options: [
                for (final t in _types)
                  (
                    t['id'].toString(),
                    [t.str('name'), t.str('category')]
                        .whereType<String>()
                        .join(' · ')
                  ),
              ],
              onChanged: (v) => setState(() => _typeId = v),
            ),
          if (_typesFailed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  const Expanded(
                    child: BodyText(
                        'Fault types could not load (no signal?). You can '
                        'still report it; the type is set on the web.',
                        muted: true),
                  ),
                  TextButton(onPressed: _loadTypes, child: const Text('Retry')),
                ],
              ),
            ),
          if (type != null && (type.str('first_aid_steps') != null ||
              type.objs('steps').isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: RentalsSection(
                padding: EdgeInsets.zero,
                title: 'First aid',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (type.str('safety_line') != null)
                      BodyText(type.str('safety_line')!),
                    if (type.objs('steps').isEmpty &&
                        type.str('first_aid_steps') != null)
                      BodyText(type.str('first_aid_steps')!),
                    for (final s in type.objs('steps'))
                      BodyText('• ${s.str('text') ?? s.str('label') ?? ''}'),
                  ],
                ),
              ),
            ),
          TextField(
            controller: _title,
            maxLength: 191,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          TextField(
            controller: _desc,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(labelText: 'What is wrong?'),
          ),
          const SizedBox(height: 12),
          OptionField(
            label: 'Who reported it',
            value: _reportedBy,
            options: const [
              ('agent_noticed', 'I noticed it'),
              ('tenant', 'The tenant'),
              ('owner_instructed', 'The owner'),
            ],
            onChanged: (v) => setState(() => _reportedBy = v ?? 'agent_noticed'),
          ),
          OptionField(
            label: 'How it reached you',
            value: _channel,
            options: const [
              ('app', 'In the app / on site'),
              ('phone', 'Phone'),
              ('whatsapp', 'WhatsApp'),
              ('email', 'Email'),
              ('in_person', 'In person'),
              ('other', 'Other'),
            ],
            onChanged: (v) => setState(() => _channel = v ?? 'app'),
          ),
          const SizedBox(height: 4),
          const BodyText('Photos', muted: true),
          const SizedBox(height: 8),
          PhotoPickerRow(
              photos: _photos, onChanged: (p) => setState(() => _photos = p)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Report fault'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_lease == null) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Choose the property first.')));
      return;
    }
    if (_title.text.trim().isEmpty || _desc.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Add a title and say what is wrong.')));
      return;
    }
    setState(() => _busy = true);
    final r = await _api.reportFault(
      propertyId: _lease!.propertyId,
      leaseId: _lease!.leaseId,
      title: _title.text.trim(),
      description: _desc.text.trim(),
      faultTypeId: _typeId,
      reportedByType: _reportedBy,
      reportedChannel: _channel,
    );
    // Photos ride on the report's queue id, so they go after it even when the
    // report itself is still waiting for signal.
    final sent = r.outcome is SubmitSent
        ? (r.outcome as SubmitSent).body.integer('id')
        : null;
    if (r.outcome is! SubmitRefused && r.outcome is! SubmitArchived) {
      for (var i = 0; i < _photos.length; i++) {
        await _api.addFaultPhoto(
          faultRef: sent != null ? '$sent' : '{ref:${r.id}}',
          dependsOn: sent != null ? null : r.id,
          photoPath: _photos[i].path,
          label: 'Photo ${i + 1} for "${_title.text.trim()}"',
        );
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final ok = showSubmitOutcome(context, r.outcome, sentText: 'Fault reported.');
    if (!ok) return;
    if (sent != null) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => StaffFaultDetailScreen(faultId: sent)));
    } else {
      Navigator.of(context).pop();
    }
  }
}
