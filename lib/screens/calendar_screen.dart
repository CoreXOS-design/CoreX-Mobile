import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';
import '../theme.dart';
import '../theme/corex_tokens.dart';
import '../widgets/corex/corex_bottom_nav.dart';
import '../providers/dashboard_provider.dart';
import '../models/dashboard_data.dart';
import '../widgets/event_card.dart';
import 'calendar/event_action_sheet.dart';
import 'calendar/invitations_screen.dart';
import 'shared/quick_add_sheet.dart';

class CalendarScreen extends StatefulWidget {
  final bool embedded;
  final DateTime? initialDate;
  final int? openEventId;
  const CalendarScreen({
    super.key,
    this.embedded = false,
    this.initialDate,
    this.openEventId,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

enum _CalView { month, week, day, agenda }

class _CalendarScreenState extends State<CalendarScreen>
    with WidgetsBindingObserver {
  late DateTime _currentMonth;
  // Spec: default view = Day.
  _CalView _view = _CalView.day;
  DateTime? _selectedDate;
  // Agenda forward-pagination window (months from `_currentMonth`).
  final int _agendaWindowMonths = 2;

  @override
  void initState() {
    super.initState();
    final anchor = widget.initialDate ?? DateTime.now();
    _currentMonth = DateTime(anchor.year, anchor.month);
    _selectedDate = DateTime(anchor.year, anchor.month, anchor.day);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _reload();
      if (!mounted) return;
      context.read<DashboardProvider>().loadInvitations();
      final openId = widget.openEventId;
      if (openId != null) {
        final events = context.read<DashboardProvider>().events;
        CalendarEvent? match;
        for (final e in events) {
          if (e.id == openId) {
            match = e;
            break;
          }
        }
        if (match != null && mounted) {
          await showEventActionsSheet(context, match);
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _reload();
    }
  }

  /// Compute the visible-window range for the current view, with +1 day
  /// padding on either side as the spec requires.
  ({DateTime start, DateTime end}) _visibleRange() {
    switch (_view) {
      case _CalView.month:
        final first = DateTime(_currentMonth.year, _currentMonth.month, 1);
        final last =
            DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
        return (
          start: first.subtract(const Duration(days: 1)),
          end: last.add(const Duration(days: 1)),
        );
      case _CalView.week:
        final anchor = _selectedDate ?? DateTime.now();
        final monday = anchor.subtract(Duration(days: anchor.weekday - 1));
        return (
          start: monday.subtract(const Duration(days: 1)),
          end: monday.add(const Duration(days: 7)),
        );
      case _CalView.day:
        final anchor = _selectedDate ?? DateTime.now();
        return (
          start: anchor.subtract(const Duration(days: 1)),
          end: anchor.add(const Duration(days: 1)),
        );
      case _CalView.agenda:
        return (
          start: _currentMonth.subtract(const Duration(days: 1)),
          end: DateTime(
              _currentMonth.year, _currentMonth.month + _agendaWindowMonths, 0),
        );
    }
  }

  Future<void> _reload() async {
    final r = _visibleRange();
    await context
        .read<DashboardProvider>()
        .loadEventsRange(start: r.start, end: r.end);
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
      _selectedDate = null;
    });
    _reload();
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
      _selectedDate = null;
    });
    _reload();
  }

  void _shiftDays(int days) {
    setState(() {
      final anchor = _selectedDate ?? DateTime.now();
      _selectedDate = anchor.add(Duration(days: days));
      // Keep month header aligned with whatever the anchor is now in.
      _currentMonth =
          DateTime(_selectedDate!.year, _selectedDate!.month);
    });
    _reload();
  }

  void _changeView(_CalView v) {
    setState(() {
      _view = v;
      if (v == _CalView.week || v == _CalView.day) {
        _selectedDate ??= DateTime.now();
      }
    });
    _reload();
  }

