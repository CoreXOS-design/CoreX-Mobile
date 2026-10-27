import 'package:flutter/material.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../../services/rentals/rentals_http.dart';
import '../../../services/rentals/staff_rentals_api.dart';
import '../widgets/rentals_actions.dart';
import '../widgets/rentals_ui.dart';

// The web's fault, work-order and job-card actions on the phone (parity
// addendum §3: the web routes with "corex" swapped for "mobile"). The server
// answers in the web's own words; the cost authorisation's hard lock is the
// server's and its refusal is shown as is. Money is shown only where the
// server sent it (roles that may see costs).

final _api = StaffRentalsApi.instance;

abstract final class MaintenanceDeny {
  static const faultCreate = 'rfr.create';
  static const faultCancel = 'rfr.cancel';
  static const sendToOwner = 'rfr.send_to_owner';
  static const raiseWorkOrder = 'rfr.raise_work_order';
  static const recordApproval = 'rfr.record_approval';
  static const woCreate = 'rwo.create';
  static const woCancel = 'rwo.cancel';
  static const woApproval = 'rwo.record_approval';
  static const woQuotes = 'rwo.manage_quotes';
  static const woInvoices = 'rwo.manage_invoices';
  static const woCompletion = 'rwo.manage_completion';
  static const jcCreate = 'rjc.create';
  static const jcCancel = 'rjc.cancel';
  static const jcSignOff = 'rjc.sign_off';
  static const jcSendQuote = 'rjc.send_quote';
}

// ── Contractor picker ────────────────────────────────────────────────────

/// Pick one of the agency's active contractors (`agency_service_provider_id`).
Future<Json?> pickSupplier(BuildContext context) =>
    Navigator.of(context).push<Json>(MaterialPageRoute(
      builder: (_) => RentalsPage(
        title: 'Choose a contractor',
        body: RentalsPagedList<Json>(
          searchHint: 'Name, company, trade',
          fetch: _api.suppliers,
          itemBuilder: (context, s) => RentalsListCard(
            title: [s.str('name'), s.str('company')]
                .whereType<String>()
                .where((e) => e.isNotEmpty)
                .join(' · '),
            subtitle: [s.str('kind_label'), s.str('specialty')]
                .whereType<String>()
                .where((e) => e.isNotEmpty)
                .join(' · '),
            meta: [s.str('phone'), s.str('email')]
                .whereType<String>()
                .where((e) => e.isNotEmpty)
                .join(' · '),
            badges: [
              if (s.flag('is_preferred'))
                const RentalsStatusChip('Preferred', statusKey: 'done'),
            ],
            onTap: () => Navigator.of(context).pop(s),
          ),
        ),
      ),
    ));

/// The lease's owners (contact ids) for "the owner told me" records.
Future<List<(String, String)>> _owners(int? leaseId) async {
  if (leaseId == null) return const [];
  final l = await _api.lease(leaseId);
  return [
    for (final o in l.objs('owners'))
      if (o.integer('contact_id') != null)
        ('${o.integer('contact_id')}', o.str('name') ?? 'Owner'),
  ];
}

const _toldVia = <(String, String)>[
  ('phone_call', 'Phone call'),
  ('whatsapp', 'WhatsApp'),
  ('email', 'Email'),
];

/// "The owner told me": who, how, when, what they said, optional proof.
List<ActionField> _ownerToldFields(List<(String, String)> owners) => [
      ActionField('owner_contact_id', 'Which owner told you',
          kind: ActionFieldKind.choice, required: true, options: owners),
      const ActionField('told_via', 'How', kind: ActionFieldKind.choice,
          required: true, options: _toldVia),
      const ActionField('told_at', 'When', kind: ActionFieldKind.date),
      const ActionField('note', 'What the owner said',
          kind: ActionFieldKind.multiline, required: true, maxLength: 4000),
      const ActionField('proof', 'Proof (screenshot)', kind: ActionFieldKind.photo),
    ];

Future<Json> _postMaybeFiles(String path, ActionFormValues v) => v.files.isEmpty
    ? _api.act('POST', path, v.values)
    : _api.actWithFiles(path, v.values, v.files);

// ── Faults ───────────────────────────────────────────────────────────────

