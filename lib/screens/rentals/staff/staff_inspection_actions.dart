import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../../services/rentals/rentals_http.dart';
import '../../../services/rentals/staff_rentals_api.dart';
import '../widgets/rentals_actions.dart';
import '../widgets/rentals_ui.dart';
import '../widgets/signature_pad.dart';
import 'staff_inspections_screens.dart';

// The web inspection screen's actions on the phone (parity addendum §1 and
// the web-action routes): lifecycle, signing, outputs, planned dates and the
// checklist. Every answer is the server's; nothing is decided here. "Edit
// report" (reopen) is office-only and deliberately absent.

final _api = StaffRentalsApi.instance;

const _base = '/mobile/rental-inspections';

/// Permission-keyed names for [RentalsDenied], so a 403 hides the button.
abstract final class InspectionDeny {
  static const schedule = 'ri.create';
  static const reschedule = 'ri.reschedule';
  static const cancel = 'ri.cancel';
  static const archive = 'ri.archive';
  static const publicLink = 'ri.public_link';
  static const details = 'ri.edit_details';
  static const attendance = 'ri.record_attendance';
  static const plannedDates = 'ri.manage_planned_dates';
  static const followUp = 'rfr.create';
}

/// The four types as the web's picker names them (`RentalInspection::TYPE_PICKER`).
const kInspectionTypes = <(String, String)>[
  ('in', 'In'),
  ('ad_hoc', 'Routine'),
  ('interim', 'Interim'),
  ('out', 'Out'),
];

void _openInspection(BuildContext context, Json d) {
  final id = d.integer('id');
  if (id == null) return;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => StaffInspectionScreen(
      inspectionId: id,
      propertyId: d.obj('property')?.integer('id') ?? 0,
      title: d.obj('property')?.str('address') ?? 'Inspection',
      initialDetail: d.containsKey('checklist') ? d : null,
    ),
  ));
}

// ── Schedule (from a lease / a due row) ──────────────────────────────────

/// "Schedule" on the New-inspection form: books it for a date; the server
/// notifies the parties and says when it is under the agency's notice.
Future<void> scheduleInspection(
  BuildContext context, {
  required int leaseId,
  String? type,
  int? plannedDateId,
}) async {
  final body = await showActionForm(
    context,
    title: 'Schedule an inspection',
    denyKey: InspectionDeny.schedule,
    successText: 'Inspection scheduled.',
    fields: [
      ActionField('type', 'Type',
          kind: ActionFieldKind.choice,
          required: true,
          initial: type,
          options: kInspectionTypes),
      const ActionField('scheduled_for', 'Date',
          kind: ActionFieldKind.date, required: true),
      const ActionField('scheduled_time', 'Time', kind: ActionFieldKind.time),
      const ActionField('scheduled_duration_minutes', 'Duration (minutes)',
          kind: ActionFieldKind.number),
      const ActionField('schedule_note', 'Note',
          kind: ActionFieldKind.multiline, maxLength: 1000),
    ],
    submit: (v) => _api.act('POST', '$_base/schedule', {
      'lease_id': leaseId,
      if (plannedDateId != null) 'planned_date_id': plannedDateId,
      ...v.values,
    }),
  );
  if (body != null && context.mounted) _openInspection(context, body);
}

// ── Planned dates (due list rows with source = planned) ──────────────────

Future<bool> plannedDateActions(BuildContext context, Json row) async {
  final id = row.integer('planned_date_id');
  if (id == null) return false;
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
            leading: const Icon(TablerIcons.calendar_event),
            title: const Text('Move the date'),
            onTap: () => Navigator.pop(ctx, 'move')),
        ListTile(
            leading: const Icon(TablerIcons.player_skip_forward),
            title: const Text('Skip this date'),
            onTap: () => Navigator.pop(ctx, 'skip')),
        ListTile(
            leading: const Icon(TablerIcons.rotate),
            title: const Text('Plan it again'),
            onTap: () => Navigator.pop(ctx, 'reopen')),
        ListTile(
            leading: const Icon(TablerIcons.archive),
            title: const Text('Archive this date'),
            onTap: () => Navigator.pop(ctx, 'archive')),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return false;
  final path = '$_base/planned-dates/$id';
  final Json? res;
  switch (choice) {
    case 'move':
      res = await showActionForm(context,
          title: 'Move the date',
          denyKey: InspectionDeny.plannedDates,
          fields: [
            ActionField('planned_on', 'Date',
                kind: ActionFieldKind.date,
                required: true,
                initial: row.str('due_on')),
            ActionField('note', 'Note',
                kind: ActionFieldKind.multiline,
                maxLength: 500,
                initial: row.str('note')),
          ],
          submit: (v) => _api.act('POST', path, v.values));
    case 'skip':
      res = await showActionForm(context,
          title: 'Skip this date',
          denyKey: InspectionDeny.plannedDates,
          fields: const [
            ActionField('skipped_reason', 'Why is it skipped?',
                kind: ActionFieldKind.multiline,
                required: true,
                maxLength: 500),
          ],
          submit: (v) => _api.act('POST', '$path/skip', v.values));
    default:
      res = await runServerAction(context,
          denyKey: InspectionDeny.plannedDates,
          call: () => _api.act('POST', '$path/$choice'));
  }
  return res != null;
}