  Widget _buildBody(BuildContext context, List<CalendarEvent> events) {
    return Column(
        children: [
          // Sticky two-row header — keeps the month name big and the
          // chevrons/Today/view-toggle/invitations evenly spaced beneath it.
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
            decoration: BoxDecoration(
              color: AppTheme.background(context),
              border: Border(
                  bottom: BorderSide(color: AppTheme.borderColor(context))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      _monthName(_currentMonth),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary(context)),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Invitations',
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.mail_outline),
                        if (context
                                .watch<DashboardProvider>()
                                .pendingInvitationCount >
                            0)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                  color: Colors.amber,
                                  shape: BoxShape.circle),
                            ),
                          ),
                      ],
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const InvitationsScreen()),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  _RoundIconBtn(
                      icon: Icons.chevron_left, onTap: _previousMonth),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _currentMonth =
                            DateTime(DateTime.now().year, DateTime.now().month);
                        _selectedDate = DateTime.now();
                      });
                      _reload();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.surface(context),
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        border: Border.all(
                            color: AppTheme.borderColor(context)),
                      ),
                      child: Text('Today',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary(context))),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _RoundIconBtn(
                      icon: Icons.chevron_right, onTap: _nextMonth),
                  const Spacer(),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                      border:
                          Border.all(color: AppTheme.borderColor(context)),
                    ),
                    child: Row(children: [
                      _ViewToggle(
                          label: 'M',
                          active: _view == _CalView.month,
                          onTap: () => _changeView(_CalView.month)),
                      _ViewToggle(
                          label: 'W',
                          active: _view == _CalView.week,
                          onTap: () => _changeView(_CalView.week)),
                      _ViewToggle(
                          label: 'D',
                          active: _view == _CalView.day,
                          onTap: () => _changeView(_CalView.day)),
                      _ViewToggle(
                          label: 'A',
                          active: _view == _CalView.agenda,
                          onTap: () => _changeView(_CalView.agenda)),
                    ]),
                  ),
                ]),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: _renderView(events),
            ),
          ),
        ],
    );
  }

  Widget _renderView(List<CalendarEvent> events) {
    switch (_view) {
      case _CalView.month:
        return _MonthView(
          currentMonth: _currentMonth,
          events: events,
          selectedDate: _selectedDate,
          onDateSelected: (date) => setState(() => _selectedDate = date),
          onSwipeLeft: _nextMonth,
          onSwipeRight: _previousMonth,
        );
      case _CalView.week:
        return _WeekView(
          anchor: _selectedDate ?? DateTime.now(),
          events: events,
          onShift: _shiftDays,
        );
      case _CalView.day:
        return _DayView(
          day: _selectedDate ?? DateTime.now(),
          events: events,
          onShift: _shiftDays,
        );
      case _CalView.agenda:
        return _AgendaView(events: events);
    }
  }

  Widget _buildFab(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'calendar_fab',
      onPressed: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const QuickAddSheet(initialMode: 'event'),
      ),
      backgroundColor: AppTheme.brand,
      child: const Icon(Icons.add, color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    final events = context.watch<DashboardProvider>().events;

    if (widget.embedded) {
      return Stack(
        children: [
          _buildBody(context, events),
          Positioned(right: 16, bottom: 16, child: _buildFab(context)),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      bottomNavigationBar: CorexBottomNav(
        active: CorexNavTab.calendar,
        onTap: (tab) =>
            corexNavigateTo(context, tab, CorexNavTab.calendar),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(
                        TablerIcons.arrow_left,
                        color: CorexTokens.textPrimary(context),
                      ),
                    ),
                    Text(
                      'Calendar',
                      style: TextStyle(
                        color: CorexTokens.textPrimary(context),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: _buildBody(context, events)),
          ],
        ),
      ),
      floatingActionButton: _buildFab(context),
    );
  }

  String _monthName(DateTime dt) {
    const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    return '${months[dt.month - 1]} ${dt.year}';
  }
}

class _RoundIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppTheme.surface(context),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
        child: Icon(icon, size: 20, color: AppTheme.textSecondary(context)),
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ViewToggle({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppTheme.brand : AppTheme.surface(context),
          borderRadius: BorderRadius.circular(AppTheme.radius - 1),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: active ? Colors.white : AppTheme.textSecondary(context))),
      ),
    );
  }
}

class _MonthView extends StatelessWidget {
  final DateTime currentMonth;
  final List<CalendarEvent> events;
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final VoidCallback onSwipeLeft;
  final VoidCallback onSwipeRight;

  const _MonthView({
    required this.currentMonth,
    required this.events,
    this.selectedDate,
    required this.onDateSelected,
    required this.onSwipeLeft,
    required this.onSwipeRight,
  });

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(currentMonth.year, currentMonth.month, 1);
    final startWeekday = firstDay.weekday; // 1=Mon
    final daysInMonth = DateTime(currentMonth.year, currentMonth.month + 1, 0).day;
    final today = DateTime.now();

    // Group events by day
    final byDay = <int, List<CalendarEvent>>{};
    for (final e in events) {
      if (e.eventDate.year == currentMonth.year && e.eventDate.month == currentMonth.month) {
        byDay.putIfAbsent(e.eventDate.day, () => []).add(e);
      }
    }

