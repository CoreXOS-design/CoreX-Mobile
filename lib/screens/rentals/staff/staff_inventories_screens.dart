import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../../providers/rentals_access_provider.dart';
import '../../../services/rentals/rental_write_queue.dart';
import '../../../services/rentals/staff_rentals_api.dart';
import '../widgets/rentals_actions.dart';
import '../widgets/rentals_ui.dart';
import 'staff_faults_screens.dart';
import 'staff_inventory_actions.dart';

final _api = StaffRentalsApi.instance;
final _queue = RentalWriteQueue.instance;

/// Inventories: list, start one on site, detail, typed lines, photos,
/// signatures, completion and the move-out check (the web's own actions).
class StaffInventoriesScreen extends StatelessWidget {
  const StaffInventoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final canAct =
        context.watch<RentalsAccess>().staffScreens.inventories.canAct;
    return RentalsPage(
      title: 'Inventories',
      actions: [
        if (canAct)
          IconButton(
            tooltip: 'Start an inventory',
            icon: const Icon(TablerIcons.plus),
            onPressed: () => startInventory(context),
          ),
      ],
      body: RentalsPagedList<Json>(
        searchHint: 'Address, tenant or creator',
        filters: const [
          ListFilter(param: 'status', label: 'Status', options: [
            ('draft', 'Draft'),
            ('awaiting_signature', 'Awaiting signature'),
            ('completed', 'Completed'),
            ('cancelled', 'Cancelled'),
          ]),
          ListFilter(param: 'sort', label: 'Sort', options: [
            ('created', 'Newest'),
            ('property', 'Property'),
            ('status', 'Status'),
          ]),
        ],
        fetch: _api.inventories,
        itemBuilder: (context, i) => RentalsListCard(
          title: i.obj('property')?.str('address') ?? 'Inventory',
          subtitle: i.str('tenant_names'),
          meta: [
            '${i.integer('lines_count') ?? 0} lines',
            fmtMoment(i.str('created_at')),
          ].join(' · '),
          statusLabel: i.str('status_label'),
          statusKey: i.str('status'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  StaffInventoryDetailScreen(inventoryId: i.integer('id')!))),
        ),
      ),
    );
  }
}

class StaffInventoryDetailScreen extends StatefulWidget {
  final int inventoryId;
  const StaffInventoryDetailScreen({super.key, required this.inventoryId});

  @override
  State<StaffInventoryDetailScreen> createState() =>
      _StaffInventoryDetailScreenState();
}

/// One room heading: a property room (`rooms[]`) or a typed room label that
/// only lines carry.
class _RoomKey {
  final int? id;
  final String label;
  const _RoomKey(this.id, this.label);
}

