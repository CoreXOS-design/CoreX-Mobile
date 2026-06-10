import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../models/dashboard_data.dart';
import '../../providers/dashboard_provider.dart';
import '../../screens/calendar_screen.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../utils/app_time.dart';
import 'corex_card.dart';
import 'corex_chip.dart';

/// Home hero card: surfaces the next upcoming event on today's calendar and
/// taps through to that event in the Calendar screen. When nothing is left for
/// the day it shows a "schedule is clear" empty state.
///
/// Self-loading: triggers a calendar fetch on init (the range endpoint returns
/// the whole month, which we filter client-side) and rebuilds off
/// [DashboardProvider.events].
class CorexNextAppointment extends StatefulWidget {
  const CorexNextAppointment({super.key});

  @override
  State<CorexNextAppointment> createState() => _CorexNextAppointmentState();
}

class _CorexNextAppointmentState extends State<CorexNextAppointment> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    await context.read<DashboardProvider>().loadEventsRange(
          start: day,
          end: day,
        );
    if (mounted) setState(() => _loading = false);
  }

  /// First event today whose start is still ahead of now, earliest first.
  CalendarEvent? _nextToday(List<CalendarEvent> events) {
    final now = jhb(DateTime.now());
    final upcoming = events.where((e) {
      final d = jhb(e.eventDate);
      return d.year == now.year &&
          d.month == now.month &&
          d.day == now.day &&
          (e.allDay || d.isAfter(now));
    }).toList()
      ..sort((a, b) => a.eventDate.compareTo(b.eventDate));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  void _openInCalendar(CalendarEvent event) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CalendarScreen(
          initialDate: jhb(event.eventDate),
          openEventId: event.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final events = context.watch<DashboardProvider>().events;
    final next = _nextToday(events);

    if (_loading) return const _AppointmentShell(state: _ShellState.loading);
    if (next == null) return const _AppointmentShell(state: _ShellState.clear);

    return _AppointmentShell(
      state: _ShellState.event,
      event: next,
      onTap: () => _openInCalendar(next),
    );
  }
}

enum _ShellState { loading, clear, event }

class _AppointmentShell extends StatelessWidget {
  final _ShellState state;
  final CalendarEvent? event;
  final VoidCallback? onTap;

  const _AppointmentShell({required this.state, this.event, this.onTap});

  Color _eventColour() {
    try {
      return Color(int.parse(event!.colour.replaceFirst('#', '0xFF')));
    } catch (_) {
      return const Color(0xFF6B7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);

    if (state != _ShellState.event) {
      final clear = state == _ShellState.clear;
      return CorexCard(
        accent: true,
        child: Row(
          children: [
            _IconBox(
              color: t.accentSoft,
              child: Icon(
                clear ? TablerIcons.circle_check : TablerIcons.calendar_time,
                color: t.accent,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _Eyebrow('NEXT APPOINTMENT'),
                  const SizedBox(height: 4),
                  Text(
                    clear
                        ? 'Your schedule is clear for the rest of the day'
                        : 'Checking your schedule…',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: CorexTokens.textPrimary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final e = event!;
    final colour = _eventColour();
    final chips = <Widget>[
      CorexChip(
        label: e.allDay ? 'All day' : _formatTime(jhb(e.eventDate)),
        variant: CorexChipVariant.accent,
      ),
      if (!e.allDay) CorexChip(label: _relative(e.eventDate)),
    ];
    final subtitle = e.propertyAddress ?? e.location ?? e.contactName;

    return CorexCard(
      accent: true,
      onTap: onTap,
      child: Row(
        children: [
          _IconBox(
            color: colour.withValues(alpha: 0.14),
            child: Icon(TablerIcons.calendar_event, color: colour, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Eyebrow('NEXT APPOINTMENT'),
                const SizedBox(height: 4),
                Text(
                  e.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CorexTokens.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: CorexTokens.textSecondary(context),
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: chips),
              ],
            ),
          ),
          Icon(
            TablerIcons.chevron_right,
            size: 18,
            color: CorexTokens.textTertiary(context),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    // Stored times are UTC; show them in the device's local timezone.
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  /// "Now" / "in 45 min" / "in 2h" / "in 2h 15m" — scoped to today.
  String _relative(DateTime dt) {
    final diff = dt.difference(DateTime.now());
    if (diff.inMinutes <= 0) return 'Now';
    if (diff.inMinutes < 60) return 'in ${diff.inMinutes} min';
    final hours = diff.inHours;
    final mins = diff.inMinutes % 60;
    return mins == 0 ? 'in ${hours}h' : 'in ${hours}h ${mins}m';
  }
}

class _IconBox extends StatelessWidget {
  final Color color;
  final Widget child;
  const _IconBox({required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}

class _Eyebrow extends StatelessWidget {
  final String label;
  const _Eyebrow(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: CorexTokens.textTertiary(context),
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }
}