/// Load interim dates for a tenancy (the web's "Add dates").
Future<bool> addPlannedDate(BuildContext context, int leaseId) async {
  final res = await showActionForm(context,
      title: 'Load an interim inspection date',
      denyKey: InspectionDeny.plannedDates,
      fields: const [
        ActionField('date', 'Date', kind: ActionFieldKind.date, required: true),
        ActionField('note', 'Note',
            kind: ActionFieldKind.multiline, maxLength: 500),
      ],
      submit: (v) => _api.act('POST', '$_base/planned-dates', {
            'lease_id': leaseId,
            'dates': [v.values['date']],
            if (v.values['note'] != null) 'note': v.values['note'],
          }));
  return res != null;
}

// ── The walkthrough's actions ────────────────────────────────────────────

/// The Actions section of one inspection. [reload] re-reads the detail;
/// [onArchived] leaves the screen (the record is gone from lists).
List<Widget> inspectionActionButtons(
  BuildContext context,
  Json d, {
  required VoidCallback reload,
  required VoidCallback onArchived,
}) {
  final id = d.integer('id')!;
  final status = d.str('status');
  final closed = status == 'completed' || status == 'cancelled';
  final completed = status == 'completed';
  final open = !closed;
  final readiness = d.obj('readiness')?.str('state');
  final path = '$_base/$id';

  Future<void> done(Json? r) async {
    if (r != null) reload();
  }

  return [
    if (open && readiness == 'ready')
      ServerActionButton(
        icon: TablerIcons.writing_sign,
        label: 'Ready to sign',
        onPressed: () async => done(await runServerAction(context,
            confirmTitle: 'Ready to sign?',
            confirmBody: 'Recording stops and the signing window opens.',
            successFallback: 'Ready to sign.',
            call: () => _api.act('POST', '$path/ready-to-sign'))),
      ),
    if (d.obj('signatures')?.flag('required') == true && open)
      ServerActionButton(
        icon: TablerIcons.link,
        label: 'Signing links',
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(
                builder: (_) => SigningLinksScreen(inspection: d)))
            .then((_) => reload()),
      ),
    if (open && (d.obj('checklist')?.objs('rooms').isNotEmpty ?? false))
      ServerActionButton(
        icon: TablerIcons.checks,
        label: 'Mark all good',
        onPressed: () async => done(await runServerAction(context,
            confirmTitle: 'Mark the whole inspection good?',
            confirmBody: 'Every item not yet recorded is filled with the '
                'agency\'s good condition. Items already recorded stay as '
                'they are.',
            confirmLabel: 'Mark all good',
            successFallback: 'Marked good.',
            call: () => _api.act('POST', '$path/mark-all-good'))),
      ),
    if (open)
      ServerActionButton(
        icon: TablerIcons.calendar_event,
        label: 'Reschedule',
        denyKey: InspectionDeny.reschedule,
        onPressed: () async => done(await showActionForm(context,
            title: 'Reschedule',
            denyKey: InspectionDeny.reschedule,
            successText: 'Rescheduled.',
            fields: [
              ActionField('scheduled_for', 'New date',
                  kind: ActionFieldKind.date,
                  required: true,
                  initial: d.str('scheduled_for')),
              ActionField('scheduled_time', 'Time',
                  kind: ActionFieldKind.time, initial: d.str('scheduled_time')),
              const ActionField(
                  'scheduled_duration_minutes', 'Duration (minutes)',
                  kind: ActionFieldKind.number),
              const ActionField('schedule_note', 'Note',
                  kind: ActionFieldKind.multiline, maxLength: 1000),
              const ActionField('reason', 'Why is it moving?',
                  kind: ActionFieldKind.multiline, maxLength: 500),
            ],
            submit: (v) => _api.act('POST', '$path/reschedule', v.values))),
      ),
    ServerActionButton(
      icon: TablerIcons.file_description,
      label: 'Report (PDF)',
      onPressed: () => openServerFile(context, '$path/report',
          fileName: 'inspection-$id.pdf'),
    ),
    if (open)
      ServerActionButton(
        icon: TablerIcons.printer,
        label: 'Print for signature',
        onPressed: () => openServerFile(context, '$path/print-for-signature',
            fileName: 'inspection-$id-for-signature.pdf'),
      ),
    if (open)
      ServerActionButton(
        icon: TablerIcons.file_text,
        label: 'Paper site form',
        onPressed: () => openServerFile(context, '$path/form',
            fileName: 'site-form-$id.pdf'),
      ),
    if (open)
      ServerActionButton(
        icon: TablerIcons.scan,
        label: 'Upload site form scan',
        onPressed: () async => done(await showActionForm(context,
            title: 'Upload the ticked site form',
            intro: 'The scan is read on the server. Checking what it read is '
                'done on the web for now.',
            fields: const [
              ActionField('scan', 'Photo of the form',
                  kind: ActionFieldKind.photo, required: true),
            ],
            submit: (v) =>
                _api.actWithFiles('$path/scans', const {}, v.files))),
      ),
    ServerActionButton(
      icon: TablerIcons.world,
      label: 'Public report link',
      denyKey: InspectionDeny.publicLink,
      onPressed: () => _publicLink(context, id),
    ),
    if (completed)
      ServerActionButton(
        icon: TablerIcons.mail_forward,
        label: 'Resend report',
        onPressed: () async {
          final r = await runServerAction(context,
              confirmTitle: 'Send the report again?',
              confirmBody: 'It goes to everyone it went to before.',
              call: () => _api.act('POST', '$path/resend-report'));
          if (r != null && context.mounted) _showSendResults(context, r);
        },
      ),
    if (completed)
      ServerActionButton(
        icon: TablerIcons.arrow_right_circle,
        label: 'Next inspection',
        denyKey: InspectionDeny.schedule,
        onPressed: () => _next(context, id),
      ),
    if (completed || d.flag('signed_locked'))
      ServerActionButton(
        icon: TablerIcons.copy,
        label: 'Start new inspection',
        denyKey: InspectionDeny.schedule,
        onPressed: () async {
          final r = await runServerAction(context,
              confirmTitle: 'Start a new inspection?',
              confirmBody: 'A sent report is never edited. A new inspection '
                  'replaces it.',
              confirmLabel: 'Start new',
              successFallback: 'New inspection started.',
              call: () => _api.act('POST', '$path/replace'));
          if (r != null && context.mounted) _openInspection(context, r);
        },
      ),
    if (open)
      ServerActionButton(
        icon: TablerIcons.x,
        label: 'Cancel inspection',
        denyKey: InspectionDeny.cancel,
        danger: true,
        onPressed: () async => done(await showActionForm(context,
            title: 'Cancel this inspection',
            denyKey: InspectionDeny.cancel,
            successText: 'Inspection cancelled.',
            fields: const [
              ActionField('cancel_reason', 'Why is it cancelled?',
                  kind: ActionFieldKind.multiline,
                  required: true,
                  maxLength: 500),
            ],
            submit: (v) => _api.act('POST', '$path/cancel', v.values))),
      ),
    ServerActionButton(
      icon: TablerIcons.archive,
      label: 'Archive',
      denyKey: InspectionDeny.archive,
      danger: true,
      onPressed: () async {
        final r = await runServerAction(context,
            denyKey: InspectionDeny.archive,
            confirmTitle: 'Archive this inspection?',
            confirmBody: 'It leaves the lists. Nothing is deleted.',
            confirmLabel: 'Archive',
            successFallback: 'Inspection archived.',
            call: () => _api.act('DELETE', path));
        if (r != null) onArchived();
      },
    ),
  ];
}

