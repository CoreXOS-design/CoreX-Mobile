import 'package:flutter/material.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../../services/rentals/staff_rentals_api.dart';
import '../widgets/rentals_actions.dart';
import 'staff_inspection_actions.dart';

// The web Lease Hub's actions on the phone (parity addendum §3). The server
// answers with the web's own sentence and, where the lease still exists, the
// refreshed lease file. No money is shown or edited on these screens, and a
// received notice is never rejected (Johan): it is accepted or acted on.

final _api = StaffRentalsApi.instance;

abstract final class LeaseDeny {
  static const create = 'leases.create';
  static const cancel = 'leases.cancel';
  static const renew = 'leases.renew';
  static const noticeTerms = 'lease_notice_terms.edit';
  static const review = 'rental_notices.review';
}

/// The lease file's Actions section. [reload] re-reads the lease;
/// [onArchived] leaves the screen.
List<Widget> leaseActionButtons(
  BuildContext context,
  Json l, {
  required VoidCallback reload,
  required VoidCallback onArchived,
}) {
  final id = l.integer('id')!;
  final path = '/mobile/leases/$id';
  final status = l.str('status');
  final can = l.obj('can') ?? const {};
  final signing = l.obj('signing');
  final renewal = l.obj('renewal');
  final notStarted = status == 'draft' || status == 'signed_awaiting_start';
  final live = status == 'draft' || status == 'active';
  void after(Object? r) {
    if (r != null) reload();
  }

  return [
    ServerActionButton(
      icon: TablerIcons.calendar_plus,
      label: 'Schedule an inspection',
      denyKey: InspectionDeny.schedule,
      onPressed: () => scheduleInspection(context, leaseId: id),
    ),
    ServerActionButton(
      icon: TablerIcons.calendar_event,
      label: 'Load an interim date',
      denyKey: InspectionDeny.plannedDates,
      onPressed: () => addPlannedDate(context, id),
    ),
    if (can.flag('review_notices'))
      ServerActionButton(
        icon: TablerIcons.file_text,
        label: 'Record a notice given',
        denyKey: LeaseDeny.review,
        onPressed: () async => after(await recordNoticeCase(context, id)),
      ),
    if (can.flag('review_notices') && renewal?.str('expiry_notice_sent_at') == null) ...[
      ServerActionButton(
        icon: TablerIcons.send,
        label: 'Send the expiry notice',
        denyKey: LeaseDeny.review,
        onPressed: () async => after(await runServerAction(context,
            denyKey: LeaseDeny.review,
            confirmTitle: 'Send the lease expiry notice to the tenant?',
            confirmLabel: 'Send',
            call: () => _api.act('POST', '$path/expiry-notice/send'))),
      ),
      ServerActionButton(
        icon: TablerIcons.hand_finger,
        label: 'Expiry notice given by hand',
        denyKey: LeaseDeny.review,
        onPressed: () async => after(await showActionForm(context,
            title: 'The expiry notice was given another way',
            denyKey: LeaseDeny.review,
            fields: const [
              ActionField('note', 'How was it given?',
                  kind: ActionFieldKind.multiline, maxLength: 500),
            ],
            submit: (v) => _api.act('POST', '$path/expiry-notice/mark-given', v.values))),
      ),
    ],
    if (live)
      ServerActionButton(
        icon: TablerIcons.pencil,
        label: 'Edit lease',
        denyKey: LeaseDeny.create,
        onPressed: () async => after(await showActionForm(context,
            title: 'Edit lease',
            denyKey: LeaseDeny.create,
            fields: [
              ActionField('end_date', 'End date',
                  kind: ActionFieldKind.date, initial: l.str('end_date')),
              ActionField('lease_type', 'Lease type',
                  initial: l.str('lease_type'), maxLength: 40),
            ],
            submit: (v) => _api.act('PUT', path, v.values))),
      ),
    ServerActionButton(
      icon: TablerIcons.clock_hour_4,
      label: 'Notice terms',
      denyKey: LeaseDeny.noticeTerms,
      onPressed: () async => after(await editNoticeTerms(context, id)),
    ),
    ServerActionButton(
      icon: TablerIcons.check,
      label: 'Confirm notice terms',
      denyKey: LeaseDeny.noticeTerms,
      onPressed: () async => after(await runServerAction(context,
          denyKey: LeaseDeny.noticeTerms,
          call: () => _api.act('POST', '$path/notice-terms/confirm'))),
    ),
    if (notStarted && signing?.str('status') != 'signed')
      ServerActionButton(
        icon: TablerIcons.writing_sign,
        label: 'Prepare for signing',
        denyKey: LeaseDeny.create,
        onPressed: () async => after(await runServerAction(context,
            denyKey: LeaseDeny.create,
            confirmTitle: 'Prepare the lease agreement for signing?',
            confirmBody: 'Nothing is sent to anyone yet.',
            confirmLabel: 'Prepare',
            call: () => _api.act('POST',
                signing?.objs('signers').isNotEmpty == true
                    ? '$path/signing/prepare-again'
                    : '$path/signing/prepare'))),
      ),
    if (notStarted)
      ServerActionButton(
        icon: TablerIcons.file_upload,
        label: 'Signed paper copy',
        denyKey: LeaseDeny.create,
        onPressed: () async => after(await showActionForm(context,
            title: 'Attach the signed paper copy',
            denyKey: LeaseDeny.create,
            fields: const [
              ActionField('signed_document', 'Photo of the signed lease',
                  kind: ActionFieldKind.photo, required: true),
            ],
            submit: (v) =>
                _api.actWithFiles('$path/signing/signed-copy', const {}, v.files))),
      ),
    if (notStarted)
      ServerActionButton(
        icon: TablerIcons.player_play,
        label: 'Activate',
        denyKey: LeaseDeny.create,
        onPressed: () async => after(await runServerAction(context,
            denyKey: LeaseDeny.create,
            confirmTitle: 'Activate this lease?',
            confirmLabel: 'Activate',
            call: () => _api.act('POST', '$path/activate'))),
      ),
    if (renewal?.flag('has_renewal_in_progress') == true)
      ServerActionButton(
        icon: TablerIcons.x,
        label: 'Cancel renewal draft',
        denyKey: LeaseDeny.renew,
        danger: true,
        onPressed: () async => after(await showActionForm(context,
            title: 'Cancel the renewal draft',
            denyKey: LeaseDeny.renew,
            fields: const [
              ActionField('cancel_reason', 'Why?',
                  kind: ActionFieldKind.multiline, required: true, maxLength: 500),
            ],
            submit: (v) => _api.act('POST', '$path/renewal/cancel-draft', v.values))),
      ),
    if (live)
      ServerActionButton(
        icon: TablerIcons.ban,
        label: 'Cancel lease',
        denyKey: LeaseDeny.cancel,
        danger: true,
        onPressed: () async => after(await showActionForm(context,
            title: 'Cancel this lease',
            denyKey: LeaseDeny.cancel,
            fields: const [
              ActionField('cancel_reason', 'Why is it cancelled?',
                  kind: ActionFieldKind.multiline, required: true, maxLength: 500),
            ],
            submit: (v) => _api.act('POST', '$path/cancel', v.values))),
      ),
    ServerActionButton(
      icon: TablerIcons.archive,
      label: 'Archive',
      denyKey: LeaseDeny.create,
      danger: true,
      onPressed: () async {
        final r = await showActionForm(context,
            title: 'Archive this lease',
            denyKey: LeaseDeny.create,
            fields: const [
              ActionField('archive_reason', 'Why is it archived?',
                  kind: ActionFieldKind.multiline, required: true, maxLength: 500),
            ],
            submit: (v) => _api.act('POST', '$path/archive', v.values));
        if (r != null) onArchived();
      },
    ),
  ];
}