List<Widget> faultActionButtons(
  BuildContext context,
  Json f, {
  required VoidCallback reload,
  required VoidCallback onArchived,
  required void Function(int workOrderId) openWorkOrder,
}) {
  final id = f.integer('id')!;
  final path = '/mobile/rental-fault-reports/$id';
  final status = f.str('status');
  final archived = f.flag('archived');
  final closed = status == 'resolved' || status == 'cancelled';
  void after(Object? r) {
    if (r != null) reload();
  }

  if (archived) {
    return [
      ServerActionButton(
        icon: TablerIcons.arrow_back_up,
        label: 'Restore',
        denyKey: MaintenanceDeny.faultCreate,
        onPressed: () async => after(await runServerAction(context,
            denyKey: MaintenanceDeny.faultCreate,
            call: () => _api.act('POST', '$path/restore'))),
      ),
    ];
  }

  return [
    if (status == 'reported')
      ServerActionButton(
        icon: TablerIcons.pencil,
        label: 'Edit',
        denyKey: MaintenanceDeny.faultCreate,
        onPressed: () async => after(await showActionForm(context,
            title: 'Edit the fault report',
            denyKey: MaintenanceDeny.faultCreate,
            fields: [
              ActionField('title', 'Title',
                  required: true, maxLength: 191, initial: f.str('title')),
              ActionField('description', 'Description',
                  kind: ActionFieldKind.multiline,
                  required: true,
                  initial: f.str('description')),
            ],
            submit: (v) => _api.act('PUT', path, v.values))),
      ),
    if (!closed) ...[
      ServerActionButton(
        icon: TablerIcons.file_pencil,
        label: 'Owner version',
        denyKey: MaintenanceDeny.faultCreate,
        onPressed: () async => after(await showActionForm(context,
            title: 'What the owner will see',
            denyKey: MaintenanceDeny.faultCreate,
            intro: 'Nothing is sent to the owner yet.',
            fields: [
              ActionField('owner_title', 'Title',
                  maxLength: 191, initial: f.str('title')),
              ActionField('owner_description', 'Description',
                  kind: ActionFieldKind.multiline,
                  maxLength: 5000,
                  initial: f.str('description')),
              const ActionField('owner_agent_note', 'Your note to the owner',
                  kind: ActionFieldKind.multiline, maxLength: 3000),
            ],
            submit: (v) => _api.act('POST', '$path/owner-version', v.values))),
      ),
      ServerActionButton(
        icon: TablerIcons.send,
        label: 'Send to the owner',
        denyKey: MaintenanceDeny.sendToOwner,
        onPressed: () async => after(await runServerAction(context,
            denyKey: MaintenanceDeny.sendToOwner,
            confirmTitle: 'Send this fault to the owner to decide?',
            confirmLabel: 'Send',
            call: () => _api.act('POST', '$path/send-to-owner'))),
      ),
      ServerActionButton(
        icon: TablerIcons.user_check,
        label: 'Send to owner to authorise',
        denyKey: MaintenanceDeny.sendToOwner,
        onPressed: () async {
          final s = await pickSupplier(context);
          if (!context.mounted) return;
          after(await runServerAction(context,
              denyKey: MaintenanceDeny.sendToOwner,
              confirmTitle: 'Send to the owner to authorise?',
              confirmBody: s == null ? null : 'Contractor: ${s.str('name') ?? ''}',
              confirmLabel: 'Send',
              call: () => _api.act('POST', '$path/send-to-owner-to-authorise', {
                    if (s != null) ...{
                      'assignment_type': 'outside_supplier',
                      'agency_service_provider_id': s.integer('id'),
                    },
                  })));
        },
      ),
      ServerActionButton(
        icon: TablerIcons.eye,
        label: 'Send to inspect',
        denyKey: MaintenanceDeny.raiseWorkOrder,
        onPressed: () async {
          final s = await pickSupplier(context);
          if (s == null || !context.mounted) return;
          final r = await runServerAction(context,
              denyKey: MaintenanceDeny.raiseWorkOrder,
              confirmTitle: 'Send ${s.str('name') ?? 'the contractor'} to look first?',
              confirmLabel: 'Send',
              call: () => _api.act('POST', '$path/send-to-inspect', {
                    'assignment_type': 'outside_supplier',
                    'agency_service_provider_id': s.integer('id'),
                  }));
          _openRedirectedWorkOrder(r, openWorkOrder);
          after(r);
        },
      ),
      if (f.integer('work_order_id') == null)
        ServerActionButton(
          icon: TablerIcons.hammer,
          label: 'Raise work order (contractor)',
          denyKey: MaintenanceDeny.raiseWorkOrder,
          onPressed: () async {
            final s = await pickSupplier(context);
            if (s == null || !context.mounted) return;
            final r = await runServerAction(context,
                denyKey: MaintenanceDeny.raiseWorkOrder,
                confirmTitle: 'Raise a work order for ${s.str('name') ?? 'this contractor'}?',
                confirmLabel: 'Raise',
                call: () => _api.act('POST', '$path/raise-work-order', {
                      'assignment_type': 'outside_supplier',
                      'agency_service_provider_id': s.integer('id'),
                    }));
            _openRedirectedWorkOrder(r, openWorkOrder);
            after(r);
          },
        ),
      if (f.integer('work_order_id') == null)
        ServerActionButton(
          icon: TablerIcons.user,
          label: "Raise work order (owner's contractor)",
          denyKey: MaintenanceDeny.raiseWorkOrder,
          onPressed: () async {
            final r = await showActionForm(context,
                title: "The owner's own contractor",
                denyKey: MaintenanceDeny.raiseWorkOrder,
                fields: const [
                  ActionField('contractor_name', 'Contractor', maxLength: 191),
                  ActionField('contractor_phone', 'Phone', maxLength: 40),
                ],
                submit: (v) => _api.act('POST', '$path/raise-work-order', {
                      'assignment_type': 'owner_contractor',
                      ...v.values,
                    }));
            _openRedirectedWorkOrder(r, openWorkOrder);
            after(r);
          },
        ),
      ServerActionButton(
        icon: TablerIcons.gavel,
        label: "Owner's decision (authorise)",
        denyKey: MaintenanceDeny.recordApproval,
        onPressed: () async {
          final owners = await _ownersOrSay(context, f.integer('lease_id'));
          if (owners == null || !context.mounted) return;
          after(await showActionForm(context,
              title: "Record the owner's decision",
              denyKey: MaintenanceDeny.recordApproval,
              fields: [
                const ActionField('decision', 'The owner',
                    kind: ActionFieldKind.choice,
                    required: true,
                    options: [('authorise', 'Authorised'), ('declined', 'Declined')]),
                ..._ownerToldFields(owners),
              ],
              submit: (v) => _postMaybeFiles('$path/owner-decision', v)));
        },
      ),
      ServerActionButton(
        icon: TablerIcons.player_play,
        label: "Resume on the owner's go-ahead",
        denyKey: MaintenanceDeny.recordApproval,
        onPressed: () async {
          final owners = await _ownersOrSay(context, f.integer('lease_id'));
          if (owners == null || !context.mounted) return;
          after(await showActionForm(context,
              title: "Resume on the owner's go-ahead",
              denyKey: MaintenanceDeny.recordApproval,
              fields: _ownerToldFields(owners),
              submit: (v) => _postMaybeFiles('$path/resume', v)));
        },
      ),
      ServerActionButton(
        icon: TablerIcons.message_circle,
        label: 'Confirmed with the tenant',
        denyKey: MaintenanceDeny.faultCreate,
        onPressed: () async => after(await showActionForm(context,
            title: 'Confirmed with the tenant',
            denyKey: MaintenanceDeny.faultCreate,
            fields: const [
              ActionField('via', 'How',
                  kind: ActionFieldKind.choice,
                  required: true,
                  options: [..._toldVia, ('in_person', 'In person')]),
              ActionField('at', 'When', kind: ActionFieldKind.date, required: true),
              ActionField('note', 'Note',
                  kind: ActionFieldKind.multiline, maxLength: 2000),
            ],
            submit: (v) => _api.act('POST', '$path/tenant-confirmation', v.values))),
      ),
      ServerActionButton(
        icon: TablerIcons.category,
        label: 'Change the type',
        denyKey: MaintenanceDeny.faultCreate,
        onPressed: () async {
          final propertyId = f.obj('property')?.integer('id');
          Json types;
          try {
            types = await _api.faultTypes(propertyId: propertyId);
          } on RentalsApiException catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(refusalText(e))));
            }
            return;
          }
          if (!context.mounted) return;
          after(await showActionForm(context,
              title: 'Change the type',
              denyKey: MaintenanceDeny.faultCreate,
              fields: [
                ActionField('rental_fault_type_id', 'Type',
                    kind: ActionFieldKind.choice,
                    required: true,
                    options: [
                      for (final t in types.objs('data'))
                        if (t.integer('id') != null)
                          ('${t.integer('id')}', t.str('name') ?? ''),
                    ]),
              ],
              submit: (v) => _api.act('POST', '$path/reclassify', v.values)));
        },
      ),
      ServerActionButton(
        icon: TablerIcons.x,
        label: 'Cancel',
        denyKey: MaintenanceDeny.faultCancel,
        danger: true,
        onPressed: () async => after(await showActionForm(context,
            title: 'Cancel this fault report',
            denyKey: MaintenanceDeny.faultCancel,
            fields: const [
              ActionField('cancel_reason', 'Why is it cancelled?',
                  kind: ActionFieldKind.multiline, required: true, maxLength: 500),
            ],
            submit: (v) => _api.act('POST', '$path/cancel', v.values))),
      ),
    ],
    if (f.str('outcome') == 'resolved_by_first_aid')
      ServerActionButton(
        icon: TablerIcons.tool,
        label: 'Repair it anyway',
        denyKey: MaintenanceDeny.faultCreate,
        onPressed: () async => after(await runServerAction(context,
            denyKey: MaintenanceDeny.faultCreate,
            confirmTitle: 'Make a repair request from this report?',
            confirmLabel: 'Make it',
            call: () => _api.act('POST', '$path/repair-anyway'))),
      ),
    ServerActionButton(
      icon: TablerIcons.archive,
      label: 'Archive',
      denyKey: MaintenanceDeny.faultCreate,
      danger: true,
      onPressed: () async {
        final r = await runServerAction(context,
            denyKey: MaintenanceDeny.faultCreate,
            confirmTitle: 'Archive this fault report?',
            confirmBody: 'It leaves the lists. Nothing is deleted.',
            confirmLabel: 'Archive',
            call: () => _api.act('DELETE', path));
        if (r != null) onArchived();
      },
    ),
  ];
}

