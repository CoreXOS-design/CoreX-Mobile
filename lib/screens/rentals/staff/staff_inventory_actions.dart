import 'package:flutter/material.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../../services/rentals/rentals_http.dart';
import '../../../services/rentals/staff_rentals_api.dart';
import '../widgets/rentals_actions.dart';
import '../widgets/rentals_ui.dart';
import '../widgets/signature_pad.dart';
import 'staff_inventories_screens.dart';
import 'staff_lease_picker.dart';

// The web inventory screen's actions on the phone (parity addendum §2). The
// inventory is editable only while it is a draft; every refusal is the
// server's own sentence.

final _api = StaffRentalsApi.instance;
const _base = '/mobile/rental-inventories';

/// Start the property's inventory on site; a second tap opens the same one.
Future<void> startInventory(BuildContext context) async {
  final picked = await pickLease(context);
  if (picked == null || !context.mounted) return;
  final r = await runServerAction(context,
      confirmTitle: 'Start the inventory for ${picked.address}?',
      confirmLabel: 'Start',
      successFallback: 'Inventory open.',
      call: () => _api.act(
          'POST', '/mobile/properties/${picked.propertyId}/inventory'));
  final id = r?.integer('id');
  if (id != null && context.mounted) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => StaffInventoryDetailScreen(inventoryId: id)));
  }
}

/// "Nothing in this room", or undo it.
Future<bool> toggleRoomEmpty(BuildContext context, int inventoryId, Json room) async {
  final marked = room.flag('marked_empty');
  final r = await runServerAction(context,
      successFallback: marked ? 'Mark removed.' : 'Marked: nothing in this room.',
      call: () => _api.act(marked ? 'DELETE' : 'POST',
          '$_base/$inventoryId/rooms/${room.integer('id')}/mark-empty'));
  return r != null;
}

/// A photo's menu: tag to / untag from a line, archive.
Future<bool> inventoryPhotoActions(
    BuildContext context, Json inv, Json photo) async {
  final id = inv.integer('id')!;
  final photoId = photo.integer('id');
  if (photoId == null) return false;
  final lines = inv.objs('lines');
  final tagged = {for (final x in (photo['line_ids'] as List? ?? const [])) x};
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        for (final l in lines)
          if (l.integer('id') != null)
            ListTile(
              leading: Icon(tagged.contains(l.integer('id'))
                  ? TablerIcons.tag_off
                  : TablerIcons.tag),
              title: Text(l.str('description') ?? 'Item'),
              subtitle: Text(tagged.contains(l.integer('id'))
                  ? 'Untag from this item'
                  : 'Tag to this item'),
              onTap: () => Navigator.pop(ctx, 'line:${l.integer('id')}'),
            ),
        ListTile(
            leading: const Icon(TablerIcons.archive),
            title: const Text('Archive the photo'),
            onTap: () => Navigator.pop(ctx, 'archive')),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return false;
  Json? r;
  if (choice == 'archive') {
    r = await runServerAction(context,
        confirmTitle: 'Archive this photo?',
        confirmLabel: 'Archive',
        call: () => _api.act('DELETE', '$_base/$id/photos/$photoId'));
  } else {
    final lineId = int.parse(choice.substring(5));
    r = await runServerAction(context,
        call: () => _api.act(tagged.contains(lineId) ? 'DELETE' : 'POST',
            '$_base/$id/lines/$lineId/photos/$photoId'));
  }
  return r != null;
}