/// The agent records a notice the tenant or the landlord gave; it then
/// waits for review.
Future<Json?> recordNoticeCase(BuildContext context, int leaseId) =>
    showActionForm(context,
        title: 'Record a notice given',
        denyKey: LeaseDeny.review,
        intro: 'It waits for review; nothing goes to the other party yet.',
        fields: const [
          ActionField('given_by', 'Given by',
              kind: ActionFieldKind.choice,
              required: true,
              options: [('tenant', 'The tenant'), ('landlord', 'The landlord')]),
          ActionField('notice_date', 'Date notice was given',
              kind: ActionFieldKind.date, required: true),
          ActionField('intended_end_date', 'Move-out date',
              kind: ActionFieldKind.date, required: true),
          ActionField('reason', 'Reason',
              kind: ActionFieldKind.multiline, maxLength: 2000),
          ActionField('attachment', 'Photo of the notice', kind: ActionFieldKind.photo),
        ],
        submit: (v) => v.files.isEmpty
            ? _api.act('POST', '/mobile/leases/$leaseId/notice-cases', v.values)
            : _api.actWithFiles(
                '/mobile/leases/$leaseId/notice-cases', v.values, v.files));

Future<Json?> editNoticeTerms(BuildContext context, int leaseId) => showActionForm(
      context,
      title: 'Notice terms',
      denyKey: LeaseDeny.noticeTerms,
      fields: const [
        ActionField('notice_period', 'Notice period', kind: ActionFieldKind.number),
        ActionField('notice_period_unit', 'Unit',
            kind: ActionFieldKind.choice,
            options: [('days', 'Days'), ('weeks', 'Weeks'), ('months', 'Months')]),
        ActionField('earliest_notice_date', 'Earliest notice date',
            kind: ActionFieldKind.date),
        ActionField('earliest_termination_date', 'Earliest termination date',
            kind: ActionFieldKind.date),
        ActionField('early_cancellation_allowed', 'Early cancellation allowed',
            kind: ActionFieldKind.choice, options: [('yes', 'Yes'), ('no', 'No')]),
        ActionField('early_cancellation_notice', 'Early cancellation notice',
            kind: ActionFieldKind.number),
        ActionField('early_cancellation_notice_unit', 'Unit',
            kind: ActionFieldKind.choice,
            options: [('days', 'Days'), ('weeks', 'Weeks'), ('months', 'Months')]),
        ActionField('early_cancellation_penalty', 'Early cancellation penalty',
            kind: ActionFieldKind.multiline, maxLength: 2000),
        ActionField('notice_reason', 'Why are they changing? (needed once signed)',
            kind: ActionFieldKind.multiline, maxLength: 300),
      ],
      submit: (v) {
        final notice = Map<String, dynamic>.of(v.values)..remove('notice_reason');
        return _api.act('PUT', '/mobile/leases/$leaseId/notice-terms', {
          'notice': notice,
          if (v.values['notice_reason'] != null) 'notice_reason': v.values['notice_reason'],
        });
      },
    );

