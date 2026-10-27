import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:tabler_icons/tabler_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/rentals/client_rentals_api.dart';
import '../../../services/rentals/rental_write_queue.dart';
import '../../../services/rentals/rentals_cache.dart';
import '../../../services/rentals/rentals_http.dart';
import '../../../theme.dart';
import '../widgets/rentals_ui.dart';
import 'client_inspection_screens.dart';
import 'client_rentals_shared.dart';

final _api = ClientRentalsApi.tenant;

// Tenant (lessee) screens. Two rules shape all of them (Johan):
//  * nothing about the owner — no name, contact or detail, not even who gave
//    a notice; if an owner field ever turned up in a payload it is not shown;
//  * no rent, deposit or payment UI anywhere.

/// Tenant rentals home: My Lease, the agent's phone/email, next inspection,
/// finished work waiting for "is it fixed?", and the tenant's actions.
class TenantRentalsHomeScreen extends StatefulWidget {
  const TenantRentalsHomeScreen({super.key});

  @override
  State<TenantRentalsHomeScreen> createState() =>
      _TenantRentalsHomeScreenState();
}

class _TenantRentalsHomeScreenState extends State<TenantRentalsHomeScreen> {
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
      title: 'My rental',
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
    final cards = lease.objs('leases');
    final items = waiting.objs('items');
    final homes = [
      for (final c in cards)
        if (c.obj('lease') != null && c.obj('property')?.integer('id') != null)
          c.obj('property')!,
    ];
    void push(Widget w) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      children: [
        ClientAgencyHeader(api: _api),
        const RentalsQueueBanner(),
        if (items.isNotEmpty)
          RentalsSection(
            title: 'Please check (${waiting.integer('waiting_count') ?? items.length})',
            child: Column(children: [
              for (final i in items)
                RentalsNavRow(
                  icon: TablerIcons.tool,
                  title: i.str('title') ?? 'Finished work',
                  subtitle: 'Is it fixed?',
                  onTap: i.integer('work_order_id') == null
                      ? null
                      : () => push(TenantWorkOrderScreen(
                          workOrderId: i.integer('work_order_id')!)),
                ),
            ]),
          ),
        if (cards.isEmpty)
          const RentalsEmpty(reason: 'No current lease')
        else
          for (final c in cards) MyLeaseCard(card: c),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Wrap(spacing: 10, runSpacing: 10, children: [
            if (homes.isNotEmpty)
              _ActionTile(
                  icon: TablerIcons.alert_triangle,
                  label: 'Report a fault',
                  onTap: () => push(TenantReportFaultScreen(homes: homes))),
            _ActionTile(
                icon: TablerIcons.list_check,
                label: 'My faults',
                onTap: () => push(const TenantFaultsScreen())),
            _ActionTile(
                icon: TablerIcons.file_text,
                label: 'Give notice',
                onTap: () => push(ClientNoticesScreen(api: _api))),
            _ActionTile(
                icon: TablerIcons.files,
                label: 'Documents',
                onTap: () => push(ClientDocumentsScreen(api: _api))),
            _ActionTile(
                icon: TablerIcons.clipboard_check,
                label: 'Inspections',
                onTap: () => push(ClientInspectionsScreen(api: _api))),
            _ActionTile(
                icon: TablerIcons.bell,
                label: 'Notifications',
                onTap: () => push(ClientPushPreferencesScreen(api: _api))),
          ]),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionTile(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final w = (MediaQuery.of(context).size.width.clamp(0, 720) - 42) / 2;
    return SizedBox(
      width: w,
      child: RentalsActionTile(icon: icon, label: label, onTap: onTap),
    );
  }
}

/// Report a fault. Works offline: fault types are cached per home, and the
/// report (with its photos) is queued with one key and its real capture time.
class TenantReportFaultScreen extends StatefulWidget {
  final List<Json> homes;
  const TenantReportFaultScreen({super.key, required this.homes});