class _StaffInventoryDetailScreenState
    extends State<StaffInventoryDetailScreen> {
  final _refresh = ValueNotifier<int>(0);

  String get _group => StaffRentalsApi.inventoryGroup(widget.inventoryId);

  @override
  void initState() {
    super.initState();
    _queue.sent.addListener(_bump);
    _queue.addListener(_onQueue);
  }

  @override
  void dispose() {
    _queue.sent.removeListener(_bump);
    _queue.removeListener(_onQueue);
    _refresh.dispose();
    super.dispose();
  }

  void _bump() => _refresh.value++;

  void _onQueue() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'Inventory',
      body: RentalsFutureView<Json>(
        refresh: _refresh,
        load: () => _api.inventory(widget.inventoryId),
        builder: (context, inv, reload) => _body(context, inv),
      ),
    );
  }

  // ── what is still on this phone ────────────────────────────────────────

  List<QueuedRentalWrite> get _pending => _queue.itemsIn(_group);

  /// Lines added here and not yet sent.
  List<QueuedRentalWrite> get _pendingAdds =>
      _pending.where((q) => q.path.endsWith('/lines')).toList();

  /// "change waiting" / "removing" for a line with a queued write.
  String? _pendingChange(int lineId) {
    String? state;
    for (final q in _pending) {
      if (q.path.endsWith('/lines/$lineId/retire')) return 'removing';
      if (q.path.endsWith('/lines/$lineId')) state = 'change waiting';
    }
    return state;
  }

  String? _conditionLabel(List<Json> states, String? key) {
    if (key == null) return null;
    for (final c in states) {
      if (c.str('key') == key) return c.str('label') ?? key;
    }
    return key;
  }

  Widget _body(BuildContext context, Json inv) {
    final editable = inv.flag('editable');
    final rooms = inv.objs('rooms');
    final lines = inv.objs('lines');
    final photos = inv.objs('photos');
    final states = inv.objs('condition_states');

    // Property rooms first, then any typed room labels the lines carry.
    final headings = <_RoomKey>[
      for (final r in rooms) _RoomKey(r.integer('id'), r.str('label') ?? 'Room'),
    ];
    final typed = <String>{
      for (final l in lines)
        if (l.integer('room_id') == null && l.str('room_label') != null)
          l.str('room_label')!,
      for (final q in _pendingAdds)
        if (q.fields['property_room_id'] == null &&
            q.fields['room_label'] is String)
          q.fields['room_label'] as String,
    };
    for (final t in typed) {
      if (!headings.any((h) => h.id == null && h.label == t)) {
        headings.add(_RoomKey(null, t));
      }
    }

    bool inRoom(int? roomId, String? roomLabel, _RoomKey h) =>
        h.id != null ? roomId == h.id : roomId == null && roomLabel == h.label;

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      children: [
        RentalsQueueBanner(group: _group),
        RentalsSection(
          title: inv.obj('property')?.str('address') ?? 'Inventory',
          trailing: RentalsStatusChip(inv.str('status_label') ?? '',
              statusKey: inv.str('status')),
          child: Column(children: [
            KeyValueRow('Tenant', inv.str('tenant_names')),
            KeyValueRow('Created by', inv.obj('created_by')?.str('name')),
            KeyValueRow('Created', fmtMoment(inv.str('created_at'))),
            KeyValueRow('Completed', fmtMoment(inv.str('completed_at'))),
          ]),
        ),
        for (final h in headings)
          _roomSection(
            context,
            inv: inv,
            heading: h,
            editable: editable,
            states: states,
            lines: lines
                .where((l) =>
                    inRoom(l.integer('room_id'), l.str('room_label'), h))
                .toList(),
            adds: _pendingAdds
                .where((q) => inRoom(
                    q.fields['property_room_id'] as int?,
                    q.fields['room_label'] as String?,
                    h))
                .toList(),
            photos: h.id == null
                ? const []
                : photos.where((p) => p.integer('room_id') == h.id).toList(),
          ),
        // Photos the server holds against no room of this property (the web
        // shows them too); without this they were never seen on the phone.
        if (photos.any((p) => !rooms.any((r) =>
            r.integer('id') != null && r.integer('id') == p.integer('room_id'))))
          RentalsSection(
            title: 'Photos not in a room',
            child: _photoGrid([
              for (final p in photos)
                if (!rooms.any((r) =>
                    r.integer('id') != null &&
                    r.integer('id') == p.integer('room_id')))
                  p,
            ]),
          ),
        if (editable)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(TablerIcons.plus),
              label: const Text('Add item'),
              onPressed: () => _addLine(context, inv),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: BodyText(
                'Items and photos can only be changed while the inventory is '
                'a draft.',
                muted: true),
          ),
        if (inv.objs('signatures').any((s) => !s.flag('superseded')))
          RentalsSection(
            title: 'Signatures',
            child: Column(children: [
              for (final s in inv.objs('signatures').where((s) => !s.flag('superseded')))
                KeyValueRow(displayValue(s.str('party_role')),
                    displayValue(s.str('disposition'))),
            ]),
          ),
        RentalsActionsSection(actions: [
          if (editable && photos.any((p) => p.str('url') != null))
            ServerActionButton(
              icon: TablerIcons.arrows_sort,
              label: 'Sort photos',
              onPressed: () => _sortPhotos(context, inv),
            ),
          ...inventoryActionButtons(
            context,
            inv,
            reload: () => _refresh.value++,
            onArchived: () {
              if (mounted) Navigator.of(context).pop();
            },
          ),
        ]),
      ],
    );
  }

  Future<void> _sortPhotos(BuildContext context, Json inv) async {
    final photos = inv.objs('photos').where((p) => p.str('url') != null).toList();
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
                    errorBuilder: (_, __, ___) => const Icon(TablerIcons.photo_off)),
              ),
              title: Text(inv
                      .objs('rooms')
                      .where((r) => r.integer('id') == p.integer('room_id'))
                      .firstOrNull
                      ?.str('label') ??
                  'Not in a room'),
              subtitle: Text(p.flag('from_inspection') ? 'Inspection' : ''),
              onTap: () => Navigator.pop(ctx, p),
            ),
        ]),
      ),
    );
    if (picked == null || !context.mounted) return;
    if (await inventoryPhotoActions(context, inv, picked)) _refresh.value++;
  }

  Widget _roomSection(
    BuildContext context, {
    required Json inv,
    required _RoomKey heading,
    required bool editable,
    required List<Json> states,
    required List<Json> lines,
    required List<QueuedRentalWrite> adds,
    required List<Json> photos,
  }) {
    return RentalsSection(
      title: heading.label,
      trailing: editable
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              RentalsSectionAction(
                icon: TablerIcons.plus,
                tooltip: 'Add an item to ${heading.label}',
                onPressed: () => _addLine(context, inv, preset: heading),
              ),
              if (heading.id != null)
                RentalsSectionAction(
                  icon: TablerIcons.camera_plus,
                  tooltip: 'Photo of ${heading.label}',
                  onPressed: () => _addPhoto(context,
                      roomId: heading.id, label: heading.label),
                ),
              // "Nothing in this room" and its undo (online, the server's).
              if (heading.id != null && (lines.isEmpty || _markedEmpty(inv, heading.id)))
                RentalsSectionAction(
                  icon: _markedEmpty(inv, heading.id)
                      ? TablerIcons.arrow_back_up
                      : TablerIcons.box_off,
                  tooltip: _markedEmpty(inv, heading.id)
                      ? 'Undo "nothing in this room"'
                      : 'Nothing in this room',
                  onPressed: () async {
                    final room = inv
                        .objs('rooms')
                        .firstWhere((r) => r.integer('id') == heading.id);
                    if (await toggleRoomEmpty(context, widget.inventoryId, room)) {
                      _refresh.value++;
                    }
                  },
                ),
            ])
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lines.isEmpty && adds.isEmpty)
            BodyText(
                _markedEmpty(inv, heading.id)
                    ? 'Nothing in this room'
                    : 'No items.',
                muted: true),
          for (final l in lines)
            _lineRow(
              context,
              quantity: l.integer('quantity'),
              description: l.str('description') ?? 'Item',
              condition: _conditionLabel(states, l.str('condition_key')),
              conditionKey: l.str('condition_key'),
              photoCount: (l['photo_ids'] as List?)?.length ?? 0,
              waiting: _pendingChange(l.integer('id')!),
              onTap: editable && _pendingChange(l.integer('id')!) != 'removing'
                  ? () => _editLine(context, inv, l)
                  : null,
              onPhoto: editable
                  ? () => _addPhoto(context,
                      roomId: l.integer('room_id'),
                      lineId: l.integer('id'),
                      label: l.str('description'))
                  : null,
            ),
          for (final q in adds)
            _lineRow(
              context,
              quantity: q.fields['quantity'] as int?,
              description: (q.fields['description'] ?? 'Item').toString(),
              condition: _conditionLabel(
                  states, q.fields['condition_key'] as String?),
              conditionKey: q.fields['condition_key'] as String?,
              photoCount: 0,
              waiting: q.state == QueuedWriteState.failed
                  ? 'not sent'
                  : 'waiting to send',
            ),
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 8),
            _photoGrid(photos),
          ],
        ],
      ),
    );
  }

  /// "Inspection" marks a photo shared by reference from the inspection, as
  /// the web's badge does.
  Widget _photoGrid(List<Json> photos) {
    final shown = photos.where((p) => p.str('url') != null).toList();
    return RentalsPhotoGrid(
      [for (final p in shown) p.str('url')!],
      captions: [
        for (final p in shown)
          [
            if (p.flag('from_inspection')) 'Inspection',
            if (p.str('captured_at') != null)
              'Taken ${fmtMoment(p.str('captured_at'))}',
          ].join(' · '),
      ],
      emptyText: null,
      onLoadError: _refetchOnce,
    );
  }

  /// The server's "nothing in this room" mark on a property room.
  static bool _markedEmpty(Json inv, int? roomId) => roomId != null &&
      inv.objs('rooms').any(
          (r) => r.integer('id') == roomId && r.flag('marked_empty'));

  bool _refetched = false;

  /// An expired photo link: one fresh read for new links, never a loop.
  void _refetchOnce() {
    if (_refetched || !mounted) return;
    _refetched = true;
    _refresh.value++;
  }

  Widget _lineRow(
    BuildContext context, {
    required int? quantity,
    required String description,
    required String? condition,
    required String? conditionKey,
    required int photoCount,
    String? waiting,
    VoidCallback? onTap,
    VoidCallback? onPhoto,
  }) {
    final muted = waiting != null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(
            width: 36,
            child: Text(quantity == null ? '–' : '$quantity ×',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(description,
                    style: TextStyle(
                      decoration: waiting == 'removing'
                          ? TextDecoration.lineThrough
                          : null,
                    )),
                if (muted || photoCount > 0)
                  BodyText(
                      [
                        if (photoCount > 0)
                          '$photoCount photo${photoCount == 1 ? '' : 's'}',
                        if (waiting != null) waiting,
                      ].join(' · '),
                      muted: true),
              ],
            ),
          ),
          if (condition != null)
            RentalsStatusChip(condition, statusKey: null),
          if (onPhoto != null)
            IconButton(
              tooltip: 'Photo of this item',
              visualDensity: VisualDensity.compact,
              icon: const Icon(TablerIcons.camera_plus, size: 18),
              onPressed: onPhoto,
            ),
        ]),
      ),
    );
  }

  // ── actions ────────────────────────────────────────────────────────────

  Future<void> _addLine(BuildContext context, Json inv,
      {_RoomKey? preset}) async {
    final input = await showModalBottomSheet<_LineInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LineSheet(
        title: 'Add item',
        rooms: inv.objs('rooms'),
        conditions: inv.objs('condition_states'),
        roomId: preset?.id,
        roomLabel: preset?.id == null ? preset?.label : null,
      ),
    );
    if (input == null || !context.mounted) return;
    final r = await _api.addInventoryLine(
      inventoryId: widget.inventoryId,
      description: input.description,
      roomId: input.roomId,
      roomLabel: input.roomLabel,
      quantity: input.quantity,
      conditionKey: input.conditionKey,
    );
    if (!context.mounted) return;
    showSubmitOutcome(context, r.outcome, sentText: 'Item added.');
  }

  Future<void> _editLine(BuildContext context, Json inv, Json line) async {
    final lineId = line.integer('id')!;
    final input = await showModalBottomSheet<_LineInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LineSheet(
        title: 'Change item',
        rooms: inv.objs('rooms'),
        conditions: inv.objs('condition_states'),
        roomId: line.integer('room_id'),
        roomLabel:
            line.integer('room_id') == null ? line.str('room_label') : null,
        description: line.str('description'),
        quantity: line.integer('quantity'),
        conditionKey: line.str('condition_key'),
        canRemove: true,
      ),
    );
    if (input == null || !context.mounted) return;
    if (input.remove) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dlg) => AlertDialog(
          title: const Text('Remove this item?'),
          content: Text('"${line.str('description') ?? ''}" comes off the '
              'inventory. It stays on record.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dlg, false),
                child: const Text('Keep')),
            TextButton(
                onPressed: () => Navigator.pop(dlg, true),
                child: const Text('Remove')),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
      final r = await _api.retireInventoryLine(
        inventoryId: widget.inventoryId,
        lineRef: '$lineId',
        description: line.str('description') ?? 'Item',
      );
      if (!context.mounted) return;
      showSubmitOutcome(context, r.outcome, sentText: 'Item removed.');
      return;
    }
    final r = await _api.updateInventoryLine(
      inventoryId: widget.inventoryId,
      lineRef: '$lineId',
      description: input.description,
      roomId: input.roomId,
      roomLabel: input.roomLabel,
      quantity: input.quantity,
      conditionKey: input.conditionKey,
    );
    if (!context.mounted) return;
    showSubmitOutcome(context, r.outcome, sentText: 'Item changed.');
  }

  Future<void> _addPhoto(BuildContext context,
      {int? roomId, int? lineId, String? label}) async {
    final f = await PhotoPickerRow.takeOne(context);
    if (f == null || !context.mounted) return;
    final r = await _api.addInventoryPhoto(
      inventoryId: widget.inventoryId,
      photoPath: f.path,
      roomId: roomId,
      lineId: lineId,
      label: 'Inventory photo${label == null ? '' : ': $label'}',
    );
    if (!context.mounted) return;
    showSubmitOutcome(context, r.outcome, sentText: 'Photo added.');
  }
}