/// Share the inspection's photos of a room into the inventory by reference.
Future<bool> shareInspectionPhotos(BuildContext context, Json inv, {int? roomId}) async {
  final id = inv.integer('id')!;
  Json res;
  try {
    res = await _api.inventoryInspectionPhotos(id, roomId: roomId);
  } on RentalsApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(refusalText(e))));
    }
    return false;
  }
  final photos = res.objs('photos');
  if (!context.mounted) return false;
  if (photos.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No inspection photos to share here.')));
    return false;
  }
  final picked = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        const ListTile(title: Text('Share which inspection photo?')),
        for (final p in photos)
          ListTile(
            leading: p.str('storage_path') == null
                ? const Icon(TablerIcons.photo)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(p.str('storage_path')!,
                        width: 48, height: 48, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(TablerIcons.photo_off)),
                  ),
            title: Text(p.str('room') ?? ''),
            subtitle: Text(p.str('taken_caption_short') ?? ''),
            onTap: () => Navigator.pop(ctx, p.integer('id')),
          ),
      ]),
    ),
  );
  if (picked == null || !context.mounted) return false;
  final r = await runServerAction(context,
      successFallback: 'Photo shared from the inspection.',
      call: () => _api.act('POST', '$_base/$id/inspection-photos/$picked'));
  return r != null;
}

/// The tenancy's parties, from the lease file (the inventory itself carries
/// no names or contact ids).
Future<List<(String role, int? contactId, String name)>> _parties(Json inv) async {
  final leaseId = inv.integer('lease_id');
  if (leaseId == null) return const [];
  final l = await _api.lease(leaseId);
  return [
    for (final t in l.objs('tenants'))
      ('tenant', t.integer('contact_id'), t.str('name') ?? 'Tenant'),
    for (final o in l.objs('owners'))
      ('landlord', o.integer('contact_id'), o.str('name') ?? 'Landlord'),
  ];
}

/// Sign the inventory: a tenant / the landlord (signed, refused, wet ink,
/// awaiting wet ink) or the agent last (signed only).
Future<bool> signInventory(BuildContext context, Json inv) async {
  final id = inv.integer('id')!;
  List<(String, int?, String)> parties;
  try {
    parties = await _parties(inv);
  } on RentalsApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(refusalText(e))));
    }
    return false;
  }
  if (!context.mounted) return false;
  final signedIds = {
    for (final s in inv.objs('signatures'))
      if (!s.flag('superseded')) '${s.str('party_role')}:${s.integer('party_contact_id')}',
  };
  final who = await showModalBottomSheet<(String, int?, String)>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('Who is signing?')),
        for (final p in parties)
          if (!signedIds.contains('${p.$1}:${p.$2}'))
            ListTile(
              title: Text(p.$3),
              subtitle: Text(displayValue(p.$1)),
              onTap: () => Navigator.pop(ctx, p),
            ),
        ListTile(
          title: const Text('Me (the agent, last)'),
          onTap: () => Navigator.pop(ctx, ('agent', null, 'Agent')),
        ),
      ]),
    ),
  );
  if (who == null || !context.mounted) return false;
  final isAgent = who.$1 == 'agent';
  String disposition = 'signed';
  if (!isAgent) {
    final d = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              title: Text('${who.$3} signs now'),
              onTap: () => Navigator.pop(ctx, 'signed')),
          ListTile(
              title: const Text('Refused to sign'),
              onTap: () => Navigator.pop(ctx, 'refused')),
          ListTile(
              title: const Text('Will sign on paper'),
              onTap: () => Navigator.pop(ctx, 'awaiting_wet_ink')),
          ListTile(
              title: const Text('Signed on paper (photograph it)'),
              onTap: () => Navigator.pop(ctx, 'wet_ink')),
        ]),
      ),
    );
    if (d == null || !context.mounted) return false;
    disposition = d;
  }
  final path = '$_base/$id/signatures';
  final base = <String, dynamic>{
    'party_role': who.$1,
    if (who.$2 != null) 'party_contact_id': who.$2,
    'disposition': disposition,
  };
  Json? r;
  if (disposition == 'signed') {
    final png = await SignaturePadScreen.capture(context, who.$3);
    if (png == null || !context.mounted) return false;
    r = await runServerAction(context,
        successFallback: 'Signed.',
        call: () => _api.act('POST', path, {...base, 'signature_image': png}));
  } else if (disposition == 'refused') {
    // The web offers the agency's inspection refusal reasons here; the
    // inventory payload does not carry them, the inspection checklist does.
    var presets = const <Json>[];
    final propertyId = inv.obj('property')?.integer('id');
    if (propertyId != null) {
      try {
        presets = (await _api.checklist(propertyId)).objs('refusal_reason_presets');
      } on RentalsApiException catch (_) {}
    }
    if (!context.mounted) return false;
    if (presets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('The refusal reasons could not be loaded. Try again '
              'with signal, or record it on the web.')));
      return false;
    }
    r = await showActionForm(context,
        title: '${who.$3} refused to sign',
        successText: 'Recorded.',
        fields: [
          ActionField('refusal_reason_preset', 'Reason',
              kind: ActionFieldKind.choice,
              required: true,
              options: [
                for (final p in presets)
                  if (p.str('key') != null) (p.str('key')!, p.str('label') ?? p.str('key')!),
              ]),
          const ActionField('refusal_reason_note', 'Tell us more (needed for "other")',
              kind: ActionFieldKind.multiline, maxLength: 2000),
        ],
        submit: (v) => _api.act('POST', path, {...base, ...v.values}));
  } else if (disposition == 'wet_ink') {
    r = await showActionForm(context,
        title: 'Signed on paper',
        successText: 'Recorded.',
        fields: const [
          ActionField('wet_ink_file', 'Photo of the signed page',
              kind: ActionFieldKind.photo, required: true),
        ],
        submit: (v) => _api.actWithFiles(path, base, v.files));
  } else {
    r = await runServerAction(context,
        successFallback: 'Recorded: will sign on paper.',
        call: () => _api.act('POST', path, base));
  }
  return r != null;
}

