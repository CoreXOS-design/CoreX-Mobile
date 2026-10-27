import 'package:flutter/material.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../../services/rentals/rental_write_queue.dart';
import '../../../services/rentals/staff_rentals_api.dart';
import '../widgets/rentals_actions.dart';
import '../widgets/rentals_ui.dart';
import 'staff_faults_screens.dart';
import 'staff_lease_picker.dart';
import 'staff_maintenance_actions.dart';

final _api = StaffRentalsApi.instance;

class StaffWorkOrdersScreen extends StatelessWidget {
  final bool canAct;
  const StaffWorkOrdersScreen({super.key, required this.canAct});

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'Work orders',
      floatingActionButton: canAct
          ? FloatingActionButton.extended(
              icon: const Icon(TablerIcons.plus),
              label: const Text('New work order'),
              onPressed: () async {
                final l = await pickLease(context);
                if (l == null || !context.mounted) return;
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => StaffCreateWorkOrderScreen(
                    propertyId: l.propertyId,
                    propertyAddress: l.address,
                    leaseId: l.leaseId,
                  ),
                ));
              },
            )
          : null,
      body: Column(
        children: [
          const RentalsQueueBanner(),
          Expanded(
            child: RentalsPagedList<Json>(
              searchHint: 'Address, tenant, contractor or WO-ref',
              refresh: RentalWriteQueue.instance.sent,
              filters: const [
                ListFilter(param: 'status', label: 'Status', options: [
                  ('reported', 'Reported'),
                  ('ordered', 'Ordered'),
                  ('in_progress', 'In progress'),
                  ('completed', 'Completed'),
                  ('cancelled', 'Cancelled'),
                  ('disputed', 'Disputed'),
                ]),
                ListFilter(param: 'sort', label: 'Sort', options: [
                  ('newest', 'Newest'),
                  ('due', 'Appointment soonest'),
                  ('status', 'Status'),
                ]),
                ListFilter(param: 'date_from', label: 'Reported', options: [
                  ('__7', 'Last 7 days'),
                  ('__30', 'Last 30 days'),
                  ('__90', 'Last 90 days'),
                ]),
              ],
              fetch: (page, q) => _api.workOrders(page, resolveDateFilter(q)),
              itemBuilder: (context, w) => WorkOrderListCard(workOrder: w),
            ),
          ),
        ],
      ),
    );
  }
}

class WorkOrderListCard extends StatelessWidget {
  final Json workOrder;
  const WorkOrderListCard({super.key, required this.workOrder});

  @override
  Widget build(BuildContext context) {
    final w = workOrder;
    final appt = fmtMoment(w.str('appointment_at'));
    return RentalsListCard(
      title: '${w.str('reference') ?? ''} · ${w.str('title') ?? ''}',
      subtitle: [
        w.obj('property')?.str('address'),
        w.str('contractor') ?? w.str('who'),
      ].whereType<String>().join(' · '),
      meta: appt.isEmpty ? fmtMoment(w.str('reported_at')) : 'Booked $appt',
      statusLabel: w.str('status_label'),
      statusKey: w.str('status'),
      highlight: w.str('priority') == 'urgent',
      badges: [
        if (w.str('priority') == 'urgent')
          const RentalsStatusChip('Urgent', statusKey: 'urgent'),
        if (w.flag('archived'))
          const RentalsStatusChip('Archived', statusKey: 'cancelled'),
      ],
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            StaffWorkOrderDetailScreen(workOrderId: w.integer('id')!),
      )),
    );
  }
}

class StaffWorkOrderDetailScreen extends StatefulWidget {
  final int workOrderId;
  const StaffWorkOrderDetailScreen({super.key, required this.workOrderId});

  @override
  State<StaffWorkOrderDetailScreen> createState() =>
      _StaffWorkOrderDetailScreenState();
}