// ── Received notices (the "Notices to review" list) ──────────────────────

/// A received notice's menu. Accepting it puts the move-out date on the
/// lease; there is no reject (an agency acts on a notice, it never refuses
/// it).
Future<bool> receivedNoticeActions(BuildContext context, Json n,
    {required VoidCallback openLease}) async {
  final id = n.integer('id');
  if (id == null) return false;
  final received = n.str('status') == 'received';
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
            leading: const Icon(TablerIcons.file_text),
            title: const Text('Open the lease'),
            onTap: () => Navigator.pop(ctx, 'lease')),
        if (received) ...[
          ListTile(
              leading: const Icon(TablerIcons.circle_check),
              title: const Text('Accept the notice'),
              onTap: () => Navigator.pop(ctx, 'accept')),
          ListTile(
              leading: const Icon(TablerIcons.pencil),
              title: const Text('Correct the dates or reason'),
              onTap: () => Navigator.pop(ctx, 'edit')),
        ],
        ListTile(
            leading: const Icon(TablerIcons.archive),
            title: const Text('Archive'),
            onTap: () => Navigator.pop(ctx, 'archive')),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return false;
  Json? r;
  if (choice == 'lease') {
    openLease();
    return false;
  } else if (choice == 'accept') {
    r = await showActionForm(context,
        title: 'Accept the notice',
        denyKey: LeaseDeny.review,
        intro: 'The move-out date goes on the lease and the other party is told.',
        fields: [
          ActionField('end_date', 'Move-out date',
              kind: ActionFieldKind.date,
              required: true,
              initial: n.str('intended_end_date')),
          const ActionField('notice_outcome', 'What happens to the property?',
              kind: ActionFieldKind.choice,
              required: true,
              options: [
                ('readvertise',
                    'Put back on the market, available from the day after move-out'),
                ('withdraw',
                    'Withdraw the property (landlord is taking it back / property is lost)'),
                ('leave', 'Leave as is for now'),
              ]),
          const ActionField('show_available_from_on_portals',
              'Show available-from date on portals',
              kind: ActionFieldKind.toggle),
          const ActionField('note', 'Note (needed if you change the date)',
              kind: ActionFieldKind.multiline, maxLength: 1000),
        ],
        submit: (v) =>
            _api.act('POST', '/mobile/rental-notices/$id/accept', v.values));
  } else if (choice == 'edit') {
    r = await showActionForm(context,
        title: 'Correct the notice',
        denyKey: LeaseDeny.review,
        fields: [
          ActionField('notice_date', 'Date notice was given',
              kind: ActionFieldKind.date, required: true, initial: n.str('notice_date')),
          ActionField('intended_end_date', 'Move-out date',
              kind: ActionFieldKind.date,
              required: true,
              initial: n.str('intended_end_date')),
          ActionField('reason', 'Reason',
              kind: ActionFieldKind.multiline, maxLength: 2000, initial: n.str('reason')),
        ],
        submit: (v) => _api.act('PUT', '/mobile/lease-notices/$id', v.values));
  } else {
    r = await runServerAction(context,
        denyKey: LeaseDeny.review,
        confirmTitle: 'Archive this notice?',
        confirmLabel: 'Archive',
        call: () => _api.act('POST', '/mobile/lease-notices/$id/archive'));
  }
  return r != null;
}