/// Complete: the server lists the rooms not yet checked, or names the
/// party still to sign.
Future<bool> completeInventory(BuildContext context, int id) async {
  if (!RentalsHttp.instance.reachable.value) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text(kNeedsSignal)));
    return false;
  }
  try {
    await _api.act('POST', '$_base/$id/complete');
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Inventory completed.')));
    }
    return true;
  } on RentalsApiException catch (e) {
    if (!context.mounted) return false;
    final rooms = [
      for (final r in (e.body['unvisited_rooms'] as List? ?? const []))
        if (r is Map) '${r['label'] ?? ''}',
    ];
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Not completed yet'),
        content: Text([refusalText(e), ...rooms.map((r) => '• $r')].join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('OK')),
        ],
      ),
    );
    return false;
  }
}

/// The inventory's Actions section.
List<Widget> inventoryActionButtons(
  BuildContext context,
  Json inv, {
  required VoidCallback reload,
  required VoidCallback onArchived,
}) {
  final id = inv.integer('id')!;
  final status = inv.str('status');
  final editable = inv.flag('editable');
  final completed = status == 'completed';
  final path = '$_base/$id';
  void after(Object? r) {
    if (r != null && r != false) reload();
  }

  return [
    if (editable)
      ServerActionButton(
        icon: TablerIcons.copy,
        label: 'Copy from last inventory',
        onPressed: () async => after(await runServerAction(context,
            confirmTitle: 'Copy the items from the last inventory?',
            confirmLabel: 'Copy',
            successFallback: 'Items copied.',
            call: () => _api.act('POST', '$path/copy-from-last'))),
      ),
    if (editable)
      ServerActionButton(
        icon: TablerIcons.photo_plus,
        label: 'Share inspection photos',
        onPressed: () async => after(await shareInspectionPhotos(context, inv)),
      ),
    if (editable)
      ServerActionButton(
        icon: TablerIcons.signature,
        label: 'Sign',
        onPressed: () async => after(await signInventory(context, inv)),
      ),
    if (editable)
      ServerActionButton(
        icon: TablerIcons.circle_check,
        label: 'Complete',
        onPressed: () async => after(await completeInventory(context, id)),
      ),
    ServerActionButton(
      icon: TablerIcons.file_description,
      label: 'Report (PDF)',
      onPressed: () =>
          openServerFile(context, '$path/report', fileName: 'inventory-$id.pdf'),
    ),
    if (editable)
      ServerActionButton(
        icon: TablerIcons.printer,
        label: 'Print for signature',
        onPressed: () => openServerFile(context, '$path/print-for-signature',
            fileName: 'inventory-$id-for-signature.pdf'),
      ),
    if (completed)
      ServerActionButton(
        icon: TablerIcons.mail_forward,
        label: 'Resend report',
        onPressed: () => runServerAction(context,
            confirmTitle: 'Send the report again?',
            successFallback: 'Report sent.',
            call: () => _api.act('POST', '$path/resend-report')),
      ),
    if (completed && inv.integer('lease_id') != null)
      ServerActionButton(
        icon: TablerIcons.door_exit,
        label: 'Move-out check',
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(
                builder: (_) => InventoryMoveOutScreen(inventory: inv)))
            .then((_) => reload()),
      ),
    if (editable)
      ServerActionButton(
        icon: TablerIcons.x,
        label: 'Cancel inventory',
        danger: true,
        onPressed: () async => after(await showActionForm(context,
            title: 'Cancel this inventory',
            successText: 'Inventory cancelled.',
            fields: const [
              ActionField('cancel_reason', 'Why is it cancelled?',
                  kind: ActionFieldKind.multiline, required: true, maxLength: 500),
            ],
            submit: (v) => _api.act('POST', '$path/cancel', v.values))),
      ),
    ServerActionButton(
      icon: TablerIcons.archive,
      label: 'Archive',
      danger: true,
      onPressed: () async {
        final r = await runServerAction(context,
            confirmTitle: 'Archive this inventory?',
            confirmBody: 'It leaves the lists. Nothing is deleted.',
            confirmLabel: 'Archive',
            successFallback: 'Inventory archived.',
            call: () => _api.act('DELETE', path));
        if (r != null) onArchived();
      },
    ),
  ];
}

