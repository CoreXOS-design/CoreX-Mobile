import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../../services/rentals/client_rentals_api.dart';
import '../../../services/rentals/rentals_http.dart';
import '../../../theme/corex_tokens.dart';
import '../../../widgets/notifications_blocked_notice.dart';
import '../widgets/rentals_ui.dart';

// Screens both the tenant and the owner use. Wording, labels and empty states
// come from the server; the app keeps everything neutral (no agency name is
// hardcoded — the header shows `GET /client/rentals/branding`).

/// Agency logo + name for a client rentals screen header.
class ClientAgencyHeader extends StatelessWidget {
  final ClientRentalsApi api;
  const ClientAgencyHeader({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Json>(
      future: api.branding().catchError((_) => <String, dynamic>{}),
      builder: (context, snap) {
        final b = snap.data?.obj('branding');
        if (b == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(children: [
            if (b.str('logo_url') != null)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(b.str('logo_url')!,
                      height: 28,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                ),
              ),
            Expanded(
              child: Text(b.str('name') ?? '',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: CorexTokens.textSecondary(context))),
            ),
          ]),
        );
      },
    );
  }
}

/// One My Lease card: lease facts only — dates, time left, status, notice
/// period (only when the lease states one), the agent's phone and email (or
/// the office's) and the next inspection. Never rent, deposit or payments.
class MyLeaseCard extends StatelessWidget {
  final Json card;

  /// Owner only: the tenant's names.
  final bool showTenantNames;

  const MyLeaseCard(
      {super.key, required this.card, this.showTenantNames = false});

  @override
  Widget build(BuildContext context) {
    final lease = card.obj('lease');
    final status = card.obj('status');
    final notice = card.obj('notice');
    final period = card.obj('notice_period');
    final agent = card.obj('agent');
    final office = card.obj('office');
    final next = card.obj('next_inspection');
    final contact = agent ?? office;
    return RentalsSection(
      title: card.obj('property')?.str('address') ?? 'My lease',
      trailing: status == null
          ? null
          : RentalsStatusChip(status.str('headline') ?? '',
              statusKey: status.str('state')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lease == null || status == null)
            const BodyText('No current lease', muted: true)
          else ...[
            if (status.str('detail') != null) BodyText(status.str('detail')!),
            const SizedBox(height: 6),
            if (showTenantNames) KeyValueRow('Tenant', card.str('tenant_names')),
            KeyValueRow('Started', fmtDate(lease.str('start_date'))),
            KeyValueRow(
                'Ends',
                lease.flag('is_month_to_month')
                    ? 'Month to month'
                    : fmtDate(lease.str('end_date'))),
            KeyValueRow('Time left', lease.obj('time_left')?.str('text')),
            if (period != null)
              KeyValueRow('Notice period',
                  '${period.integer('value') ?? period.str('value')} ${period.str('unit') ?? ''}'),
            if (notice != null)
              KeyValueRow(
                  'Notice',
                  [
                    notice.str('given_by') == 'you'
                        ? 'You gave notice'
                        : 'Notice has been given',
                    if (notice.str('move_out_date') != null)
                      'move-out ${fmtDate(notice.str('move_out_date'))}',
                  ].join(' · ')),
            if (card.obj('renewal') != null)
              KeyValueRow(
                  'Renewal',
                  [
                    fmtDate(card.obj('renewal')!.str('start_date')),
                    fmtDate(card.obj('renewal')!.str('end_date')),
                  ].where((e) => e.isNotEmpty).join(' – ')),
          ],
          if (next != null)
            KeyValueRow(
                'Next inspection',
                [
                  next.str('type_label'),
                  fmtDate(next.str('date')),
                  next.str('time'),
                ].whereType<String>().where((e) => e.isNotEmpty).join(' · ')),
          if (contact != null) ...[
            const Divider(height: 20),
            KeyValueRow(agent != null ? 'Your agent' : 'Office',
                agent?.str('name') ?? 'Agency office'),
            // Phone and email only (no WhatsApp) — Johan's ruling.
            KeyValueRow('Phone', contact.str('phone'),
                icon: TablerIcons.phone,
                onTap: contact.str('phone') == null
                    ? null
                    : () => dialPhone(contact.str('phone')!)),
            KeyValueRow('Email', contact.str('email'),
                icon: TablerIcons.mail,
                onTap: contact.str('email') == null
                    ? null
                    : () => sendEmail(contact.str('email')!)),
          ],
        ],
      ),
    );
  }
}