/// "Next inspection": the server may first ask whether to start on top of an
/// open one (409 `reason: open_inspection`); only after the person agrees is
/// it sent again with `confirm_stack`.
Future<void> _next(BuildContext context, int id) async {
  final type = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('Which inspection comes next?')),
        for (final t in kInspectionTypes)
          ListTile(title: Text(t.$2), onTap: () => Navigator.pop(ctx, t.$1)),
      ]),
    ),
  );
  if (type == null || !context.mounted) return;
  Future<Json> send(bool confirm) => _api.act('POST', '$_base/$id/next', {
        'type': type,
        if (confirm) 'confirm_stack': true,
      });
  Json? created;
  try {
    created = await send(false);
  } on RentalsApiException catch (e) {
    if (!context.mounted) return;
    if (e.body['reason'] == 'open_inspection') {
      final go = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Start anyway?'),
          content: Text(e.message),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Go back')),
            TextButton(
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Start anyway')),
          ],
        ),
      );
      if (go != true || !context.mounted) return;
      created = await runServerAction(context, call: () => send(true));
    } else {
      if (e.statusCode == 403) RentalsDenied.mark(InspectionDeny.schedule);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(refusalText(e))));
      return;
    }
  }
  // The answer is the new inspection itself (not the detail): open it by id.
  final newId = created?.integer('id');
  if (newId != null && context.mounted) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StaffInspectionScreen(
        inspectionId: newId,
        propertyId: created!.integer('property_id') ?? 0,
        title: 'Inspection',
      ),
    ));
  }
}

Future<void> _publicLink(BuildContext context, int id) async {
  final r = await runServerAction(context,
      denyKey: InspectionDeny.publicLink,
      call: () => _api.act('POST', '$_base/$id/public-link'));
  final url = r?.str('url');
  if (url == null || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Public report link'),
      content: SelectableText(url),
      actions: [
        TextButton(
          onPressed: () async {
            Navigator.pop(d);
            await runServerAction(context,
                denyKey: InspectionDeny.publicLink,
                confirmTitle: 'Revoke the link?',
                confirmBody: 'Anyone who has it can no longer open the report.',
                confirmLabel: 'Revoke',
                successFallback: 'Link revoked.',
                call: () => _api.act('DELETE', '$_base/$id/public-link'));
          },
          child: const Text('Revoke'),
        ),
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
            Navigator.pop(d);
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Link copied.')));
          },
          child: const Text('Copy'),
        ),
      ],
    ),
  );
}