Future<List<(String, String)>?> _ownersOrSay(BuildContext context, int? leaseId) async {
  try {
    final owners = await _owners(leaseId);
    if (owners.isNotEmpty) return owners;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No owner is linked to this tenancy, so this is '
              'recorded on the web.')));
    }
  } on RentalsApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(refusalText(e))));
    }
  }
  return null;
}

/// The web answers a raise / send-to-inspect with the page it opened; when
/// that is a work order, open it.
void _openRedirectedWorkOrder(Json? r, void Function(int) open) {
  final redirect = r?.str('redirect');
  if (redirect == null || !redirect.contains('/rental-work-orders/')) return;
  final id = idFromRedirect(redirect);
  if (id != null) open(id);
}

// ── Work orders ──────────────────────────────────────────────────────────

List<Widget> workOrderActionButtons(
  BuildContext context,
  Json w, {
  required VoidCallback reload,
  required VoidCallback onArchived,
}) {
  final id = w.integer('id')!;
  final path = '/mobile/rental-work-orders/$id';
  final status = w.str('status');
  final archived = w.flag('archived');
  final closed = status == 'completed' || status == 'cancelled';
  void after(Object? r) {
    if (r != null) reload();
  }

  if (archived) {
    return [
      ServerActionButton(
        icon: TablerIcons.arrow_back_up,
        label: 'Restore',
        denyKey: MaintenanceDeny.woCreate,
        onPressed: () async => after(await runServerAction(context,
            denyKey: MaintenanceDeny.woCreate,
            call: () => _api.act('POST', '$path/restore'))),
      ),
    ];
  }

  return [
    if (!closed) ...[
      ServerActionButton(
        icon: TablerIcons.user_plus,
        label: w.obj('supplier') == null ? 'Assign contractor' : 'Change contractor',
        denyKey: MaintenanceDeny.woCreate,
        onPressed: () async {
          final s = await pickSupplier(context);
          if (s == null || !context.mounted) return;
          final r = await runServerAction(context,
              denyKey: MaintenanceDeny.woCreate,
              confirmTitle: 'Appoint ${s.str('name') ?? 'this contractor'}?',
              confirmBody: 'They get the job and their own link.',
              confirmLabel: 'Appoint',
              call: () => _api.act('POST', '/mobile/work-orders/$id/assign-supplier', {
                    'agency_service_provider_id': s.integer('id'),
                  }));
          if (r != null && r['contractor_emailed'] == false && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Appointed. The contractor has no email on file, '
                    'so send them the work order yourself.')));
          }
          after(r);
        },
      ),
      ServerActionButton(
        icon: TablerIcons.calendar_event,
        label: 'Appointment',
        denyKey: MaintenanceDeny.woCreate,
        onPressed: () async => after(await showActionForm(context,
            title: 'Appointment',
            denyKey: MaintenanceDeny.woCreate,
            fields: const [
              ActionField('date', 'Date', kind: ActionFieldKind.date, required: true),
              ActionField('time', 'Time', kind: ActionFieldKind.time, required: true),
              ActionField('appointment_note', 'Note for the tenant',
                  kind: ActionFieldKind.multiline, maxLength: 500),
              ActionField('appointment_contractor_note', 'Note for the contractor',
                  kind: ActionFieldKind.multiline, maxLength: 500),
            ],
            submit: (v) {
              final m = Map<String, dynamic>.of(v.values);
              final at = '${m.remove('date')} ${m.remove('time')}';
              return _api.act('POST', '$path/appointment', {'appointment_at': at, ...m});
            })),
      ),
      ServerActionButton(
        icon: TablerIcons.key,
        label: 'Access details',
        denyKey: MaintenanceDeny.woCreate,
        onPressed: () async => after(await showActionForm(context,
            title: 'Access details',
            denyKey: MaintenanceDeny.woCreate,
            fields: [
              ActionField('access_contact_name', 'Contact',
                  maxLength: 191, initial: w.str('access_contact_name')),
              ActionField('access_contact_phone', 'Phone',
                  maxLength: 50, initial: w.str('access_contact_phone')),
              ActionField('access_note', 'Note',
                  kind: ActionFieldKind.multiline,
                  maxLength: 2000,
                  initial: w.str('access_note')),
            ],
            submit: (v) => _api.act('POST', '$path/access-contact', v.values))),
      ),
      if (status == 'ordered')
        ServerActionButton(
          icon: TablerIcons.player_play,
          label: 'Mark in progress',
          denyKey: MaintenanceDeny.woCreate,
          onPressed: () async => after(await runServerAction(context,
              denyKey: MaintenanceDeny.woCreate,
              call: () => _api.act('POST', '$path/start-progress'))),
        ),
      ServerActionButton(
        icon: TablerIcons.note,
        label: 'Add a note',
        denyKey: MaintenanceDeny.woCreate,
        onPressed: () async => after(await showActionForm(context,
            title: 'Add a note',
            denyKey: MaintenanceDeny.woCreate,
            fields: const [
              ActionField('note', 'Note', kind: ActionFieldKind.multiline, required: true),
            ],
            submit: (v) => _api.act('POST', '$path/notes', v.values))),
      ),
      ServerActionButton(
        icon: TablerIcons.file_dollar,
        label: 'Add a quote',
        denyKey: MaintenanceDeny.woQuotes,
        onPressed: () async {
          final s = await pickSupplier(context);
          if (s == null || !context.mounted) return;
          after(await showActionForm(context,
              title: 'Quote from ${s.str('name') ?? 'the contractor'}',
              denyKey: MaintenanceDeny.woQuotes,
              fields: const [
                ActionField('amount', 'Amount', kind: ActionFieldKind.number, required: true),
                ActionField('quote_date', 'Quote date',
                    kind: ActionFieldKind.date, required: true),
                ActionField('detail_text', 'Detail',
                    kind: ActionFieldKind.multiline, maxLength: 2000),
                ActionField('quoted_by_phone', 'Quoted by phone',
                    kind: ActionFieldKind.toggle),
                ActionField('document', 'Photo of the quote', kind: ActionFieldKind.photo),
              ],
              submit: (v) => _postMaybeFiles('$path/quotes', ActionFormValues(
                  {...v.values, 'agency_service_provider_id': s.integer('id')},
                  v.files))));
        },
      ),
      ServerActionButton(
        icon: TablerIcons.shield_check,
        label: 'Authorise the cost',
        denyKey: MaintenanceDeny.woApproval,
        onPressed: () async => after(await showActionForm(context,
            title: 'Authorise the cost',
            denyKey: MaintenanceDeny.woApproval,
            intro: 'The work may not go over the amount authorised.',
            fields: const [
              ActionField('typed_amount', 'Authorised up to',
                  kind: ActionFieldKind.number, required: true),
            ],
            submit: (v) => _api.act('POST', '$path/cost/authorise', v.values))),
      ),
      ServerActionButton(
        icon: TablerIcons.gavel,
        label: "Owner's cost decision",
        denyKey: MaintenanceDeny.woApproval,
        onPressed: () async {
          final owners = await _ownersOrSay(context, w.integer('lease_id'));
          if (owners == null || !context.mounted) return;
          after(await showActionForm(context,
              title: "Record the owner's cost decision",
              denyKey: MaintenanceDeny.woApproval,
              fields: [
                const ActionField('decision', 'The owner',
                    kind: ActionFieldKind.choice,
                    required: true,
                    options: [('approved', 'Approved'), ('declined', 'Declined')]),
                const ActionField('approved_up_to', 'Approved up to',
                    kind: ActionFieldKind.number),
                ..._ownerToldFields(owners),
              ],
              submit: (v) => _postMaybeFiles('$path/cost/owner-decision', v)));
        },
      ),
      ServerActionButton(
        icon: TablerIcons.phone_check,
        label: 'Use what the owner said on the call',
        denyKey: MaintenanceDeny.woApproval,
        onPressed: () async => after(await runServerAction(context,
            denyKey: MaintenanceDeny.woApproval,
            confirmTitle: "Authorise the cost on the owner's call?",
            confirmLabel: 'Authorise',
            call: () => _api.act('POST', '$path/cost/use-same-call'))),
      ),
      ServerActionButton(
        icon: TablerIcons.clipboard_check,
        label: 'Contractor says done',
        denyKey: MaintenanceDeny.woCompletion,
        onPressed: () async => after(await showActionForm(context,
            title: 'The contractor says the work is done',
            denyKey: MaintenanceDeny.woCompletion,
            fields: const [
              ActionField('reported_via', 'How they told you',
                  kind: ActionFieldKind.choice,
                  required: true,
                  options: [
                    ('phone', 'Phone'),
                    ('whatsapp', 'WhatsApp'),
                    ('email', 'Email'),
                    ('in_person', 'In person'),
                    ('other', 'Other'),
                  ]),
              ActionField('date_done', 'Date done', kind: ActionFieldKind.date),
              ActionField('note', 'Note', kind: ActionFieldKind.multiline, maxLength: 2000),
              ActionField('photos[0]', 'Photo', kind: ActionFieldKind.photo),
            ],
            submit: (v) => _postMaybeFiles('$path/contractor-done', v))),
      ),
      ServerActionButton(
        icon: TablerIcons.arrow_back,
        label: 'Send back to the contractor',
        denyKey: MaintenanceDeny.woCompletion,
        onPressed: () async => after(await runServerAction(context,
            denyKey: MaintenanceDeny.woCompletion,
            confirmTitle: 'Send the job back to the contractor?',
            confirmLabel: 'Send back',
            call: () => _api.act('POST', '$path/send-back'))),
      ),
      if (status == 'disputed')
        ServerActionButton(
          icon: TablerIcons.eye_check,
          label: 'Seen — nothing reopened',
          denyKey: MaintenanceDeny.woCompletion,
          onPressed: () async => after(await runServerAction(context,
              denyKey: MaintenanceDeny.woCompletion,
              call: () => _api.act('POST', '$path/dispute-seen'))),
        ),
      if (w.integer('fault_report_id') != null) ...[
        ServerActionButton(
          icon: TablerIcons.search,
          label: 'What was found',
          denyKey: MaintenanceDeny.woCompletion,
          onPressed: () async => after(await showActionForm(context,
              title: 'What was found',
              denyKey: MaintenanceDeny.woCompletion,
              fields: const [
                ActionField('found_text', 'Found',
                    kind: ActionFieldKind.multiline, maxLength: 2000),
                ActionField('cause_note', 'Cause',
                    kind: ActionFieldKind.multiline, maxLength: 500),
              ],
              submit: (v) => _api.act('POST', '$path/who-pays/findings', v.values))),
        ),
        ServerActionButton(
          icon: TablerIcons.scale,
          label: 'Who pays',
          denyKey: MaintenanceDeny.woCompletion,
          onPressed: () async => after(await showActionForm(context,
              title: 'Who pays',
              denyKey: MaintenanceDeny.woCompletion,
              fields: const [
                ActionField('payer', 'Who pays',
                    kind: ActionFieldKind.choice,
                    required: true,
                    options: [
                      ('owner', 'The owner'),
                      ('tenant', 'The tenant'),
                      ('shared', 'Shared'),
                      ('insurance_body_corporate', 'Insurance / body corporate'),
                    ]),
                ActionField('tenant_percent', "Tenant's share (%) when shared",
                    kind: ActionFieldKind.number),
                ActionField('reason', 'Reason',
                    kind: ActionFieldKind.multiline, required: true, maxLength: 2000),
                ActionField('evidence', 'Evidence', kind: ActionFieldKind.photo),
              ],
              submit: (v) => _postMaybeFiles('$path/who-pays/rule', v))),
        ),
      ],
      if (w.integer('job_card_id') == null)
        ServerActionButton(
          icon: TablerIcons.clipboard_list,
          label: 'Create job card',
          denyKey: MaintenanceDeny.jcCreate,
          onPressed: () async {
            final r = await showActionForm(context,
                title: 'Create a job card',
                denyKey: MaintenanceDeny.jcCreate,
                fields: [
                  ActionField('title', 'Title',
                      required: true, maxLength: 191, initial: w.str('title')),
                ],
                submit: (v) => _api.act('POST', '/mobile/rental-job-cards', {
                      'rental_work_order_id': id,
                      ...v.values,
                    }));
            final jc = idFromRedirect(r?.str('redirect'));
            if (jc != null && context.mounted) {
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => StaffJobCardScreen(jobCardId: jc)));
            }
            after(r);
          },
        ),
      ServerActionButton(
        icon: TablerIcons.x,
        label: 'Cancel',
        denyKey: MaintenanceDeny.woCancel,
        danger: true,
        onPressed: () async => after(await showActionForm(context,
            title: 'Cancel this work order',
            denyKey: MaintenanceDeny.woCancel,
            fields: const [
              ActionField('cancel_reason', 'Why is it cancelled?',
                  kind: ActionFieldKind.multiline, required: true, maxLength: 500),
            ],
            submit: (v) => _api.act('POST', '$path/cancel', v.values))),
      ),
    ],
    ServerActionButton(
      icon: TablerIcons.archive,
      label: 'Archive',
      denyKey: MaintenanceDeny.woCreate,
      danger: true,
      onPressed: () async {
        final r = await runServerAction(context,
            denyKey: MaintenanceDeny.woCreate,
            confirmTitle: 'Archive this work order?',
            confirmBody: 'It leaves the lists. Nothing is deleted.',
            confirmLabel: 'Archive',
            call: () => _api.act('DELETE', path));
        if (r != null) onArchived();
      },
    ),
  ];
}