  @override
  State<TenantReportFaultScreen> createState() =>
      _TenantReportFaultScreenState();
}

class _TenantReportFaultScreenState extends State<TenantReportFaultScreen> {
  late Json _home = widget.homes.first;
  Json? _types;
  bool _typesOffline = false;
  Object? _typesError;
  Json? _type;
  bool _other = false;
  final Map<int, bool> _ticks = {};
  String? _resolution;
  bool _urgent = false;
  final _title = TextEditingController();
  final _desc = TextEditingController();
  List<XFile> _photos = const [];
  bool _busy = false;

  int get _propertyId => _home.integer('id')!;
  int get _maxPhotos =>
      (_types?.obj('limits')?.integer('max_photos') ?? 6).clamp(1, 10);

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    final session = RentalWriteQueue.instance.sessionKey;
    final key = 'tenant_fault_types:$_propertyId';
    setState(() {
      _types = null;
      _typesError = null;
    });
    try {
      final t = await _api.faultTypes(_propertyId);
      await RentalsCache.write(session, key, t);
      if (mounted) setState(() => _types = t);
    } catch (e) {
      final cached = await RentalsCache.read(session, key);
      if (!mounted) return;
      setState(() {
        _types = cached;
        _typesOffline = cached != null;
        _typesError = cached == null ? e : null;
      });
    }
  }