/// Who a resend went to, as the server reports it.
void _showSendResults(BuildContext context, Json r) {
  final rows = [...r.objs('results'), ...r.objs('skipped')];
  if (rows.isEmpty) return;
  showDialog<void>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Report sent'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final x in rows)
          KeyValueRow(
              [displayValue(x.str('role')), x.str('email')]
                  .whereType<String>()
                  .where((e) => e.isNotEmpty)
                  .join(' · '),
              [displayValue(x.str('status')), x.str('error')]
                  .whereType<String>()
                  .where((e) => e.isNotEmpty)
                  .join(' — ')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('OK')),
      ],
    ),
  );
}

// ── Header details ───────────────────────────────────────────────────────

Future<bool> editInspectionDetails(BuildContext context, Json d) async {
  final h = d.obj('header') ?? const {};
  final res = await showActionForm(context,
      title: 'Details',
      denyKey: InspectionDeny.details,
      successText: 'Details saved.',
      fields: [
        ActionField('electricity_meter_reading', 'Electricity meter',
            initial: h.str('electricity_meter_reading'), maxLength: 100),
        ActionField('water_meter_reading', 'Water meter',
            initial: h.str('water_meter_reading'), maxLength: 100),
        ActionField('furnished_status', 'Furnished',
            initial: h.str('furnished_status'), maxLength: 60),
        ActionField('property_type', 'Property type',
            initial: h.str('property_type'), maxLength: 60),
        ActionField('keys_count', 'Number of keys',
            kind: ActionFieldKind.number, initial: h['keys_count']),
        ActionField('keys_description', 'Keys',
            initial: h.str('keys_description'), maxLength: 191),
        ActionField('remotes_count', 'Number of remotes',
            kind: ActionFieldKind.number, initial: h['remotes_count']),
        ActionField('remotes_description', 'Remotes',
            initial: h.str('remotes_description'), maxLength: 191),
        if (d.str('type') == 'out')
          ActionField('move_in_date_recorded', 'Move-in date',
              kind: ActionFieldKind.date,
              initial: h.str('move_in_date_recorded')),
      ],
      submit: (v) =>
          _api.act('POST', '$_base/${d.integer('id')}/details', v.values));
  return res != null;
}

// ── Rooms and items ──────────────────────────────────────────────────────

/// A room's menu: N/A, All good, add an item.
Future<bool> roomActions(BuildContext context, Json d, Json room) async {
  final id = d.integer('id')!;
  final roomId = room.integer('id');
  if (roomId == null) return false;
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(room.str('label') ?? 'Room')),
        ListTile(
            leading: const Icon(TablerIcons.checks),
            title: const Text('All good'),
            subtitle: const Text('Fills only the items not yet recorded.'),
            onTap: () => Navigator.pop(ctx, 'good')),
        ListTile(
            leading: const Icon(TablerIcons.circle_off),
            title: const Text('Mark the room N/A'),
            onTap: () => Navigator.pop(ctx, 'na')),
        ListTile(
            leading: const Icon(TablerIcons.plus),
            title: const Text('Add an item to this room'),
            onTap: () => Navigator.pop(ctx, 'add')),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return false;
  final propertyId = d.obj('property')?.integer('id');
  Json? r;
  if (choice == 'good') {
    r = await runServerAction(context,
        successFallback: 'Marked good.',
        call: () => _api.act('POST', '$_base/$id/rooms/$roomId/mark-good'));
  } else if (choice == 'na') {
    r = await runServerAction(context,
        confirmTitle: 'Mark ${room.str('label') ?? 'the room'} N/A?',
        successFallback: 'Marked N/A.',
        call: () => _api.act('POST', '$_base/$id/rooms/$roomId/mark-na'));
  } else if (propertyId != null) {
    r = await showActionForm(context,
        title: 'Add an item to ${room.str('label') ?? 'the room'}',
        successText: 'Item added.',
        fields: const [
          ActionField('label', 'What is it?', required: true, maxLength: 191),
        ],
        submit: (v) => _api.act('POST',
                '/mobile/properties/$propertyId/rental-inspection-items', {
              'kind': 'item',
              'property_room_id': roomId,
              ...v.values,
            }));
  }
  return r != null;
}