class _LineInput {
  final String description;
  final int? roomId;
  final String? roomLabel;
  final int? quantity;
  final String? conditionKey;
  final bool remove;
  const _LineInput({
    this.description = '',
    this.roomId,
    this.roomLabel,
    this.quantity,
    this.conditionKey,
    this.remove = false,
  });
}

/// Add / change one line: description, room (one of the inventory's rooms
/// or a typed name), quantity (blank = unknown) and a condition from the
/// agency's own `condition_states`.
class _LineSheet extends StatefulWidget {
  final String title;
  final List<Json> rooms;
  final List<Json> conditions;
  final int? roomId;
  final String? roomLabel;
  final String? description;
  final int? quantity;
  final String? conditionKey;
  final bool canRemove;

  const _LineSheet({
    required this.title,
    required this.rooms,
    required this.conditions,
    this.roomId,
    this.roomLabel,
    this.description,
    this.quantity,
    this.conditionKey,
    this.canRemove = false,
  });

  @override
  State<_LineSheet> createState() => _LineSheetState();
}

class _LineSheetState extends State<_LineSheet> {
  static const _typed = '__typed__';

  late final _description = TextEditingController(text: widget.description);
  late final _quantity =
      TextEditingController(text: widget.quantity?.toString() ?? '');
  late final _roomName = TextEditingController(text: widget.roomLabel ?? '');
  late String? _room = widget.roomId != null
      ? '${widget.roomId}'
      : (widget.roomLabel != null || widget.rooms.isEmpty ? _typed : null);
  late String? _condition = widget.conditionKey;