  void _choose(Json? type, {bool other = false}) {
    setState(() {
      _type = type;
      _other = other;
      _ticks.clear();
      _resolution = other ? 'still_a_problem' : null;
      _urgent = false;
      if (type != null && _title.text.isEmpty) {
        _title.text = type.str('name') ?? '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'Report a fault',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (widget.homes.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<int>(
                initialValue: _propertyId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Which home?'),
                items: [
                  for (final h in widget.homes)
                    DropdownMenuItem(
                        value: h.integer('id'),
                        child: Text(h.str('address') ?? '')),
                ],
                onChanged: (v) {
                  final h = widget.homes.firstWhere((e) => e.integer('id') == v);
                  setState(() => _home = h);
                  _choose(null);
                  _loadTypes();
                },
              ),
            ),
          if (_type == null && !_other) ..._typePicker(context) else ..._form(context),
        ],
      ),
    );
  }

  List<Widget> _typePicker(BuildContext context) {
    if (_typesError != null) {
      return [
        RentalsError(error: _typesError!, onRetry: _loadTypes),
        const SizedBox(height: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => _choose(null, other: true),
          child: const Text('Report it anyway (describe the problem)'),
        ),
      ];
    }
    final types = _types?.objs('fault_types');
    if (types == null) return const [SizedBox(height: 200, child: RentalsLoading())];
    final byCategory = <String, List<Json>>{};
    for (final t in types) {
      byCategory.putIfAbsent(t.str('category') ?? 'Other', () => []).add(t);
    }
    return [
      const BodyText('What is the problem?'),
      if (_typesOffline)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: BodyText('Offline — showing the list this phone last saw.',
              muted: true),
        ),
      const SizedBox(height: 8),
      for (final e in byCategory.entries)
        RentalsSection(
          padding: const EdgeInsets.only(bottom: 12),
          title: e.key,
          child: Column(children: [
            for (final t in e.value)
              RentalsNavRow(
                title: t.str('name') ?? '',
                trailing: t.str('urgency') == 'emergency'
                    ? const RentalsStatusChip('Emergency', statusKey: 'emergency')
                    : null,
                onTap: () => _choose(t),
              ),
          ]),
        ),
      OutlinedButton(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
        onPressed: () => _choose(null, other: true),
        child: const Text('Other — not on the list'),
      ),
    ];
  }

  List<Widget> _form(BuildContext context) {
    final t = _type;
    final steps = (t?['steps'] as List? ?? const []).map((e) => e.toString()).toList();
    final photos = t?.objs('photos') ?? const <Json>[];
    final docs = t?.objs('documents') ?? const <Json>[];
    return [
      Row(children: [
        Expanded(
          child: Text(_other ? 'Other' : (t?.str('name') ?? ''),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
        TextButton(
            onPressed: () => _choose(null), child: const Text('Change')),
      ]),
      if (t?.str('safety_line') != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: RentalsAlert(t!.str('safety_line')!,
              tone: RentalsAlertTone.danger),
        ),
      if (steps.isNotEmpty)
        RentalsSection(
          padding: const EdgeInsets.only(bottom: 12),
          title: 'Try this first',
          child: Column(children: [
            for (var i = 0; i < steps.length; i++)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _ticks[i] ?? false,
                onChanged: (v) => setState(() => _ticks[i] = v ?? false),
                title: Text(steps[i]),
              ),
            if (photos.isNotEmpty)
              RentalsPhotoGrid([
                for (final p in photos)
                  if (p.str('url') != null) p.str('url')!,
              ]),
            for (final d in docs)
              if (d.str('type') == 'video_link' && d.str('url') != null)
                RentalsNavRow(
                  icon: TablerIcons.video,
                  title: d.str('caption') ?? 'Watch how',
                  onTap: () => launchUrl(Uri.parse(d.str('url')!),
                      mode: LaunchMode.externalApplication),
                )
              else if ((d.str('type') == 'pdf' || d.str('type') == 'document') &&
                  d.str('url') != null)
                RentalsNavRow(
                  icon: TablerIcons.file,
                  title: d.str('caption') ?? 'Guide',
                  onTap: () => _openDoc(context, d),
                ),
          ]),
        ),
      if (!_other) ...[
        const BodyText('Is it still a problem?'),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          RentalsChoiceChip(
            label: const Text('Yes, it still needs fixing'),
            selected: _resolution == 'still_a_problem',
            onSelected: (_) => setState(() => _resolution = 'still_a_problem'),
          ),
          if (steps.isNotEmpty)
            RentalsChoiceChip(
              label: const Text('No, the steps fixed it'),
              selected: _resolution == 'first_aid_resolved',
              onSelected: (_) => setState(() {
                _resolution = 'first_aid_resolved';
                _urgent = false;
              }),
            ),
        ]),
        const SizedBox(height: 12),
      ],
      if (_resolution == 'still_a_problem')
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            // A red wash (not an outline) once marked urgent.
            color: _urgent
                ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                : AppTheme.surface2(context),
          ),
          child: SwitchListTile(
            title: const Text('This is urgent / an emergency'),
            subtitle: const Text(
                'Your agent is alerted straight away. Use this for danger, '
                'flooding, no water or power, or a security risk.'),
            value: _urgent,
            onChanged: (v) => setState(() => _urgent = v),
          ),
        ),
      if (_resolution != null) ...[
        if (!_other)
          TextField(
            controller: _title,
            maxLength: 191,
            decoration: const InputDecoration(labelText: 'Short title'),
          ),
        TextField(
          controller: _desc,
          maxLength: 5000,
          minLines: 3,
          maxLines: 8,
          decoration: InputDecoration(
              labelText: _other
                  ? 'Tell us what needs attention (required)'
                  : 'Anything else we should know?'),
        ),
        const SizedBox(height: 8),
        BodyText('Photos (up to $_maxPhotos)', muted: true),
        const SizedBox(height: 8),
        PhotoPickerRow(
          photos: _photos,
          max: _maxPhotos,
          onChanged: (p) => setState(() => _photos = p),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _busy ? null : _submit,
          child: Text(_resolution == 'first_aid_resolved'
              ? 'Let my agent know it is fixed'
              : 'Report fault'),
        ),
      ],
    ];
  }

  Future<void> _openDoc(BuildContext context, Json d) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final f = await _api.downloadDocument(
          d.str('url')!, '${d.str('caption') ?? 'guide'}.pdf');
      await OpenFilex.open(f.path);
    } on RentalsApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_other && _desc.text.trim().isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Tell us what needs attention.')));
      return;
    }
    if (!_other && _title.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Add a short title.')));
      return;
    }
    setState(() => _busy = true);
    final steps = (_type?['steps'] as List? ?? const []).map((e) => '$e').toList();
    final r = await _api.reportFault(
      propertyId: _propertyId,
      faultTypeId: _type?.integer('id'),
      otherType: _other,
      title: _other ? null : _title.text.trim(),
      description: _desc.text.trim(),
      resolution: _resolution!,
      urgent: _urgent,
      selfChecks: [
        for (var i = 0; i < steps.length; i++)
          {'text': steps[i], 'ticked': _ticks[i] ?? false},
      ],
      photos: [for (final p in _photos) p.path],
    );
    if (!mounted) return;
    setState(() => _busy = false);
    final ok = showSubmitOutcome(context, r.outcome,
        sentText: _resolution == 'first_aid_resolved'
            ? 'Thanks — your agent has been told.'
            : _urgent
                ? 'Reported as urgent. Your agent has been alerted.'
                : 'Fault reported.');
    if (ok) Navigator.of(context).pop();
  }
}