/// An item's menu: raise a fault report from what was recorded, rename,
/// retire.
Future<bool> itemActions(
    BuildContext context, Json d, Json item, Json? latest) async {
  final propertyId = d.obj('property')?.integer('id');
  final itemId = item.integer('id');
  if (propertyId == null || itemId == null) return false;
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(item.str('label') ?? 'Item')),
        if (latest?.integer('id') != null)
          ListTile(
              leading: const Icon(TablerIcons.tool),
              title: const Text('Raise a fault report'),
              onTap: () => Navigator.pop(ctx, 'fault')),
        ListTile(
            leading: const Icon(TablerIcons.pencil),
            title: const Text('Rename'),
            onTap: () => Navigator.pop(ctx, 'rename')),
        ListTile(
            leading: const Icon(TablerIcons.archive),
            title: const Text('Retire from the checklist'),
            onTap: () => Navigator.pop(ctx, 'retire')),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return false;
  final itemPath =
      '/mobile/properties/$propertyId/rental-inspection-items/$itemId';
  Json? r;
  if (choice == 'fault') {
    r = await runServerAction(context,
        denyKey: InspectionDeny.followUp,
        confirmTitle:
            'Raise a fault report for ${item.str('label') ?? 'this item'}?',
        confirmLabel: 'Raise',
        call: () => _api.act(
                'POST', '$_base/${d.integer('id')}/follow-up/fault-reports', {
              'observation_ids': [latest!.integer('id')],
            }));
  } else if (choice == 'rename') {
    r = await showActionForm(context,
        title: 'Rename',
        successText: 'Renamed.',
        fields: [
          ActionField('label', 'Name',
              required: true, maxLength: 191, initial: item.str('label')),
        ],
        submit: (v) => _api.act('POST', '$itemPath/rename', v.values));
  } else {
    r = await runServerAction(context,
        confirmTitle: 'Retire ${item.str('label') ?? 'this item'}?',
        confirmBody: 'It leaves the checklist for new inspections. Past '
            'records keep it.',
        confirmLabel: 'Retire',
        call: () => _api.act('POST', '$itemPath/retire'));
  }
  return r != null;
}

/// The standard rooms, for a property that has no checklist yet.
Future<bool> seedStandardChecklist(BuildContext context, int propertyId) async {
  final r = await runServerAction(context,
      confirmTitle: 'Build rooms from the standard checklist?',
      confirmLabel: 'Build',
      successFallback: 'Rooms built.',
      call: () => _api.act('POST',
          '/mobile/properties/$propertyId/rental-inspection-items/seed-from-standard'));
  return r != null;
}

// ── Photos: file, unfile, archive ────────────────────────────────────────

/// One photo's menu. To an item needs that item's observation (the web's
/// rule); a room or the unsorted tray need nothing more.
Future<bool> photoActions(BuildContext context, Json d, Json photo) async {
  final id = d.integer('id')!;
  final photoId = photo.integer('id');
  if (photoId == null) return false;
  final rooms = d.obj('checklist')?.objs('rooms') ?? const <Json>[];
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
            leading: const Icon(TablerIcons.door),
            title: const Text('File under a room'),
            onTap: () => Navigator.pop(ctx, 'room')),
        ListTile(
            leading: const Icon(TablerIcons.list_check),
            title: const Text('File under an item'),
            onTap: () => Navigator.pop(ctx, 'item')),
        if (photo.integer('room_id') != null ||
            photo.integer('item_id') != null)
          ListTile(
              leading: const Icon(TablerIcons.inbox),
              title: const Text('Move to unsorted'),
              onTap: () => Navigator.pop(ctx, 'untag')),
        ListTile(
            leading: const Icon(TablerIcons.archive),
            title: const Text('Archive the photo'),
            onTap: () => Navigator.pop(ctx, 'archive')),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return false;
  final path = '$_base/$id/photos/$photoId';
  Json? r;
  switch (choice) {
    case 'room':
      final roomId = await _pick<int>(context, 'Which room?', [
        for (final room in rooms)
          if (room.integer('id') != null)
            (room.integer('id')!, room.str('label') ?? 'Room'),
      ]);
      if (roomId == null || !context.mounted) return false;
      r = await runServerAction(context,
          successFallback: 'Photo filed.',
          call: () =>
              _api.act('POST', '$path/tag', {'property_room_id': roomId}));
    case 'item':
      // Only items already recorded have the observation the server files to.
      final obs = {for (final o in d.objs('observations')) o.integer('id'): o};
      final options = <(int, String)>[
        for (final room in rooms)
          for (final item in room.objs('items'))
            if (obs.containsKey(item.integer('latest_observation_id')))
              (
                item.integer('latest_observation_id')!,
                '${room.str('label') ?? ''} · ${item.str('label') ?? ''}'
              ),
      ];
      if (options.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Record the item first, then file photos under it.')));
        return false;
      }
      final obsId = await _pick<int>(context, 'Which item?', options);
      if (obsId == null || !context.mounted) return false;
      r = await runServerAction(context,
          successFallback: 'Photo filed.',
          call: () => _api.act('POST', '$path/tag',
              {'rental_inspection_observation_id': obsId}));
    case 'untag':
      r = await runServerAction(context,
          successFallback: 'Moved to unsorted.',
          call: () => _api.act('POST', '$path/untag'));
    default:
      r = await runServerAction(context,
          confirmTitle: 'Archive this photo?',
          confirmLabel: 'Archive',
          call: () => _api.act('DELETE', path));
  }
  return r != null;
}