/// A quote's menu on the work order: select, archive.
Future<bool> quoteActions(BuildContext context, int workOrderId, Json q) async {
  final id = q.integer('id');
  if (id == null) return false;
  final path = '/mobile/rental-work-orders/$workOrderId/quotes/$id';
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (!q.flag('is_selected'))
          ListTile(
              leading: const Icon(TablerIcons.circle_check),
              title: const Text('Select this quote'),
              onTap: () => Navigator.pop(ctx, 'select')),
        ListTile(
            leading: const Icon(TablerIcons.archive),
            title: const Text('Archive this quote'),
            onTap: () => Navigator.pop(ctx, 'archive')),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return false;
  final r = await runServerAction(context,
      denyKey: choice == 'select' ? MaintenanceDeny.woApproval : MaintenanceDeny.woQuotes,
      call: () => choice == 'select'
          ? _api.act('POST', '$path/select')
          : _api.act('DELETE', path));
  return r != null;
}

/// An invoice's menu: share with the owner (or stop), archive.
Future<bool> invoiceActions(BuildContext context, int workOrderId, Json i) async {
  final id = i.integer('id');
  if (id == null) return false;
  final path = '/mobile/rental-work-orders/$workOrderId/invoices/$id';
  final shared = i.flag('share_with_owner');
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
            leading: Icon(shared ? TablerIcons.eye_off : TablerIcons.eye),
            title: Text(shared ? 'Stop sharing with the owner' : 'Share with the owner'),
            onTap: () => Navigator.pop(ctx, 'share')),
        ListTile(
            leading: const Icon(TablerIcons.archive),
            title: const Text('Archive this invoice'),
            onTap: () => Navigator.pop(ctx, 'archive')),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return false;
  final r = await runServerAction(context,
      denyKey: MaintenanceDeny.woInvoices,
      call: () => choice == 'share'
          ? _api.act('POST', '$path/share', {'share_with_owner': !shared})
          : _api.act('DELETE', path));
  return r != null;
}

