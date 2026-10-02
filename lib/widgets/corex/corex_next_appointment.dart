import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../models/dashboard_data.dart';
import '../../providers/dashboard_provider.dart';
import '../../screens/calendar_screen.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../utils/app_time.dart';
import '../../utils/route_observer.dart';
import 'corex_card.dart';

/// Home hero card: surfaces the next upcoming event on today's calendar and
/// taps through to that event in the Calendar screen. When nothing is left for
/// the day it shows a "schedule is clear" empty state.
///
/// Self-loading: triggers a calendar fetch on init (the range endpoint returns
/// the whole month, which we filter client-side) and rebuilds off
/// [DashboardProvider.events].
///
/// Home stays mounted underneath anything pushed from it (Ellie, Notifications,
/// module screens), so an appointment created there would never reach this
/// card from the init fetch alone. It therefore also re-fetches when:
///  - a route pushed on top of Home pops ([RouteAware.didPopNext]);
///  - the app returns to the foreground;
/// and re-evaluates (no network) once a minute so the card rolls over to the
/// following event as the current one's start time passes.
class CorexNextAppointment extends StatefulWidget {
  const CorexNextAppointment({super.key});

  @override
  State<CorexNextAppointment> createState() => _CorexNextAppointmentState();
}

class _CorexNextAppointmentState extends State<CorexNextAppointment>
    with RouteAware, WidgetsBindingObserver {
  bool _loading = true;
  bool _inFlight = false;
  ModalRoute<void>? _route;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && route != _route) {
      if (_route != null) corexRouteObserver.unsubscribe(this);
      _route = route;
      corexRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    corexRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A screen pushed over Home (Ellie, a module, Notifications) just closed —
  /// it may have created, moved or completed an event.
  @override
  void didPopNext() => _load();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  /// Single-flight: a pop and a resume landing together must not fan out into
  /// parallel fetches. The skeleton only shows for the very first load; later
  /// refreshes swap the card in place.
  Future<void> _load() async {
    if (_inFlight || !mounted) return;
    _inFlight = true;
    try {
      final today = DateTime.now();
      final day = DateTime(today.year, today.month, today.day);
      await context.read<DashboardProvider>().loadEventsRange(
            start: day,
            end: day,
          );
    } finally {
      _inFlight = false;
      if (mounted && _loading) setState(() => _loading = false);
    }
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
        child: Row(
          children: [
            _IconBox(
              color: t.accentSoft,
              child: Icon(
                clear ? TablerIcons.circle_check : TablerIcons.calendar_time,
                color: Theme.of(context).brightness == Brightness.light
                    ? CorexTokens.textPrimary(context)
                    : t.accent,
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
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
    final subtitle = e.propertyAddress ?? e.location ?? e.contactName;
    final isLight = Theme.of(context).brightness == Brightness.light;

    // The hero's time is the one number on the page, so it gets the accent
    // outright — darkened per agency in light mode, where the raw accent
    // usually fails contrast.
    final timeColour = isLight ? t.accentText : t.accent;

    return CorexCard(
      elevated: true,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBox(
                color: colour.withValues(alpha: 0.15),
                child: Icon(
                  TablerIcons.calendar_event,
                  color: isLight ? CorexTokens.textPrimary(context) : colour,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _Eyebrow('NEXT APPOINTMENT'),
                    const SizedBox(height: 4),
                    Text(
                      e.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: CorexTokens.textPrimary(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: CorexTokens.surfaceBorder(context)),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                e.allDay ? 'All day' : _formatTime(jhb(e.eventDate)),
                style: TextStyle(
                  color: timeColour,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  [
                    if (!e.allDay) _relative(e.eventDate),
                    if (subtitle != null && subtitle.isNotEmpty) subtitle,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CorexTokens.textSecondary(context),
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Reads as the card's action, but the whole card is the tap
              // target — this is an affordance, not a second button, so it
              // stays a container and never swallows the tap.
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.accent,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  'Open',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    // `dt` is already converted to Africa/Johannesburg via `jhb()` by the
    // caller. Read its wall-clock fields directly — calling `.toLocal()` here
    // would re-shift to the device's timezone (e.g. UTC), making a 16:00 SA
    // event render as 14:00.
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(CorexTokens.radiusChip),
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