Future<T?> _pick<T>(
        BuildContext context, String title, List<(T, String)> options) =>
    showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text(title)),
          for (final o in options)
            ListTile(title: Text(o.$2), onTap: () => Navigator.pop(ctx, o.$1)),
        ]),
      ),
    );

// ── Attendance and signatures ────────────────────────────────────────────

Future<bool> withdrawAttendance(
    BuildContext context, int inspectionId, int attendanceId) async {
  final r = await runServerAction(context,
      denyKey: InspectionDeny.attendance,
      confirmTitle: 'Withdraw this attendance record?',
      confirmLabel: 'Withdraw',
      successFallback: 'Withdrawn.',
      call: () => _api.act(
          'POST', '$_base/$inspectionId/attendance/$attendanceId/withdraw'));
  return r != null;
}

Future<bool> recordInvitation(
    BuildContext context, int inspectionId, List<Json> rows) async {
  final parties = [
    for (final row in rows)
      if (row.str('party_role') != 'other') row,
  ];
  final r = await showActionForm(context,
      title: 'Record an invitation given',
      denyKey: InspectionDeny.attendance,
      successText: 'Invitation recorded.',
      fields: [
        ActionField('party', 'Who was invited',
            kind: ActionFieldKind.choice,
            required: true,
            options: [
              for (var i = 0; i < parties.length; i++)
                (
                  '$i',
                  parties[i].str('name') ??
                      displayValue(parties[i].str('party_role'))
                ),
            ]),
        const ActionField('method', 'How (e.g. WhatsApp, email, in person)',
            required: true, maxLength: 200),
        const ActionField('occurred_at', 'When', maxLength: 40),
      ], submit: (v) {
    final p = parties[int.parse(v.values['party'] as String)];
    return _api.act('POST', '$_base/$inspectionId/attendance-invitations', {
      'party_role': p.str('party_role'),
      if (p.integer('contact_id') != null)
        'party_contact_id': p.integer('contact_id'),
      if (p.integer('user_id') != null) 'party_user_id': p.integer('user_id'),
      'method': v.values['method'],
      if (v.values['occurred_at'] != null)
        'occurred_at': v.values['occurred_at'],
    });
  });
  return r != null;
}

/// Replace a bad paper scan with a better photo of the signed page.
Future<bool> supersedeWetInk(
    BuildContext context, int inspectionId, int signatureId) async {
  final r = await showActionForm(context,
      title: 'Replace the paper signature scan',
      successText: 'Scan replaced.',
      fields: const [
        ActionField('wet_ink_file', 'Photo of the signed page',
            kind: ActionFieldKind.photo, required: true),
      ],
      submit: (v) => _api.actWithFiles(
          '$_base/$inspectionId/signatures/$signatureId/supersede-wet-ink',
          const {},
          v.files));
  return r != null;
}

// ── Signing links ────────────────────────────────────────────────────────

/// The web's signing panel: one row per party with its link, and the ways
/// to get it to them — email, WhatsApp, QR, or sign now on this phone.
class SigningLinksScreen extends StatefulWidget {
  final Json inspection;
  const SigningLinksScreen({super.key, required this.inspection});

  @override
  State<SigningLinksScreen> createState() => _SigningLinksScreenState();
}