// ── Job cards ────────────────────────────────────────────────────────────

/// The web job-card list. Rows carry no money.
class StaffJobCardsScreen extends StatelessWidget {
  const StaffJobCardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'Job cards',
      body: RentalsPagedList<Json>(
        searchHint: 'Title, property, tenant, JC-number',
        filters: const [
          ListFilter(param: 'status', label: 'Status', options: [
            ('draft', 'Draft'),
            ('quoted', 'Quoted'),
            ('approved', 'Approved'),
            ('scheduled', 'Scheduled'),
            ('in_progress', 'In progress'),
            ('disputed', 'Disputed'),
            ('completed', 'Completed'),
            ('cancelled', 'Cancelled'),
          ]),
          ListFilter(param: 'overdue', label: 'Overdue', options: [('1', 'Overdue')]),
          ListFilter(param: 'needs_pricing', label: 'Needs pricing', options: [('1', 'Needs pricing')]),
          ListFilter(param: 'archived', label: 'Archived', options: [('1', 'Archived')]),
        ],
        fetch: _api.jobCards,
        itemBuilder: (context, j) => RentalsListCard(
          title: j.str('title') ?? 'Job card',
          subtitle: [j.str('property_address'), j.str('tenant_names')]
              .whereType<String>()
              .where((e) => e.isNotEmpty)
              .join(' · '),
          meta: [j.obj('crew')?.str('name'), fmtMoment(j.str('scheduled_at'))]
              .whereType<String>()
              .where((e) => e.isNotEmpty)
              .join(' · '),
          statusLabel: displayValue(j.str('status')),
          statusKey: j.str('status'),
          onTap: j.integer('id') == null
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => StaffJobCardScreen(jobCardId: j.integer('id')!))),
        ),
      ),
    );
  }
}