/// Documents shared with this person; tap to open (downloaded with the
/// session token — the links are not public).
class ClientDocumentsScreen extends StatelessWidget {
  final ClientRentalsApi api;
  const ClientDocumentsScreen({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'Documents',
      body: RentalsPagedList<Json>(
        searchHint: 'Search documents',
        fetch: (page, q) async {
          final body = await api.documents(page: page, q: q['q']);
          final meta = body.obj('meta') ?? const {};
          return PagedResult<Json>(
            items: body.objs('documents'),
            page: meta.integer('page') ?? page,
            lastPage: meta.integer('pages') ?? page,
            total: meta.integer('total') ?? 0,
            emptyReason: 'No documents have been shared with you yet.',
          );
        },
        itemBuilder: (context, d) => RentalsListCard(
          title: d.str('name') ?? d.str('file_name') ?? 'Document',
          subtitle: [d.str('type'), d.obj('belongs_to')?.str('address')]
              .whereType<String>()
              .join(' · '),
          meta: fmtMoment(d.str('date') ?? d.str('uploaded_at')),
          onTap: () => _open(context, d),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, Json d) async {
    final url = d.str('view_url');
    if (url == null) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Opening…')));
    try {
      final f = await api.downloadDocument(
          url, d.str('file_name') ?? 'document-${d.integer('id')}');
      await OpenFilex.open(f.path);
    } on RentalsApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// Only the notifications the server lists as switchable. Mandatory ones
/// (decisions, appointments, work checks, notice outcomes) never get a switch.
class ClientPushPreferencesScreen extends StatefulWidget {
  final ClientRentalsApi api;
  const ClientPushPreferencesScreen({super.key, required this.api});

  @override
  State<ClientPushPreferencesScreen> createState() =>
      _ClientPushPreferencesScreenState();
}

class _ClientPushPreferencesScreenState
    extends State<ClientPushPreferencesScreen> {
  List<Json>? _items;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.pushPreferences();
      if (mounted) setState(() => _items = r.objs('switchable'));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _set(Json item, bool v) async {
    final key = item.str('key');
    if (key == null) return;
    setState(() => item['enabled'] = v);
    final res = await runAction(
        context, () => widget.api.setPushPreferences({key: v}));
    if (!mounted) return;
    if (res == null) {
      setState(() => item['enabled'] = !v);
    } else {
      setState(() => _items = res.objs('switchable'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return RentalsPage(
      title: 'Rental notifications',
      body: _error != null
          ? RentalsError(error: _error!, onRetry: () {
              setState(() => _error = null);
              _load();
            })
          : items == null
              ? const RentalsLoading()
              : ListView(
                  padding: const EdgeInsets.only(top: 8),
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: NotificationsBlockedNotice(),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: BodyText(
                          'Notifications about decisions, appointments, '
                          'finished work and notice outcomes are always sent.',
                          muted: true),
                    ),
                    if (items.isEmpty)
                      const RentalsEmpty(
                          reason: 'There is nothing to switch off.'),
                    for (final i in items)
                      SwitchListTile(
                        title: Text(i.str('label') ?? ''),
                        subtitle: i.str('description') == null
                            ? null
                            : Text(i.str('description')!),
                        value: i.flag('enabled'),
                        onChanged: (v) => _set(i, v),
                      ),
                  ],
                ),
    );
  }
}

/// Notices this person gave, plus "give notice" on an active lease. For the
/// tenant, a notice the owner gave reads only "Notice has been given".
class ClientNoticesScreen extends StatefulWidget {
  final ClientRentalsApi api;
  const ClientNoticesScreen({super.key, required this.api});

  @override
  State<ClientNoticesScreen> createState() => _ClientNoticesScreenState();
}

class _ClientNoticesScreenState extends State<ClientNoticesScreen> {
  final _refresh = ValueNotifier<int>(0);

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'Notice',
      body: RentalsFutureView<Json>(
        refresh: _refresh,
        load: widget.api.notices,
        builder: (context, d, _) {
          final leases = d.objs('leases');
          final mine = d.objs('notices');
          final other = d.objs('from_other_party');
          return ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 32),
            children: [
              for (final l in leases)
                RentalsSection(
                  title: l.str('address') ?? 'Lease',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      KeyValueRow(
                          'Ends',
                          l.flag('is_month_to_month')
                              ? 'Month to month'
                              : fmtDate(l.str('end_date'))),
                      if (l.flag('waiting'))
                        const BodyText(
                            'Your notice is with your agent for review.',
                            muted: true)
                      else if (!l.flag('has_notice'))
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 44)),
                            icon: const Icon(TablerIcons.file_text),
                            label: const Text('Give notice'),
                            onPressed: () => _give(context, l),
                          ),
                        ),
                    ],
                  ),
                ),
              if (mine.isNotEmpty)
                RentalsSection(
                  title: 'Notices you gave',
                  child: Column(children: [
                    for (final n in mine)
                      KeyValueRow(n.str('address') ?? '',
                          n.str('status_line') ?? n.str('status_label')),
                  ]),
                ),
              if (other.isNotEmpty)
                RentalsSection(
                  title: 'Notices on your lease',
                  child: Column(children: [
                    for (final n in other)
                      KeyValueRow(
                        n.str('address') ?? '',
                        // The tenant is told nothing about the owner — not
                        // even who gave the notice.
                        widget.api.isOwner
                            ? n.str('status_line')
                            : 'Notice has been given. The lease ends '
                                '${fmtDate(n.str('end_date'))}.',
                      ),
                  ]),
                ),
              if (leases.isEmpty && mine.isEmpty && other.isEmpty)
                const RentalsEmpty(
                    reason: 'Notice can be given on a lease that is running.'),
            ],
          );
        },
      ),
    );
  }

  Future<void> _give(BuildContext context, Json lease) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _GiveNoticeSheet(api: widget.api, lease: lease),
    );
    if (done == true) _refresh.value++;
  }
}