class _SigningLinksScreenState extends State<SigningLinksScreen> {
  final _refresh = ValueNotifier<int>(0);
  int get _id => widget.inspection.integer('id')!;
  String get _path => '$_base/$_id/signing-links';

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  void _reload() => _refresh.value++;

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'Signing',
      body: RentalsFutureView<Json>(
        refresh: _refresh,
        load: () => _api.signingLinks(_id),
        builder: (context, p, reload) => ListView(
          padding: const EdgeInsets.only(top: 4, bottom: 32),
          children: [
            if (p.obj('readiness')?.str('summary') != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: RentalsAlert(p.obj('readiness')!.str('summary')!,
                    tone: RentalsAlertTone.warning),
              ),
            if (p.flag('enabled') == false)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: RentalsAlert(
                    'Signing by link is switched off for this agency.'),
              ),
            for (final row in p.objs('rows')) _row(context, row),
            RentalsActionsSection(actions: [
              ServerActionButton(
                icon: TablerIcons.mail_fast,
                label: 'Email every party',
                denyKey: InspectionDeny.publicLink,
                onPressed: () async {
                  final r = await runServerAction(context,
                      denyKey: InspectionDeny.publicLink,
                      confirmTitle:
                          'Email a signing link to every tenant and the landlord?',
                      confirmLabel: 'Send',
                      call: () => _api.act('POST', '$_path/send-all'));
                  if (r != null && context.mounted) {
                    _results(context, r.objs('results'));
                    _reload();
                  }
                },
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, Json row) {
    final link = row.obj('link');
    final recorded = row.obj('recorded');
    final live = link?.flag('live') ?? false;
    final subtitle = [
      row.str('role_label'),
      recorded?.str('label') ?? link?.str('status_label'),
      if (row.str('blocked_reason') != null) row.str('blocked_reason'),
    ].whereType<String>().join(' · ');
    return RentalsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(row.str('name') ?? '',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        BodyText(subtitle, muted: true),
        if (recorded == null && row.flag('is_agent') == false) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (row.flag('can_issue'))
              ServerActionButton(
                icon: TablerIcons.device_mobile,
                label: 'Sign now on this phone',
                onPressed: () => _signHere(context, row),
              ),
            if (row.flag('can_issue') && !live)
              ServerActionButton(
                icon: TablerIcons.link,
                label: 'Create link',
                denyKey: InspectionDeny.publicLink,
                onPressed: () => _issue(context, row, 'copied'),
              ),
            if (live) ...[
              ServerActionButton(
                icon: TablerIcons.mail,
                label: 'Email',
                denyKey: InspectionDeny.publicLink,
                onPressed: () async {
                  final r = await runServerAction(context,
                      denyKey: InspectionDeny.publicLink,
                      call: () => _api.act(
                          'POST', '$_path/${link!.integer('id')}/email'));
                  if (r != null && context.mounted) {
                    final res = r.obj('result');
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text([
                      displayValue(res?.str('status')),
                      res?.str('to'),
                      res?.str('error'),
                    ]
                            .whereType<String>()
                            .where((e) => e.isNotEmpty)
                            .join(' · '))));
                    _reload();
                  }
                },
              ),
              ServerActionButton(
                icon: TablerIcons.qrcode,
                label: 'QR code',
                denyKey: InspectionDeny.publicLink,
                onPressed: () => _qr(context, link!.integer('id')!),
              ),
              ServerActionButton(
                icon: TablerIcons.link_off,
                label: 'Revoke',
                denyKey: InspectionDeny.publicLink,
                danger: true,
                onPressed: () async {
                  final r = await runServerAction(context,
                      denyKey: InspectionDeny.publicLink,
                      confirmTitle: 'Revoke ${row.str('name') ?? 'this'} link?',
                      confirmLabel: 'Revoke',
                      successFallback: 'Link revoked.',
                      call: () => _api.act(
                          'POST', '$_path/${link!.integer('id')}/revoke'));
                  if (r != null) _reload();
                },
              ),
            ],
          ]),
        ],
      ]),
    );
  }

  Future<Json?> _issue(BuildContext context, Json row, String channel) async {
    final r = await runServerAction(context,
        denyKey: channel == 'device' ? null : InspectionDeny.publicLink,
        call: () => _api.act('POST', _path, {
              'party_role': row.str('role'),
              if (row.integer('contact_id') != null)
                'party_contact_id': row.integer('contact_id'),
              'channel': channel,
            }));
    if (r == null) return null;
    final url = r.str('url');
    if (channel != 'device' && url != null && context.mounted) {
      await Clipboard.setData(ClipboardData(text: url));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Link copied.')));
      }
    }
    _reload();
    return r;
  }

  Future<void> _qr(BuildContext context, int linkId) async {
    try {
      final r = await _api.signingQr(_id, linkId);
      final uri = r.str('data_uri');
      if (uri == null || !context.mounted) return;
      final bytes = base64Decode(uri.substring(uri.indexOf(',') + 1));
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Scan to sign'),
          content: Image.memory(bytes, width: 260, height: 260),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d), child: const Text('Done')),
          ],
        ),
      );
    } on RentalsApiException catch (e) {
      if (e.statusCode == 403) RentalsDenied.mark(InspectionDeny.publicLink);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(refusalText(e))));
      }
    }
  }

  /// "Sign now on this device": a device link for the party, then the full
  /// report to read, then their signature (or their reason for not signing).
  Future<void> _signHere(BuildContext context, Json row) async {
    final issued = await _issue(context, row, 'device');
    final linkId = issued?.integer('link_id');
    if (linkId == null || !context.mounted) return;
    Json detail;
    try {
      detail = await _api.inspection(_id);
    } on RentalsApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(refusalText(e))));
      }
      return;
    }
    if (!context.mounted) return;
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => DeviceSigningScreen(
        detail: detail,
        partyName: row.str('name') ?? '',
        submitPath: '$_path/$linkId/device',
      ),
    ));
    if (ok == true) _reload();
  }

  void _results(BuildContext context, List<Json> rows) {
    if (rows.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Signing links'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final x in rows)
            KeyValueRow(
                x.str('name') ?? '',
                [displayValue(x.str('status')), x.str('error')]
                    .whereType<String>()
                    .where((e) => e.isNotEmpty)
                    .join(' — ')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('OK')),
        ],
      ),
    );
  }
}

/// The party reads the whole report on the agent's phone, then signs it
/// (typed name, drawn signature, "I have read", comment) or declines with a
/// reason from the agency's list.
class DeviceSigningScreen extends StatefulWidget {
  final Json detail;
  final String partyName;
  final String submitPath;