    // Selected day events
    final selectedDayEvents = selectedDate != null ? (byDay[selectedDate!.day] ?? []) : <CalendarEvent>[];

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null) {
          if (details.primaryVelocity! < -200) onSwipeLeft();
          if (details.primaryVelocity! > 200) onSwipeRight();
        }
      },
      child: Column(
        children: [
          // Day headers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: ['M','T','W','T','F','S','S'].map((d) =>
                Expanded(child: Center(child: Text(d, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.textMuted(context))))),
              ).toList(),
            ),
          ),

          // Calendar grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: 42,
              itemBuilder: (context, index) {
                final dayOffset = index - (startWeekday - 1);
                if (dayOffset < 0 || dayOffset >= daysInMonth) {
                  return const SizedBox.shrink();
                }
                final day = dayOffset + 1;
                final isToday = today.year == currentMonth.year && today.month == currentMonth.month && today.day == day;
                final isSelected = selectedDate?.day == day && selectedDate?.month == currentMonth.month;
                final dayEvents = byDay[day] ?? [];

                return GestureDetector(
                  onTap: () => onDateSelected(DateTime(currentMonth.year, currentMonth.month, day)),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.brandDark : (isToday ? AppTheme.brand.withValues(alpha: 0.12) : null),
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: isToday ? AppTheme.brand : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '$day',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isToday || isSelected ? FontWeight.w600 : FontWeight.w400,
                                color: isToday ? Colors.white : AppTheme.textPrimary(context),
                              ),
                            ),
                          ),
                        ),
                        if (dayEvents.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: dayEvents.take(3).map((e) {
                              Color dotColor;
                              try {
                                dotColor = Color(int.parse(e.colour.replaceFirst('#', '0xFF')));
                              } catch (_) {
                                dotColor = const Color(0xFF6b7280);
                              }
                              return Container(
                                width: 5, height: 5,
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Selected day events
          if (selectedDate != null)
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: AppTheme.surface(context),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border(top: BorderSide(color: AppTheme.borderColor(context))),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        children: [
                          Text(
                            _formatSelectedDate(selectedDate!),
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary(context)),
                          ),
                          const Spacer(),
                          Text('${selectedDayEvents.length} events', style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context))),
                        ],
                      ),
                    ),
                    Expanded(
                      child: selectedDayEvents.isEmpty
                          ? Center(child: Text('No events', style: TextStyle(fontSize: 13, color: AppTheme.textMuted(context))))
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                              itemCount: selectedDayEvents.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final event = selectedDayEvents[i];
                                return EventCard(
                                  event: event,
                                  onComplete: () => context.read<DashboardProvider>().completeEvent(event.id),
                                  onTap: () => showEventActionsSheet(context, event),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: Center(
                child: Text('Tap a day to see events', style: TextStyle(fontSize: 13, color: AppTheme.textMuted(context))),
              ),
            ),
        ],
      ),
    );
  }

  String _formatSelectedDate(DateTime dt) {
    const days = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    return '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]}';
  }
}

class _AgendaView extends StatelessWidget {
  final List<CalendarEvent> events;
  const _AgendaView({required this.events});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: AppTheme.surface(context), shape: BoxShape.circle),
              child: Icon(Icons.calendar_today_rounded, color: AppTheme.textMuted(context), size: 28),
            ),
            const SizedBox(height: 12),
            Text('No events this month', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textSecondary(context))),
          ],
        ),
      );
    }

    // Group by date
    final grouped = <String, List<CalendarEvent>>{};
    for (final e in events) {
      final key = '${e.eventDate.year}-${e.eventDate.month.toString().padLeft(2, '0')}-${e.eventDate.day.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(key, () => []).add(e);
    }
    final sortedKeys = grouped.keys.toList()..sort();
    final today = DateTime.now();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      itemCount: sortedKeys.length,
      itemBuilder: (context, i) {
        final dateKey = sortedKeys[i];
        final dayEvents = grouped[dateKey]!;
        final date = DateTime.parse(dateKey);
        final isToday = date.year == today.year && date.month == today.month && date.day == today.day;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  if (isToday)
                    Container(
                      width: 8, height: 8,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(color: AppTheme.brand, shape: BoxShape.circle),
                    ),
                  Text(
                    isToday ? 'Today · ${_formatAgendaDate(date)}' : _formatAgendaDate(date),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isToday ? AppTheme.brand : AppTheme.textSecondary(context)),
                  ),
                ],
              ),
            ),
            ...dayEvents.map((event) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: EventCard(
                event: event,
                onComplete: () => context.read<DashboardProvider>().completeEvent(event.id),
                onTap: () => showEventActionsSheet(context, event),
              ),
            )),
          ],
        );
      },
    );
  }

  String _formatAgendaDate(DateTime dt) {
    const days = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    return '${days[dt.weekday - 1]} · ${dt.day} ${months[dt.month - 1]}';
  }
}