class TenantFaultsScreen extends StatelessWidget {
  const TenantFaultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'My faults',
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
                  RentalsEmpty(reason: 'You have not reported any faults.'),
                ]);
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final f = rows[i];
                  final current = f.obj('progress')?.str('current_label');
                  return RentalsListCard(
                    title: f.str('title') ?? 'Fault',
                    subtitle: f.str('fault_type_name'),
                    meta: fmtMoment(f.str('reported_at')),
                    statusLabel: f.str('end_state') ?? current ?? f.str('status'),
                    statusKey: f.str('status'),
                    highlight: f.flag('urgent') && !f.flag('closed'),
                    badges: [
                      if (f.flag('urgent'))
                        const RentalsStatusChip('Urgent', statusKey: 'urgent'),
                    ],
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            TenantFaultDetailScreen(faultId: f.integer('id')!))),
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

class TenantFaultDetailScreen extends StatefulWidget {
  final int faultId;
  const TenantFaultDetailScreen({super.key, required this.faultId});

  @override
  State<TenantFaultDetailScreen> createState() =>
      _TenantFaultDetailScreenState();
}

class _TenantFaultDetailScreenState extends State<TenantFaultDetailScreen> {
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
        builder: (context, d, _) {
          final f = d.obj('fault_report') ?? d;
          final wo = f.obj('work_order_stage');
          final photos = [
            ...f.objs('reported_photos'),
            ...f.objs('photos'),
          ];
          return ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 32),
            children: [
              RentalsQueueBanner(group: 'fault:${widget.faultId}'),
              RentalsSection(
                title: f.str('title') ?? 'Fault',
                trailing: f.flag('urgent')
                    ? const RentalsStatusChip('Urgent', statusKey: 'urgent')
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (f.str('description') != null)
                      BodyText(f.str('description')!),
                    const SizedBox(height: 6),
                    KeyValueRow('Type', f.str('fault_type_name')),
                    KeyValueRow('Reported', fmtMoment(f.str('reported_at'))),
                    KeyValueRow('Result', f.str('end_state')),
                    KeyValueRow('Note', f.str('outcome_note')),
                  ],
                ),
              ),
              if (f.objs('timeline').isNotEmpty)
                RentalsSection(
                    title: 'Progress',
                    child: RentalsTimeline(f.objs('timeline'))),
              if (wo != null)
                RentalsSection(
                  title: 'Repair',
                  child: Column(children: [
                    KeyValueRow('Stage', wo.str('stage_label')),
                    KeyValueRow('Who', wo.str('who_label')),
                    KeyValueRow('Appointment', fmtMoment(wo.str('appointment_at'))),
                    KeyValueRow('Appointment note', wo.str('appointment_note')),
                    if (wo.integer('id') != null)
                      KeyValueRow('Details', 'Open',
                          icon: TablerIcons.chevron_right,
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => TenantWorkOrderScreen(
                                      workOrderId: wo.integer('id')!)))),
                  ]),
                ),
              if (photos.isNotEmpty)
                RentalsSection(
                  title: 'Photos',
                  child: RentalsPhotoGrid([
                    for (final p in photos)
                      if (p.str('url') != null) p.str('url')!,
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  if (f.flag('can_add'))
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44)),
                      icon: const Icon(TablerIcons.message_plus, size: 18),
                      label: const Text('Add a note or photo'),
                      onPressed: () => _addTo(context),
                    ),
                  if (f.flag('can_withdraw'))
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44)),
                      icon: const Icon(TablerIcons.x, size: 18),
                      label: const Text('Withdraw'),
                      onPressed: () => _withdraw(context),
                    ),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addTo(BuildContext context) async {
    final r = await showModalBottomSheet<({String note, List<XFile> photos})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const NotePhotosSheet(title: 'Add to your fault'),
    );
    if (r == null || !context.mounted) return;
    final res = await _api.addToFault(widget.faultId,
        note: r.note, photos: [for (final p in r.photos) p.path]);
    if (!context.mounted) return;
    showSubmitOutcome(context, res.outcome, sentText: 'Sent to your agent.');
    _refresh.value++;
  }

  Future<void> _withdraw(BuildContext context) async {
    final c = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Withdraw this fault?'),
        content: TextField(
          controller: c,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Why? (required)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('Keep it')),
          TextButton(
              onPressed: () => Navigator.pop(d, c.text.trim()),
              child: const Text('Withdraw')),
        ],
      ),
    );
    c.dispose();
    if (reason == null || !context.mounted) return;
    if (reason.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please give a short reason.')));
      return;
    }
    final res = await _api.withdrawFault(widget.faultId, reason);
    if (!context.mounted) return;
    showSubmitOutcome(context, res.outcome, sentText: 'Fault withdrawn.');
    _refresh.value++;
  }
}