  const DeviceSigningScreen({
    super.key,
    required this.detail,
    required this.partyName,
    required this.submitPath,
  });

  @override
  State<DeviceSigningScreen> createState() => _DeviceSigningScreenState();
}

class _DeviceSigningScreenState extends State<DeviceSigningScreen> {
  bool _readToEnd = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final conditions = d.objs('condition_states');
    final obs = {for (final o in d.objs('observations')) o.integer('id'): o};
    final photos = d.objs('photos').where((p) => !p.flag('archived')).toList();
    final h = d.obj('header') ?? const {};
    return RentalsPage(
      title: 'Read the report',
      subtitle: widget.partyName,
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (!_readToEnd && n.metrics.extentAfter < 80) {
            setState(() => _readToEnd = true);
          }
          return false;
        },
        child: ListView(
          padding: const EdgeInsets.only(top: 4, bottom: 32),
          children: [
            RentalsSection(
              title: [d.str('type_label'), d.obj('property')?.str('address')]
                  .whereType<String>()
                  .join(' · '),
              child: Column(children: [
                for (final e in h.entries)
                  if (e.value != null)
                    KeyValueRow(displayValue(e.key), '${e.value}'),
              ]),
            ),
            for (final room in [
              ...?d.obj('checklist')?.objs('rooms'),
              if (d.obj('checklist')?.objs('meters').isNotEmpty ?? false)
                {
                  'label': 'Meters',
                  'items': d.obj('checklist')!.objs('meters')
                },
            ])
              RentalsSection(
                title: room.str('label') ?? '',
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final item in room
                          .objs('items')
                          .where((i) => !i.flag('is_retired')))
                        Builder(builder: (_) {
                          final o = obs[item.integer('latest_observation_id')];
                          final itemPhotos = photos
                              .where((p) =>
                                  p.integer('item_id') == item.integer('id'))
                              .toList();
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(children: [
                                    Expanded(
                                        child: Text(item.str('label') ?? '')),
                                    if (o?.str('condition') != null)
                                      RentalsStatusChip(
                                          conditionLabel(
                                              conditions, o!.str('condition')),
                                          color: conditionColor(
                                              conditions, o.str('condition'))),
                                  ]),
                                  if (o?.str('notes') != null)
                                    BodyText(o!.str('notes')!, muted: true),
                                  if (itemPhotos.isNotEmpty)
                                    RentalsPhotoGrid([
                                      for (final p in itemPhotos)
                                        if (p.str('url') != null) p.str('url')!
                                    ], emptyText: null),
                                ]),
                          );
                        }),
                    ]),
              ),
            if (d.str('overall_notes') != null)
              RentalsSection(
                  title: 'Overall notes',
                  child: BodyText(d.str('overall_notes')!)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_readToEnd)
                      const BodyText('Scroll to the end of the report to sign.',
                          muted: true),
                    const SizedBox(height: 8),
                    ServerActionButton(
                      icon: TablerIcons.signature,
                      label: 'Sign',
                      onPressed: _readToEnd ? () => _sign(context) : null,
                    ),
                    const SizedBox(height: 8),
                    ServerActionButton(
                      icon: TablerIcons.ban,
                      label: 'Do not sign',
                      danger: true,
                      onPressed: _readToEnd ? () => _decline(context) : null,
                    ),
                  ]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sign(BuildContext context) async {
    final png = await SignaturePadScreen.capture(context, widget.partyName);
    if (png == null || !context.mounted) return;
    final r = await showActionForm(context,
        title: 'Sign the report',
        successText: 'Signed.',
        fields: [
          ActionField('typed_name', 'Full name',
              required: true, initial: widget.partyName, maxLength: 191),
          const ActionField(
              'read_confirmed', 'I have read this inspection report',
              kind: ActionFieldKind.toggle, required: true),
          const ActionField('comment', 'Comment',
              kind: ActionFieldKind.multiline, maxLength: 2000),
        ],
        submit: (v) => _api.act('POST', widget.submitPath, {
              'action': 'sign',
              'signature_image': png,
              ...v.values,
            }));
    if (r != null && context.mounted) Navigator.pop(context, true);
  }

  Future<void> _decline(BuildContext context) async {
    final presets = widget.detail.objs('refusal_reason_presets');
    final r = await showActionForm(context,
        title: 'Not signing',
        successText: 'Recorded.',
        fields: [
          ActionField('typed_name', 'Full name',
              required: true, initial: widget.partyName, maxLength: 191),
          ActionField('reason_preset', 'Reason',
              kind: ActionFieldKind.choice,
              required: true,
              options: [
                for (final p in presets)
                  if (p.str('key') != null)
                    (p.str('key')!, p.str('label') ?? p.str('key')!),
              ]),
          const ActionField('reason_note', 'Tell us more (needed for "other")',
              kind: ActionFieldKind.multiline, maxLength: 2000),
        ],
        submit: (v) => _api.act('POST', widget.submitPath, {
              'action': 'decline',
              ...v.values,
            }));
    if (r != null && context.mounted) Navigator.pop(context, true);
  }
}