class _StaffWorkOrderDetailScreenState
    extends State<StaffWorkOrderDetailScreen> {
  final _refresh = ValueNotifier<int>(0);
  String get _group => 'work_order:${widget.workOrderId}';

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
      title: 'WO-${widget.workOrderId}',
      body: RentalsFutureView<Json>(
        refresh: _refresh,
        load: () => _api.workOrder(widget.workOrderId),
        builder: (context, w, reload) => _body(context, w),
      ),
    );
  }

  Widget _body(BuildContext context, Json w) {
    final archived = w.flag('archived');
    final status = w.str('status');
    final closed = status == 'completed' || status == 'cancelled';
    final photos = w.objs('photos');
    final quotes = w.objs('quotes');
    final invoices = w.objs('invoices');
    final supplier = w.obj('supplier');
    final faultId = w.integer('fault_report_id');

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      children: [
        RentalsQueueBanner(group: _group),
        RentalsSection(
          title: w.str('title') ?? 'Work order',
          trailing: RentalsStatusChip(w.str('status_label') ?? '',
              statusKey: status),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (archived)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: RentalsStatusChip('Archived', statusKey: 'cancelled'),
                ),
              if (w.str('description') != null) BodyText(w.str('description')!),
              const SizedBox(height: 8),
              KeyValueRow('Property', w.obj('property')?.str('address')),
              KeyValueRow('Tenant', w.str('tenant_names')),
              KeyValueRow('Priority', w.str('priority')),
              KeyValueRow('Trade', w.str('trade_type')),
              KeyValueRow('Who', w.str('who')),
              KeyValueRow('Contractor', supplier?.str('name') ?? w.str('contractor')),
              KeyValueRow('Contractor phone', w.str('contractor_phone'),
                  onTap: w.str('contractor_phone') == null
                      ? null
                      : () => dialPhone(w.str('contractor_phone')!)),
              KeyValueRow('Contractor answer', w.str('contractor_response_label')),
              KeyValueRow('Decline reason', w.str('contractor_decline_reason')),
              KeyValueRow('Appointment', fmtMoment(w.str('appointment_at'))),
              KeyValueRow('Appointment note', w.str('appointment_note')),
              KeyValueRow('Access', [
                w.str('access_contact_name'),
                w.str('access_contact_phone'),
              ].whereType<String>().join(' · ')),
              KeyValueRow('Access note', w.str('access_note')),
              KeyValueRow('Reported', fmtMoment(w.str('reported_at'))),
              KeyValueRow('Completed', fmtMoment(w.str('completed_at'))),
              KeyValueRow('Completion notes', w.str('completion_notes')),
              KeyValueRow('Paid by', w.str('paid_by')),
              // Cost keys are absent without rental_job_cards.view_costs.
              KeyValueRow('Approved amount', w.str('approved_amount')),
              KeyValueRow('Cost', w.str('cost_amount')),
              if (faultId != null)
                KeyValueRow('Fault', 'FR-$faultId',
                    icon: TablerIcons.chevron_right,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            StaffFaultDetailScreen(faultId: faultId)))),
            ],
          ),
        ),
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
        if (quotes.isNotEmpty)
          RentalsSection(
            title: 'Quotes',
            child: Column(children: [
              for (final q in quotes)
                KeyValueRow(
                    q.str('supplier') ?? 'Quote',
                    [
                      fmtDate(q.str('quote_date')),
                      if (q.flag('is_selected')) 'selected',
                      if (q.flag('declined')) 'declined',
                      q.str('amount'),
                    ].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
                    icon: closed || archived ? null : TablerIcons.dots,
                    onTap: closed || archived
                        ? null
                        : () async {
                            if (await quoteActions(context, widget.workOrderId, q)) _bump();
                          }),
            ]),
          ),
        RentalsSection(
          title: 'Invoices',
          child: invoices.isEmpty
              ? const BodyText('No invoices filed.', muted: true)
              : Column(children: [
                  for (final i in invoices)
                    KeyValueRow(
                        i.str('invoice_number') ?? 'Invoice',
                        [
                          fmtDate(i.str('invoice_date')),
                          i.str('supplier_name'),
                          i.str('amount'),
                        ].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
                        icon: archived ? null : TablerIcons.dots,
                        onTap: archived
                            ? null
                            : () async {
                                if (await invoiceActions(context, widget.workOrderId, i)) _bump();
                              }),
                ]),
        ),
        if (!archived && !closed)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (supplier != null)
                  _action(TablerIcons.phone_call, 'Record contractor\'s answer',
                      () => _sheet(context, _ContractorResponseSheet(id: widget.workOrderId))),
                _action(TablerIcons.file_invoice, 'File an invoice',
                    () => _sheet(context, _InvoiceSheet(id: widget.workOrderId))),
                _action(TablerIcons.circle_check, 'Complete',
                    () => _sheet(context, _CompleteSheet(
                        id: widget.workOrderId,
                        fromFault: faultId != null,
                        group: _group))),
              ],
            ),
          ),
        RentalsActionsSection(
          title: 'More actions',
          actions: workOrderActionButtons(
            context,
            w,
            reload: _bump,
            onArchived: () {
              if (mounted) Navigator.of(context).pop();
            },
          ),
        ),
      ],
    );
  }

  Widget _action(IconData icon, String label, VoidCallback on) =>
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
        icon: Icon(icon, size: 18),
        label: Text(label),
        onPressed: on,
      );

  Future<void> _sheet(BuildContext context, Widget sheet) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => sheet,
    );
    if (done == true) _bump();
  }

  Future<void> _addPhoto(BuildContext context) async {
    final type = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final t in const [
            ('reported', 'The problem (before)'),
            ('in_progress', 'Work in progress'),
            ('completed', 'Finished work'),
          ])
            ListTile(title: Text(t.$2), onTap: () => Navigator.pop(ctx, t.$1)),
        ]),
      ),
    );
    if (type == null || !context.mounted) return;
    final f = await PhotoPickerRow.takeOne(context);
    if (f == null || !context.mounted) return;
    final r = await _api.addWorkOrderPhoto(
        workOrderId: widget.workOrderId, photoPath: f.path, photoType: type);
    if (!context.mounted) return;
    showSubmitOutcome(context, r.outcome, sentText: 'Photo added.');
    _bump();
  }
}