/// A note + photos sheet; pops `(note, photos)`.
class NotePhotosSheet extends StatefulWidget {
  final String title;
  final String noteLabel;
  final int minNote;
  final int maxPhotos;
  final bool allowPhotos;
  const NotePhotosSheet({
    super.key,
    required this.title,
    this.noteLabel = 'Note',
    this.minNote = 0,
    this.maxPhotos = 6,
    this.allowPhotos = true,
  });

  @override
  State<NotePhotosSheet> createState() => _NotePhotosSheetState();
}

class _NotePhotosSheetState extends State<NotePhotosSheet> {
  final _note = TextEditingController();
  List<XFile> _photos = const [];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _valid {
    final n = _note.text.trim();
    if (widget.minNote > 0) return n.length >= widget.minNote;
    return n.isNotEmpty || _photos.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                maxLength: 2000,
                minLines: 2,
                maxLines: 5,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: widget.noteLabel),
              ),
              if (widget.allowPhotos)
                PhotoPickerRow(
                    photos: _photos,
                    max: widget.maxPhotos,
                    onChanged: (p) => setState(() => _photos = p)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _valid
                    ? () => Navigator.pop(
                        context, (note: _note.text.trim(), photos: _photos))
                    : null,
                child: const Text('Send'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tenant's view of a repair: stage, appointment, photos, and — when the
/// work is reported finished — "Is it fixed?".
class TenantWorkOrderScreen extends StatefulWidget {
  final int workOrderId;
  const TenantWorkOrderScreen({super.key, required this.workOrderId});

  @override
  State<TenantWorkOrderScreen> createState() => _TenantWorkOrderScreenState();
}

class _TenantWorkOrderScreenState extends State<TenantWorkOrderScreen> {
  final _refresh = ValueNotifier<int>(0);

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'Repair',
      body: RentalsFutureView<Json>(
        refresh: _refresh,
        load: () => _api.workOrder(widget.workOrderId),
        builder: (context, d, _) {
          final w = d.obj('work_order') ?? d;
          final awaiting = w.obj('awaiting_answer');
          return ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 32),
            children: [
              const RentalsQueueBanner(),
              if (awaiting != null)
                RentalsSection(
                  title: 'Is it fixed?',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BodyText(
                          'The work was reported finished'
                          '${awaiting.str('reported_at') == null ? '' : ' on ${fmtMoment(awaiting.str('reported_at'))}'}.'
                          ' Please check it.'),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(TablerIcons.thumb_up),
                            label: const Text('Yes, fixed'),
                            onPressed: () => _answer(context, true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 48)),
                            icon: const Icon(TablerIcons.thumb_down),
                            label: const Text('Not yet'),
                            onPressed: () => _answer(context, false),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              RentalsSection(
                title: w.str('title') ?? 'Repair',
                trailing: RentalsStatusChip(w.str('stage_label') ?? '',
                    statusKey: w.str('stage')),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (w.str('description') != null)
                      BodyText(w.str('description')!),
                    const SizedBox(height: 6),
                    KeyValueRow('Who', w.str('who_label')),
                    KeyValueRow('Appointment', fmtMoment(w.str('appointment_at'))),
                    KeyValueRow('Appointment note', w.str('appointment_note')),
                    KeyValueRow('Completed', fmtMoment(w.str('completed_at'))),
                  ],
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
              if (w.flag('tenant_can_start') ||
                  w.flag('tenant_can_finish') ||
                  w.str('tenant_progress_note') != null)
                RentalsSection(
                  title: 'Tell us how it is going',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (w.str('tenant_progress_note') != null)
                        BodyText(w.str('tenant_progress_note')!, muted: true),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        if (w.flag('tenant_can_start'))
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 44)),
                            onPressed: () => _progress(context, 'started'),
                            child: const Text('The work has started'),
                          ),
                        if (w.flag('tenant_can_finish'))
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 44)),
                            onPressed: () => _progress(context, 'finished'),
                            child: const Text('The work is finished'),
                          ),
                        if (w.flag('tenant_can_finish'))
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 44)),
                            onPressed: () => _progress(context, 'not_fixed'),
                            child: const Text('It is not fixed'),
                          ),
                      ]),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _answer(BuildContext context, bool fixed) async {
    ({String note, List<XFile> photos})? r;
    if (!fixed) {
      r = await showModalBottomSheet<({String note, List<XFile> photos})>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const NotePhotosSheet(
            title: 'What is still wrong?',
            noteLabel: 'Tell us what is still wrong',
            minNote: 5),
      );
      if (r == null) return;
    }
    if (!context.mounted) return;
    final res = await _api.completionResponse(widget.workOrderId,
        fixed: fixed,
        note: r?.note,
        photos: [for (final p in r?.photos ?? const <XFile>[]) p.path]);
    if (!context.mounted) return;
    showSubmitOutcome(context, res.outcome,
        sentText: fixed ? 'Thanks for confirming.' : 'Sent to your agent.');
    _refresh.value++;
  }

  Future<void> _progress(BuildContext context, String action) async {
    ({String note, List<XFile> photos})? r;
    if (action == 'not_fixed') {
      r = await showModalBottomSheet<({String note, List<XFile> photos})>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const NotePhotosSheet(
            title: 'What is still wrong?',
            noteLabel: 'Tell us what is still wrong',
            minNote: 5),
      );
      if (r == null) return;
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(action == 'started'
              ? 'Has the work started?'
              : 'Is the work finished?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Yes')),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!context.mounted) return;
    final res = await _api.workProgress(widget.workOrderId,
        action: action,
        note: r?.note,
        photos: [for (final p in r?.photos ?? const <XFile>[]) p.path]);
    if (!context.mounted) return;
    showSubmitOutcome(context, res.outcome, sentText: 'Thanks — noted.');
    _refresh.value++;
  }
}