// ── Move-out ─────────────────────────────────────────────────────────────

/// The move-out comparison (read-only from the server): each line's move-in
/// count beside today's, with a finding per line, move-out photos, then
/// complete and sign off.
class InventoryMoveOutScreen extends StatefulWidget {
  final Json inventory;
  const InventoryMoveOutScreen({super.key, required this.inventory});

  @override
  State<InventoryMoveOutScreen> createState() => _InventoryMoveOutScreenState();
}

class _InventoryMoveOutScreenState extends State<InventoryMoveOutScreen> {
  final _refresh = ValueNotifier<int>(0);
  int get _id => widget.inventory.integer('id')!;

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  void _reload() => _refresh.value++;

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'Move-out check',
      body: RentalsFutureView<Json>(
        refresh: _refresh,
        load: () => _api.inventoryComparison(_id),
        builder: (context, c, reload) {
          final presets = c.objs('disposition_presets');
          return ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 32),
            children: [
              for (final row in c.objs('rows')) _row(context, row, presets),
              RentalsActionsSection(actions: [
                ServerActionButton(
                  icon: TablerIcons.circle_check,
                  label: 'Complete the move-out check',
                  onPressed: () async {
                    final r = await runServerAction(context,
                        confirmTitle: 'Complete the move-out check?',
                        confirmLabel: 'Complete',
                        successFallback: 'Move-out check completed.',
                        call: () => _api.act('POST', '$_base/$_id/move-out/complete'));
                    if (r != null) _reload();
                  },
                ),
                ServerActionButton(
                  icon: TablerIcons.signature,
                  label: 'Sign off',
                  onPressed: () => _signOff(context),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, Json row, List<Json> presets) {
    final lineId = row.integer('line_id');
    return RentalsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(row.str('description') ?? '',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        BodyText(
            [
              row.str('room_label'),
              if (row['quantity_at_move_in'] != null)
                '${row['quantity_at_move_in']} at move-in',
              if (row['quantity_found'] != null) '${row['quantity_found']} today',
            ].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
            muted: true),
        if (row.str('disposition_label') != null)
          KeyValueRow('Finding', row.str('disposition_label')),
        KeyValueRow('Notes', row.str('notes')),
        if (lineId != null)
          Wrap(spacing: 8, runSpacing: 8, children: [
            ServerActionButton(
              icon: TablerIcons.clipboard_check,
              label: row.str('disposition_label') == null ? 'Record finding' : 'Change finding',
              onPressed: () async {
                final r = await showActionForm(context,
                    title: row.str('description') ?? 'Finding',
                    successText: 'Finding recorded.',
                    fields: [
                      ActionField('disposition_key', 'Finding',
                          kind: ActionFieldKind.choice,
                          required: true,
                          initial: row.str('disposition_key'),
                          options: [
                            for (final p in presets)
                              if (p.str('key') != null)
                                (p.str('key')!, p.str('label') ?? p.str('key')!),
                          ]),
                      ActionField('quantity_found', 'How many today',
                          kind: ActionFieldKind.number, initial: row['quantity_found']),
                      ActionField('notes', 'Notes',
                          kind: ActionFieldKind.multiline,
                          maxLength: 2000,
                          initial: row.str('notes')),
                    ],
                    submit: (v) => _api.act(
                        'POST', '$_base/$_id/lines/$lineId/dispositions', v.values));
                if (r != null) _reload();
              },
            ),
            ServerActionButton(
              icon: TablerIcons.camera_plus,
              label: 'Move-out photo',
              onPressed: () async {
                final r = await showActionForm(context,
                    title: 'Move-out photo',
                    successText: 'Photo added.',
                    fields: const [
                      ActionField('photos[0]', 'Photo',
                          kind: ActionFieldKind.photo, required: true),
                    ],
                    submit: (v) => _api.actWithFiles(
                        '$_base/$_id/lines/$lineId/move-out-photos', const {}, v.files));
                if (r != null) _reload();
              },
            ),
          ]),
      ]),
    );
  }

  Future<void> _signOff(BuildContext context) async {
    List<(String, int?, String)> parties;
    try {
      parties = await _parties(widget.inventory);
    } on RentalsApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(refusalText(e))));
      }
      return;
    }
    if (!context.mounted) return;
    final all = [...parties, ('agent', null, 'Me (the agent)')];
    final r = await showActionForm(context,
        title: 'Sign off the move-out check',
        successText: 'Signed off.',
        fields: [
          ActionField('party', 'Who',
              kind: ActionFieldKind.choice,
              required: true,
              options: [
                for (var i = 0; i < all.length; i++) ('$i', all[i].$3),
              ]),
          const ActionField('disposition', 'Outcome',
              kind: ActionFieldKind.choice,
              required: true,
              options: [('signed', 'Signed'), ('refused', 'Refused')]),
          const ActionField('signed_name', 'Name of the person signing',
              required: true, maxLength: 191),
          const ActionField('refusal_reason', 'Reason (when refused)',
              kind: ActionFieldKind.multiline, maxLength: 500),
        ],
        submit: (v) {
          final p = all[int.parse(v.values['party'] as String)];
          return _api.act('POST', '$_base/$_id/move-out/sign-off', {
            'party_role': p.$1,
            if (p.$2 != null) 'party_contact_id': p.$2,
            'disposition': v.values['disposition'],
            'signed_name': v.values['signed_name'],
            if (v.values['refusal_reason'] != null)
              'refusal_reason': v.values['refusal_reason'],
          });
        });
    if (r != null) _reload();
  }
}