class _ContractorResponseSheet extends StatefulWidget {
  final int id;
  const _ContractorResponseSheet({required this.id});
  @override
  State<_ContractorResponseSheet> createState() =>
      _ContractorResponseSheetState();
}

class _ContractorResponseSheetState extends State<_ContractorResponseSheet> {
  String? _response;
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SheetForm(
        title: 'The contractor\'s answer',
        submitLabel: 'Save',
        busy: _busy,
        onSubmit: _response == null ? null : _submit,
        children: [
          const BodyText(
              'Record what the contractor told you, on their behalf.',
              muted: true),
          const SizedBox(height: 12),
          OptionField(
            label: 'Answer',
            value: _response,
            options: const [
              ('accepted', 'Accepted the job'),
              ('declined', 'Declined the job'),
            ],
            onChanged: (v) => setState(() => _response = v),
          ),
          if (_response == 'declined')
            TextField(
              controller: _reason,
              maxLength: 1000,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
        ],
      );

  Future<void> _submit() async {
    setState(() => _busy = true);
    final res = await runAction(
        context,
        () => _api.contractorResponse(widget.id, _response!,
            reason: _reason.text.trim()),
        successText: 'Saved.');
    if (!mounted) return;
    setState(() => _busy = false);
    if (res != null) Navigator.pop(context, true);
  }
}

class _InvoiceSheet extends StatefulWidget {
  final int id;
  const _InvoiceSheet({required this.id});
  @override
  State<_InvoiceSheet> createState() => _InvoiceSheetState();
}

class _InvoiceSheetState extends State<_InvoiceSheet> {
  final _number = TextEditingController();
  final _amount = TextEditingController();
  final _supplier = TextEditingController();
  DateTime _date = DateTime.now();
  bool _share = false;
  String? _docPath;
  bool _busy = false;