/// Week view — strip of 7 day-pills above an event list for the focused day.
/// Horizontal swipe shifts the week by 7 days. The focused day is the
/// `anchor`; tapping a pill in the strip moves focus within the week.
class _WeekView extends StatefulWidget {
  final DateTime anchor;
  final List<CalendarEvent> events;
  final ValueChanged<int> onShift;
  const _WeekView({required this.anchor, required this.events, required this.onShift});

  @override
  State<_WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends State<_WeekView> {
  late DateTime _focus;

  @override
  void initState() {
    super.initState();
    _focus = widget.anchor;
  }

  @override
  void didUpdateWidget(covariant _WeekView old) {
    super.didUpdateWidget(old);
    if (old.anchor != widget.anchor) _focus = widget.anchor;
  }

  DateTime get _weekStart {
    // Monday-anchored.
    final wd = _focus.weekday;
    return DateTime(_focus.year, _focus.month, _focus.day).subtract(Duration(days: wd - 1));
  }

  @override
  Widget build(BuildContext context) {
    final start = _weekStart;
    final days = List.generate(7, (i) => start.add(Duration(days: i)));
    final focusedEvents = widget.events.where((e) =>
        e.eventDate.year == _focus.year &&
        e.eventDate.month == _focus.month &&
        e.eventDate.day == _focus.day).toList()
      ..sort((a, b) => a.eventDate.compareTo(b.eventDate));

    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -200) widget.onShift(7);
        if (v > 200) widget.onShift(-7);
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
            child: Row(
              children: days.map((d) {
                final isFocus = d.year == _focus.year && d.month == _focus.month && d.day == _focus.day;
                final dayCount = widget.events.where((e) =>
                    e.eventDate.year == d.year &&
                    e.eventDate.month == d.month &&
                    e.eventDate.day == d.day).length;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _focus = d),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isFocus ? AppTheme.brand : AppTheme.surface(context),
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                      ),
                      child: Column(
                        children: [
                          Text(['M','T','W','T','F','S','S'][d.weekday - 1],
                              style: TextStyle(
                                fontSize: 10,
                                color: isFocus ? Colors.white70 : AppTheme.textMuted(context),
                              )),
                          const SizedBox(height: 2),
                          Text('${d.day}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isFocus ? Colors.white : AppTheme.textPrimary(context),
                              )),
                          const SizedBox(height: 4),
                          Container(
                            width: 6, height: 6,
                            decoration: BoxDecoration(
                              color: dayCount > 0
                                  ? (isFocus ? Colors.white : AppTheme.brand)
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(child: _DayList(day: _focus, events: focusedEvents)),
        ],
      ),
    );
  }
}

/// Day view — single-day timeline as a vertically-scrolled list.
class _DayView extends StatelessWidget {
  final DateTime day;
  final List<CalendarEvent> events;
  final ValueChanged<int> onShift;
  const _DayView({required this.day, required this.events, required this.onShift});

  @override
  Widget build(BuildContext context) {
    final dayEvents = events.where((e) =>
        e.eventDate.year == day.year &&
        e.eventDate.month == day.month &&
        e.eventDate.day == day.day).toList()
      ..sort((a, b) => a.eventDate.compareTo(b.eventDate));

    const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -200) onShift(1);
        if (v > 200) onShift(-1);
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => onShift(-1),
                ),
                Expanded(
                  child: Center(
                    child: Text('${day.day} ${months[day.month - 1]} ${day.year}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => onShift(1),
                ),
              ],
            ),
          ),
          Expanded(child: _DayList(day: day, events: dayEvents)),
        ],
      ),
    );
  }
}

class _DayList extends StatelessWidget {
  final DateTime day;
  final List<CalendarEvent> events;
  const _DayList({required this.day, required this.events});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Center(
        child: Text('No events',
            style: TextStyle(fontSize: 13, color: AppTheme.textMuted(context))),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      itemCount: events.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final event = events[i];
        return EventCard(
          event: event,
          onComplete: () => context.read<DashboardProvider>().completeEvent(event.id),
          onTap: () => showEventActionsSheet(context, event),
        );
      },
    );
  }
}
