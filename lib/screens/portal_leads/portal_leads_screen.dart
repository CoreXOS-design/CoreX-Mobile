import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';
import '../../widgets/ui/content_width.dart';

import '../../models/portal_lead.dart';
import '../../providers/portal_leads_provider.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../widgets/corex/corex_card.dart';
import 'portal_lead_detail_screen.dart';

class PortalLeadsScreen extends StatefulWidget {
  const PortalLeadsScreen({super.key});

  @override
  State<PortalLeadsScreen> createState() => _PortalLeadsScreenState();
}

class _PortalLeadsScreenState extends State<PortalLeadsScreen> {
  late DateTime _weekStart; // Sunday of the visible week

  @override
  void initState() {
    super.initState();
    _weekStart = _sundayOf(DateTime.now());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = context.read<PortalLeadsProvider>();
      p.refresh();
    });
  }

  static DateTime _sundayOf(DateTime dt) {
    final d = DateTime(dt.year, dt.month, dt.day);
    // DateTime.weekday: Mon=1..Sun=7. We want Sun=0 offset.
    final offset = d.weekday % 7; // Sun→0, Mon→1, ... Sat→6
    return d.subtract(Duration(days: offset));
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _refresh() => context.read<PortalLeadsProvider>().refresh();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PortalLeadsProvider>();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: CorexTokens.pageBase(context),
        body: Container(
          decoration: BoxDecoration(gradient: CorexTokens.pageBacklight(context)),
          child: ContentSafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context, p),
                _dateStrip(context, p),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: _body(context, p),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, PortalLeadsProvider p) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(TablerIcons.arrow_left,
                  color: CorexTokens.textPrimary(context)),
            ),
            Text(
              'Portal Leads',
              style: TextStyle(
                color: CorexTokens.textPrimary(context),
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const Spacer(),
            if (p.totalUnread > 0) _unreadPill(context, p.totalUnread),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  Widget _unreadPill(BuildContext context, int count) {
    final t = CorexAccentTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: t.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count unread',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _dateStrip(BuildContext context, PortalLeadsProvider p) {
    final lookup = {for (final d in p.dates) d.date: d};
    final today = PortalLeadsProvider.today();
    final selectedDate = p.selectedDate ?? today;
    final todayDt = DateTime.now();
    final thisWeek = _sundayOf(todayDt);

    final week = List.generate(7, (i) {
      final dt = _weekStart.add(Duration(days: i));
      final key = _ymd(dt);
      final meta = lookup[key];
      return _DayCell(
        date: dt,
        ymd: key,
        total: meta?.total ?? 0,
        unread: meta?.unread ?? 0,
      );
    });

    final rangeLabel = _rangeLabel(_weekStart);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        children: [
          Row(
            children: [
              _navArrow(context, TablerIcons.chevron_left, () {
                setState(() {
                  _weekStart =
                      _weekStart.subtract(const Duration(days: 7));
                });
              }),
              Expanded(
                child: Center(
                  child: Text(
                    rangeLabel,
                    style: TextStyle(
                      color: CorexTokens.textSecondary(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
              _navArrow(
                context,
                TablerIcons.chevron_right,
                _weekStart.isBefore(thisWeek)
                    ? () {
                        setState(() {
                          _weekStart =
                              _weekStart.add(const Duration(days: 7));
                        });
                      }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final cell in week) ...[
                Expanded(
                  child: _dateChip(
                    context,
                    cell,
                    cell.ymd == selectedDate,
                    cell.ymd == today,
                    !cell.date.isAfter(todayDt),
                    () {
                      context
                          .read<PortalLeadsProvider>()
                          .loadLeads(date: cell.ymd);
                    },
                  ),
                ),
                if (cell != week.last) const SizedBox(width: 4),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _navArrow(BuildContext context, IconData icon, VoidCallback? onTap) {
    final t = CorexAccentTheme.of(context);
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: enabled
              ? t.accentSoft
              : Colors.white.withValues(alpha: 0.04),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled
              ? t.accent
              : CorexTokens.textTertiary(context).withValues(alpha: 0.5),
        ),
      ),
    );
  }

  String _rangeLabel(DateTime weekStart) {
    final end = weekStart.add(const Duration(days: 6));
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    if (weekStart.month == end.month) {
      return '${months[weekStart.month - 1]} ${weekStart.day} – ${end.day}';
    }
    return '${months[weekStart.month - 1]} ${weekStart.day} – '
        '${months[end.month - 1]} ${end.day}';
  }

  Widget _dateChip(
    BuildContext context,
    _DayCell cell,
    bool selected,
    bool isToday,
    bool tappable,
    VoidCallback onTap,
  ) {
    final t = CorexAccentTheme.of(context);
    final weekday = _weekday(cell.date.weekday).toUpperCase();
    final dayNum = '${cell.date.day}';
    final hasLeads = cell.total > 0;

    final bg = selected
        ? t.accent
        : (isToday ? t.accentSoft : Colors.white.withValues(alpha: 0.04));
    final border = selected
        ? null
        : Border.all(
            color: isToday
                ? t.accent.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.06),
            width: 1,
          );
    final fade = tappable ? 1.0 : 0.35;
    final weekdayColor = (selected
            ? Colors.white.withValues(alpha: 0.85)
            : (isToday ? t.accent : CorexTokens.textTertiary(context)))
        .withValues(alpha: fade);
    final dayColor = (selected
            ? Colors.white
            : CorexTokens.textPrimary(context))
        .withValues(alpha: fade);

    return InkWell(
      onTap: tappable ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: border,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    weekday,
                    style: TextStyle(
                      color: weekdayColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dayNum,
                    style: TextStyle(
                      color: dayColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  // Per-day indicator: dot if has leads, else placeholder
                  // for vertical alignment.
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: hasLeads
                          ? (selected
                              ? Colors.white
                              : (cell.unread > 0
                                  ? t.accentMoney
                                  : t.accent))
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
            if (cell.unread > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  constraints:
                      const BoxConstraints(minWidth: 16, minHeight: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: t.accentMoney,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: CorexTokens.surfaceBase(context),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '${cell.unread}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, PortalLeadsProvider p) {
    if (p.loadingLeads && p.leads.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (p.error != null && p.leads.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Text(
              'Failed to load leads.\nPull to retry.',
              textAlign: TextAlign.center,
              style: TextStyle(color: CorexTokens.textSecondary(context)),
            ),
          ),
        ],
      );
    }
    if (p.leads.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Column(
              children: [
                Icon(TablerIcons.inbox,
                    size: 40, color: CorexTokens.textTertiary(context)),
                const SizedBox(height: 10),
                Text(
                  'No leads on this day.',
                  style: TextStyle(
                      color: CorexTokens.textSecondary(context),
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
      itemCount: p.leads.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _LeadRow(lead: p.leads[i]),
    );
  }

  static String _weekday(int wd) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[(wd - 1).clamp(0, 6)];
  }
}

class _DayCell {
  final DateTime date;
  final String ymd;
  final int total;
  final int unread;
  const _DayCell({
    required this.date,
    required this.ymd,
    required this.total,
    required this.unread,
  });
}

class _LeadRow extends StatelessWidget {
  final PortalLead lead;
  const _LeadRow({required this.lead});

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    final isP24 = lead.portal == 'p24';
    final chipBg = isP24
        ? const Color(0xFFE11D2A).withValues(alpha: 0.14)
        : const Color(0xFF2563EB).withValues(alpha: 0.14);
    final chipFg =
        isP24 ? const Color(0xFFE11D2A) : const Color(0xFF2563EB);
    final subtitleParts = <String>[
      if (lead.phone != null && lead.phone!.isNotEmpty) lead.phone!,
      if (lead.email != null && lead.email!.isNotEmpty) lead.email!,
    ];
    final listingLine = [
      if (lead.listingPortalRef != null && lead.listingPortalRef!.isNotEmpty)
        lead.listingPortalRef!,
      if (lead.listingTitle != null && lead.listingTitle!.isNotEmpty)
        lead.listingTitle!,
    ].join(' · ');

    return CorexCard(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PortalLeadDetailScreen(leadId: lead.id),
      )),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lead.isUnread)
            Container(
              margin: const EdgeInsets.only(top: 6, right: 8),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: t.accent,
                shape: BoxShape.circle,
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: chipBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isP24 ? 'P24' : 'PP',
                        style: TextStyle(
                          color: chipFg,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        lead.name?.trim().isNotEmpty == true
                            ? lead.name!
                            : '(no name)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: CorexTokens.textPrimary(context),
                          fontSize: 14,
                          fontWeight: lead.isUnread
                              ? FontWeight.w800
                              : FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      _relative(lead.receivedAt),
                      style: TextStyle(
                        color: CorexTokens.textTertiary(context),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (subtitleParts.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitleParts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: CorexTokens.textSecondary(context),
                      fontSize: 12,
                    ),
                  ),
                ],
                if (listingLine.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    listingLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: CorexTokens.textTertiary(context),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _relative(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}';
  }
}