  @override
  void dispose() {
    _number.dispose();
    _amount.dispose();
    _supplier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SheetForm(
        title: 'File a supplier invoice',
        submitLabel: 'File invoice',
        busy: _busy,
        onSubmit: _submit,
        children: [
          TextField(
            controller: _number,
            maxLength: 100,
            decoration: const InputDecoration(labelText: 'Invoice number'),
          ),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _supplier,
            decoration:
                const InputDecoration(labelText: 'Supplier name (optional)'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(TablerIcons.calendar),
            label: Text('Invoice date ${fmtDate(ymd(_date))}'),
            onPressed: () async {
              final d = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                  initialDate: _date);
              if (d != null) setState(() => _date = d);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Share with the owner'),
            value: _share,
            onChanged: (v) => setState(() => _share = v),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: Icon(_docPath == null ? TablerIcons.camera : TablerIcons.check),
            label: Text(_docPath == null
                ? 'Photograph the invoice'
                : 'Invoice photo attached'),
            onPressed: () async {
              final f = await PhotoPickerRow.takeOne(context);
              if (f != null) setState(() => _docPath = f.path);
            },
          ),
        ],
      );

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_number.text.trim().isEmpty ||
        double.tryParse(_amount.text.trim().replaceAll(',', '.')) == null ||
        _docPath == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Add the number, the amount and a photo of it.')));
      return;
    }
    setState(() => _busy = true);
    final res = await runAction(
      context,
      () => _api.fileInvoice(widget.id, documentPath: _docPath!, fields: {
        'invoice_number': _number.text.trim(),
        'invoice_date': ymd(_date),
        'amount': _amount.text.trim().replaceAll(',', '.'),
        if (_supplier.text.trim().isNotEmpty)
          'supplier_name': _supplier.text.trim(),
        'share_with_owner': _share,
      }),
      successText: 'Invoice filed.',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (res != null) Navigator.pop(context, true);
  }
}

class _CompleteSheet extends StatefulWidget {
  final int id;
  final bool fromFault;
  final String group;
  const _CompleteSheet(
      {required this.id, required this.fromFault, required this.group});
  @override
  State<_CompleteSheet> createState() => _CompleteSheetState();
}

class _CompleteSheetState extends State<_CompleteSheet> {
  String? _paidBy;
  final _cost = TextEditingController();
  final _notes = TextEditingController();
  final _found = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _cost.dispose();
    _notes.dispose();
    _found.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = RentalWriteQueue.instance.pendingCount(widget.group);
    return SheetForm(
      title: 'Complete the work order',
      submitLabel: 'Complete',
      busy: _busy,
      onSubmit: _submit,
      children: [
        if (pending > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: BodyText(
                '$pending photo(s) for this job are still on this phone. '
                'They must send before it can be completed.'),
          ),
        if (!widget.fromFault)
          OptionField(
            label: 'Who pays',
            value: _paidBy,
            options: const [
              ('owner', 'The owner'),
              ('tenant', 'The tenant'),
              ('deposit_deduction', 'Deducted from the deposit'),
              ('not_yet_paid', 'Not paid yet'),
            ],
            onChanged: (v) => setState(() => _paidBy = v),
          ),
        TextField(
          controller: _cost,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              labelText: 'Final cost (needed for an outside contractor)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _found,
          maxLength: 2000,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'What was found'),
        ),
        TextField(
          controller: _notes,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Completion notes'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final cost = _cost.text.trim().replaceAll(',', '.');
    final res = await runAction(
      context,
      () => _api.completeWorkOrder(widget.id, {
        if (_paidBy != null) 'paid_by': _paidBy,
        if (cost.isNotEmpty) 'cost_amount': cost,
        if (_notes.text.trim().isNotEmpty)
          'completion_notes': _notes.text.trim(),
        if (_found.text.trim().isNotEmpty) 'found_text': _found.text.trim(),
      }),
      successText: 'Work order completed.',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (res != null) Navigator.pop(context, true);
  }
}

/// Log a work order on a property. Online-only: the contract gives creation
/// no idempotency key, so it is never queued (a retry would make a second).
class StaffCreateWorkOrderScreen extends StatefulWidget {
  final int propertyId;
  final String propertyAddress;
  final int? leaseId;
  final String? initialTitle;
  final String? initialDescription;

  const StaffCreateWorkOrderScreen({
    super.key,
    required this.propertyId,
    required this.propertyAddress,
    this.leaseId,
    this.initialTitle,
    this.initialDescription,
  });

  @override
  State<StaffCreateWorkOrderScreen> createState() =>
      _StaffCreateWorkOrderScreenState();
}

class _StaffCreateWorkOrderScreenState
    extends State<StaffCreateWorkOrderScreen> {
  late final _title = TextEditingController(text: widget.initialTitle);
  late final _desc = TextEditingController(text: widget.initialDescription);
  final _trade = TextEditingController();
  String _priority = 'normal';
  String _reportedBy = 'agent_noticed';
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _trade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'New work order',
      subtitle: widget.propertyAddress,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const BodyText(
              'This needs signal: a work order is created once, straight away.',
              muted: true),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            maxLength: 191,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          TextField(
            controller: _desc,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _trade,
            maxLength: 60,
            decoration:
                const InputDecoration(labelText: 'Trade (e.g. plumbing)'),
          ),
          OptionField(
            label: 'Priority',
            value: _priority,
            options: const [
              ('low', 'Low'),
              ('normal', 'Normal'),
              ('urgent', 'Urgent'),
            ],
            onChanged: (v) => setState(() => _priority = v ?? 'normal'),
          ),
          OptionField(
            label: 'Who reported it',
            value: _reportedBy,
            options: const [
              ('agent_noticed', 'I noticed it'),
              ('tenant', 'The tenant'),
              ('owner_instructed', 'The owner'),
            ],
            onChanged: (v) =>
                setState(() => _reportedBy = v ?? 'agent_noticed'),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Create work order'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty || _desc.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add a title and a description.')));
      return;
    }
    setState(() => _busy = true);
    final res = await runAction(
      context,
      () => _api.createWorkOrder(widget.propertyId, {
        'title': _title.text.trim(),
        'description': _desc.text.trim(),
        if (_trade.text.trim().isNotEmpty) 'trade_type': _trade.text.trim(),
        'priority': _priority,
        if (widget.leaseId != null) 'lease_id': widget.leaseId,
        'reported_by_type': _reportedBy,
      }),
      successText: 'Work order created.',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    final id = res?.integer('id');
    if (id != null) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => StaffWorkOrderDetailScreen(workOrderId: id)));
    }
  }
}