class _GiveNoticeSheet extends StatefulWidget {
  final ClientRentalsApi api;
  final Json lease;
  const _GiveNoticeSheet({required this.api, required this.lease});
  @override
  State<_GiveNoticeSheet> createState() => _GiveNoticeSheetState();
}

class _GiveNoticeSheetState extends State<_GiveNoticeSheet> {
  final DateTime _date = DateTime.now();
  DateTime? _end;
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
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
              Text('Give notice',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              BodyText(widget.lease.str('address') ?? '', muted: true),
              const SizedBox(height: 4),
              const BodyText(
                  'Your notice goes to your agent, who reviews it and lets you '
                  'know.',
                  muted: true),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: const Icon(TablerIcons.calendar),
                label: Text(_end == null
                    ? 'When do you want to move out / end?'
                    : 'Ending ${fmtDate(ymd(_end!))}'),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    firstDate: _date.add(const Duration(days: 1)),
                    lastDate: _date.add(const Duration(days: 730)),
                    initialDate: _date.add(const Duration(days: 30)),
                  );
                  if (d != null) setState(() => _end = d);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                maxLength: 2000,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Reason (optional)'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _end == null || _busy ? null : _submit,
                child: const Text('Send notice'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final r = await widget.api.giveNotice(
      leaseId: widget.lease.integer('id')!,
      noticeDate: ymd(_date),
      intendedEndDate: ymd(_end!),
      reason: _reason.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    final ok = showSubmitOutcome(context, r.outcome,
        sentText: 'Your notice has been sent to your agent.');
    if (ok) Navigator.pop(context, true);
  }
}