  @override
  void dispose() {
    _description.dispose();
    _quantity.dispose();
    _roomName.dispose();
    super.dispose();
  }

  bool get _valid =>
      _description.text.trim().isNotEmpty &&
      _room != null &&
      (_room != _typed || _roomName.text.trim().isNotEmpty) &&
      (_quantity.text.trim().isEmpty ||
          int.tryParse(_quantity.text.trim()) != null);

  @override
  Widget build(BuildContext context) {
    return SheetForm(
      title: widget.title,
      submitLabel: 'Save',
      busy: false,
      onSubmit: !_valid
          ? null
          : () => Navigator.pop(
                context,
                _LineInput(
                  description: _description.text.trim(),
                  roomId: _room == _typed ? null : int.tryParse(_room!),
                  roomLabel: _room == _typed ? _roomName.text.trim() : null,
                  quantity: int.tryParse(_quantity.text.trim()),
                  conditionKey: _condition,
                ),
              ),
      children: [
        TextField(
          controller: _description,
          autofocus: widget.description == null,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              labelText: 'What is it?', hintText: 'e.g. Wooden double bed'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _quantity,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              labelText: 'How many?', hintText: 'Leave blank if unknown'),
        ),
        const SizedBox(height: 12),
        OptionField(
          label: 'Room',
          value: _room,
          options: [
            for (final r in widget.rooms)
              if (r.integer('id') != null)
                ('${r.integer('id')}', r.str('label') ?? 'Room'),
            (_typed, 'Another room (type its name)'),
          ],
          onChanged: (v) => setState(() => _room = v),
        ),
        if (_room == _typed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _roomName,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Room name'),
            ),
          ),
        if (widget.conditions.isNotEmpty) ...[
          const BodyText('Condition', muted: true),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in widget.conditions)
              RentalsChoiceChip(
                label: Text(c.str('label') ?? c.str('key') ?? ''),
                selected: _condition == c.str('key'),
                // Tapping the chosen one again clears it (condition is
                // optional).
                onSelected: (on) =>
                    setState(() => _condition = on ? c.str('key') : null),
              ),
          ]),
        ],
        if (widget.canRemove)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: TextButton.icon(
              icon: const Icon(TablerIcons.trash, size: 18),
              label: const Text('Remove this item'),
              onPressed: () =>
                  Navigator.pop(context, const _LineInput(remove: true)),
            ),
          ),
      ],
    );
  }
}