/// One job card: tasks, lines, photos (money only where the server sent it)
/// and the web's job-card actions.
class StaffJobCardScreen extends StatefulWidget {
  final int jobCardId;
  const StaffJobCardScreen({super.key, required this.jobCardId});

  @override
  State<StaffJobCardScreen> createState() => _StaffJobCardScreenState();
}

class _StaffJobCardScreenState extends State<StaffJobCardScreen> {
  final _refresh = ValueNotifier<int>(0);

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  void _reload() => _refresh.value++;

  String get _path => '/mobile/rental-job-cards/${widget.jobCardId}';

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'JC-${widget.jobCardId}',
      body: RentalsFutureView<Json>(
        refresh: _refresh,
        load: () => _api.jobCard(widget.jobCardId),
        builder: (context, j, reload) => _body(context, j),
      ),
    );
  }

  Widget _body(BuildContext context, Json j) {
    final status = j.str('status');
    final closed = status == 'completed' || status == 'cancelled';
    void after(Object? r) {
      if (r != null) _reload();
    }

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      children: [
        RentalsSection(
          title: j.str('title') ?? 'Job card',
          trailing: RentalsStatusChip(displayValue(status), statusKey: status),
          child: Column(children: [
            KeyValueRow('Property', j.str('property_address')),
            KeyValueRow('Tenant', j.str('tenant_names')),
            KeyValueRow('Crew', j.obj('crew')?.str('name')),
            KeyValueRow('Assigned to', j.obj('assigned_user')?.str('name')),
            KeyValueRow('Scheduled', fmtMoment(j.str('scheduled_at'))),
            KeyValueRow('Due', fmtMoment(j.str('due_at'))),
            KeyValueRow('Access', j.str('access_notes')),
            // Present only for roles that may see costs.
            if (j.containsKey('total_amount')) KeyValueRow('Total', j.str('total_amount')),
          ]),
        ),
        RentalsSection(
          title: 'Tasks',
          trailing: closed
              ? null
              : RentalsSectionAction(
                  icon: TablerIcons.plus,
                  tooltip: 'Add a task',
                  onPressed: () async => after(await showActionForm(context,
                      title: 'Add a task',
                      denyKey: MaintenanceDeny.jcCreate,
                      fields: const [
                        ActionField('description', 'Task', required: true, maxLength: 500),
                      ],
                      submit: (v) => _api.act('POST', '$_path/tasks', v.values))),
                ),
          child: Column(children: [
            if (j.objs('tasks').isEmpty) const BodyText('No tasks.', muted: true),
            for (final t in j.objs('tasks'))
              RentalsNavRow(
                icon: t.flag('is_done') ? TablerIcons.circle_check : TablerIcons.circle,
                title: t.str('description') ?? '',
                onTap: closed || t.integer('id') == null
                    ? null
                    : () async => after(await showActionForm(context,
                        title: 'Rename the task',
                        denyKey: MaintenanceDeny.jcCreate,
                        fields: [
                          ActionField('description', 'Task',
                              required: true, maxLength: 500, initial: t.str('description')),
                        ],
                        submit: (v) =>
                            _api.act('PUT', '$_path/tasks/${t.integer('id')}', v.values))),
              ),
          ]),
        ),
        RentalsSection(
          title: 'Labour and parts',
          trailing: closed
              ? null
              : RentalsSectionAction(
                  icon: TablerIcons.plus,
                  tooltip: 'Add a line',
                  onPressed: () async => after(await showActionForm(context,
                      title: 'Add a line',
                      denyKey: MaintenanceDeny.jcCreate,
                      fields: const [
                        ActionField('type', 'Type',
                            kind: ActionFieldKind.choice,
                            required: true,
                            options: [('labour', 'Labour'), ('part', 'Part')]),
                        ActionField('description', 'Description',
                            required: true, maxLength: 255),
                        ActionField('quantity', 'Quantity',
                            kind: ActionFieldKind.number, required: true),
                        ActionField('unit', 'Unit', maxLength: 30),
                      ],
                      submit: (v) => _api.act('POST', '$_path/lines', v.values))),
                ),
          child: Column(children: [
            if (j.objs('lines').isEmpty) const BodyText('No lines.', muted: true),
            for (final l in j.objs('lines'))
              KeyValueRow(
                [l['quantity']?.toString(), l.str('unit'), l.str('description')]
                    .whereType<String>()
                    .where((e) => e.isNotEmpty)
                    .join(' '),
                l.containsKey('line_total') ? l.str('line_total') : displayValue(l.str('type')),
                icon: closed ? null : TablerIcons.archive,
                onTap: closed || l.integer('id') == null
                    ? null
                    : () async => after(await runServerAction(context,
                        denyKey: MaintenanceDeny.jcCreate,
                        confirmTitle: 'Archive this line?',
                        confirmLabel: 'Archive',
                        call: () => _api.act('DELETE', '$_path/lines/${l.integer('id')}'))),
              ),
          ]),
        ),
        if (j.objs('photos').isNotEmpty)
          RentalsSection(
            title: 'Photos',
            child: RentalsPhotoGrid(
              [for (final p in j.objs('photos')) if (p.str('url') != null) p.str('url')!],
              emptyText: null,
            ),
          ),
        RentalsActionsSection(actions: [
          if (!closed) ...[
            ServerActionButton(
              icon: TablerIcons.calendar_event,
              label: 'Schedule',
              denyKey: MaintenanceDeny.jcCreate,
              onPressed: () async => after(await showActionForm(context,
                  title: 'Schedule',
                  denyKey: MaintenanceDeny.jcCreate,
                  fields: const [
                    ActionField('scheduled_at', 'Scheduled', kind: ActionFieldKind.date),
                    ActionField('due_at', 'Due', kind: ActionFieldKind.date),
                  ],
                  submit: (v) => _api.act('POST', '$_path/schedule', v.values))),
            ),
            ServerActionButton(
              icon: TablerIcons.player_play,
              label: 'Mark in progress',
              denyKey: MaintenanceDeny.jcCreate,
              onPressed: () async => after(await runServerAction(context,
                  denyKey: MaintenanceDeny.jcCreate,
                  call: () => _api.act('POST', '$_path/start'))),
            ),
            ServerActionButton(
              icon: TablerIcons.send,
              label: 'Send quote to the owner',
              denyKey: MaintenanceDeny.jcSendQuote,
              onPressed: () async => after(await runServerAction(context,
                  denyKey: MaintenanceDeny.jcSendQuote,
                  confirmTitle: 'Send the quote to the owner?',
                  confirmLabel: 'Send',
                  call: () => _api.act('POST', '$_path/send-quote'))),
            ),
            ServerActionButton(
              icon: TablerIcons.user_check,
              label: 'Worker sign-off',
              denyKey: MaintenanceDeny.jcSignOff,
              onPressed: () async => after(await showActionForm(context,
                  title: 'Worker sign-off',
                  denyKey: MaintenanceDeny.jcSignOff,
                  fields: const [
                    ActionField('worker_sign_off_name', 'Worker', maxLength: 191),
                  ],
                  submit: (v) => _api.act('POST', '$_path/worker-sign-off', v.values))),
            ),
            ServerActionButton(
              icon: TablerIcons.signature,
              label: 'Agent sign-off',
              denyKey: MaintenanceDeny.jcSignOff,
              onPressed: () async => after(await runServerAction(context,
                  denyKey: MaintenanceDeny.jcSignOff,
                  confirmTitle: 'Sign off this job card?',
                  confirmLabel: 'Sign off',
                  call: () => _api.act('POST', '$_path/agent-sign-off'))),
            ),
            ServerActionButton(
              icon: TablerIcons.home_check,
              label: 'Tenant confirmed',
              denyKey: MaintenanceDeny.jcSignOff,
              onPressed: () async => after(await showActionForm(context,
                  title: 'The tenant confirmed the work',
                  denyKey: MaintenanceDeny.jcSignOff,
                  fields: const [
                    ActionField('tenant_confirmation_note', 'Note',
                        kind: ActionFieldKind.multiline, maxLength: 1000),
                  ],
                  submit: (v) => _api.act('POST', '$_path/tenant-confirm', v.values))),
            ),
            ServerActionButton(
              icon: TablerIcons.circle_check,
              label: 'Complete',
              denyKey: MaintenanceDeny.jcSignOff,
              onPressed: () async => after(await showActionForm(context,
                  title: 'Complete the job card',
                  denyKey: MaintenanceDeny.jcSignOff,
                  fields: const [
                    ActionField('paid_by', 'Paid by',
                        kind: ActionFieldKind.choice,
                        options: [
                          ('owner', 'The owner'),
                          ('tenant', 'The tenant'),
                          ('deposit_deduction', 'Deducted from the deposit'),
                          ('not_yet_paid', 'Not yet paid'),
                        ]),
                  ],
                  submit: (v) => _api.act('POST', '$_path/complete', v.values))),
            ),
            ServerActionButton(
              icon: TablerIcons.x,
              label: 'Cancel',
              denyKey: MaintenanceDeny.jcCancel,
              danger: true,
              onPressed: () async => after(await showActionForm(context,
                  title: 'Cancel this job card',
                  denyKey: MaintenanceDeny.jcCancel,
                  fields: const [
                    ActionField('cancel_reason', 'Why is it cancelled?',
                        kind: ActionFieldKind.multiline, required: true, maxLength: 500),
                  ],
                  submit: (v) => _api.act('POST', '$_path/cancel', v.values))),
            ),
          ],
          ServerActionButton(
            icon: TablerIcons.archive,
            label: 'Archive',
            denyKey: MaintenanceDeny.jcCreate,
            danger: true,
            onPressed: () async {
              final r = await runServerAction(context,
                  denyKey: MaintenanceDeny.jcCreate,
                  confirmTitle: 'Archive this job card?',
                  confirmLabel: 'Archive',
                  call: () => _api.act('DELETE', _path));
              if (r != null && context.mounted) Navigator.of(context).pop();
            },
          ),
        ]),
      ],
    );
  }
}
