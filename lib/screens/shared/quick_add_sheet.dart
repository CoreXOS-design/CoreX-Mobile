import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/dashboard_data.dart';
import '../../providers/dashboard_provider.dart';
import '../../theme.dart';
import '../../utils/app_time.dart';

/// One sheet, two modes — replaces the separate create-task and create-event
/// sheets. Accepts [initialMode] so callers (Today FAB, Tasks FAB, Calendar
/// FAB) can pre-select the relevant segment.
class QuickAddSheet extends StatefulWidget {
  final String initialMode; // 'task' | 'event'
  final DateTime? initialDate; // pre-fills the event date (e.g. selected day)

  const QuickAddSheet({super.key, this.initialMode = 'task', this.initialDate});

  @override
  State<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<QuickAddSheet> {
  late String _mode;

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _priority = 'normal';
  bool _sendReminder = true;
  bool _submitting = false;

  // Task
  String _taskType = 'custom';
  DateTime? _dueDate;

  // Event
  String _eventType = 'manual';
  DateTime? _eventDate;
  TimeOfDay? _eventTime;
  TimeOfDay? _eventEndTime;
  bool _allDay = false;

  // Overlapping events for the chosen window, computed locally against the
  // events already loaded for the day — no server round-trip, no timezone
  // ambiguity. Empty until a valid start+end window is set.
  List<CalendarEvent> _conflicts = const [];

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode == 'event' ? 'event' : 'task';
    // Pre-fill the event date with the day the user was viewing (date-only).
    final d = widget.initialDate;
    if (d != null) _eventDate = DateTime(d.year, d.month, d.day);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Recompute overlapping events for the chosen window. A "conflict" means the
  /// chosen [start, end) overlaps another timed event on the same day — it has
  /// nothing to do with start-vs-end ordering. Only runs once the user has set
  /// a date, a start time AND an end time that is after the start.
  void _recomputeConflicts() {
    final valid = _mode == 'event' &&
        _eventDate != null &&
        !_allDay &&
        _eventTime != null &&
        _eventEndTime != null &&
        _toMinutes(_eventEndTime!) > _toMinutes(_eventTime!);
    if (!valid) {
      if (_conflicts.isNotEmpty) setState(() => _conflicts = const []);
      return;
    }
    final start = jhbWallClock(_eventDate!.year, _eventDate!.month,
        _eventDate!.day, _eventTime!.hour, _eventTime!.minute);
    final end = jhbWallClock(_eventDate!.year, _eventDate!.month,
        _eventDate!.day, _eventEndTime!.hour, _eventEndTime!.minute);

    final events = context.read<DashboardProvider>().events;
    final overlaps = <CalendarEvent>[];
    for (final e in events) {
      if (e.allDay) continue; // all-day events don't block a timed slot
      final eStart = jhb(e.eventDate);
      final eEnd = jhb(e.endDate ?? e.eventDate);
      // Half-open overlap: [start,end) intersects [eStart,eEnd].
      final intersects = start.isBefore(eEnd) && eStart.isBefore(end);
      // Zero-length (point) events: overlap only if strictly inside the window.
      final pointInside = eEnd == eStart &&
          !eStart.isBefore(start) &&
          eStart.isBefore(end);
      if (eEnd == eStart ? pointInside : intersects) overlaps.add(e);
    }
    setState(() => _conflicts = overlaps);
  }

  String _eventTimeLabel(CalendarEvent e) {
    String hm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final s = jhb(e.eventDate);
    if (e.endDate != null) return '${hm(s)}–${hm(jhb(e.endDate!))}';
    return hm(s);
  }

  /// Returns a human-readable list of what still needs to be filled in, or an
  /// empty list when the form is ready to submit.
  List<String> _missingFields() {
    final missing = <String>[];
    if (_titleController.text.trim().isEmpty) {
      missing.add(_mode == 'task' ? 'a task title' : 'an event title');
    }
    if (_mode == 'event') {
      if (_eventDate == null) missing.add('a date');
      if (!_allDay) {
        if (_eventTime == null) missing.add('a start time');
        if (_eventEndTime == null) missing.add('an end time');
      }
    }
    return missing;
  }

  void _warnMissing(List<String> missing) {
    String message;
    if (missing.length == 1) {
      message = 'Please add ${missing.first}.';
    } else {
      final last = missing.removeLast();
      message = 'Please add ${missing.join(', ')} and $last.';
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFB45309),
      ),
    );
  }

  Future<void> _submit() async {
    final missing = _missingFields();
    if (missing.isNotEmpty) {
      _warnMissing(missing);
      return;
    }
    // End must be after start when a window is set.
    if (_mode == 'event' &&
        !_allDay &&
        _eventTime != null &&
        _eventEndTime != null &&
        _toMinutes(_eventEndTime!) <= _toMinutes(_eventTime!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End time must be after start time.'),
          backgroundColor: Color(0xFFB45309),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    final dash = context.read<DashboardProvider>();
    bool ok;

    if (_mode == 'task') {
      ok = await dash.createTask(
        title: _titleController.text.trim(),
        taskType: _taskType,
        priority: _priority,
        dueDate: _dueDate?.toIso8601String().split('T').first,
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        sendReminder: _sendReminder,
      );
    } else {
      final time = _eventTime ?? const TimeOfDay(hour: 9, minute: 0);
      // Interpret the picked wall-clock time as Africa/Johannesburg, then send
      // the equivalent UTC instant so the stored time matches what the user
      // picked regardless of the device's timezone.
      final dt = jhbWallClock(
        _eventDate!.year, _eventDate!.month, _eventDate!.day,
        time.hour, time.minute,
      );
      String? endIso;
      if (!_allDay && _eventEndTime != null) {
        final end = jhbWallClock(
          _eventDate!.year, _eventDate!.month, _eventDate!.day,
          _eventEndTime!.hour, _eventEndTime!.minute,
        );
        endIso = end.isAfter(dt) ? end.toUtc().toIso8601String() : null;
      }
      ok = await dash.createEvent(
        title: _titleController.text.trim(),
        eventDate: dt.toUtc().toIso8601String(),
        endDate: endIso,
        eventType: _eventType,
        priority: _priority,
        allDay: _allDay,
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        sendReminder: _sendReminder,
      );
    }

    if (!mounted) return;
    if (ok) {
      // Pop with `true` so the calendar (or any caller) can refresh its list.
      Navigator.pop(context, true);
    } else {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create $_mode'),
          backgroundColor: const Color(0xFFef4444),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).viewPadding.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: AppTheme.textMuted(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
              child: Row(
                children: [
                  Text('Quick Add',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary(context))),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close,
                        size: 20, color: AppTheme.textSecondary(context)),
                  ),
                ],
              ),
            ),

            // Segmented Task | Event
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface2(context),
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(
                  children: [
                    _segment('task', 'Task'),
                    _segment('event', 'Event'),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _titleController,
                    autofocus: true,
                    style: TextStyle(
                        fontSize: 14, color: AppTheme.textPrimary(context)),
                    decoration: _inputDecoration(
                        _mode == 'task' ? 'Task title' : 'Event title'),
                  ),
                  const SizedBox(height: 16),

                  if (_mode == 'event') _buildEventDateTime(),
                  if (_mode == 'event') _buildConflictBanner(),
                  if (_mode == 'event') const SizedBox(height: 16),

                  Text('Priority',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary(context))),
                  const SizedBox(height: 8),
                  _PriorityPills(
                      selected: _priority,
                      onChanged: (v) => setState(() => _priority = v)),
                  const SizedBox(height: 16),

                  if (_mode == 'task') ...[
                    Text('Type',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textSecondary(context))),
                    const SizedBox(height: 8),
                    _dropdown<String>(
                      value: _taskType,
                      items: const {
                        'custom': 'Custom',
                        'follow_up': 'Follow Up',
                        'document_upload': 'Document Upload',
                        'compliance': 'Compliance',
                        'review': 'Review',
                        'deal_action': 'Deal Action',
                      },
                      onChanged: (v) =>
                          setState(() => _taskType = v ?? 'custom'),
                    ),
                    const SizedBox(height: 16),
                    Text('Due Date',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textSecondary(context))),
                    const SizedBox(height: 8),
                    _datePicker(
                      value: _dueDate,
                      onPicked: (d) => setState(() => _dueDate = d),
                      allowPast: false,
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (_mode == 'event') ...[
                    Text('Type',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textSecondary(context))),
                    const SizedBox(height: 8),
                    _dropdown<String>(
                      value: _eventType,
                      items: const {
                        'manual': 'Manual',
                        'deal': 'Deal',
                        'lease': 'Lease',
                        'compliance': 'Compliance',
                        'prospecting': 'Prospecting',
                      },
                      onChanged: (v) =>
                          setState(() => _eventType = v ?? 'manual'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                            child: Text('All day',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.textSecondary(context)))),
                        Switch.adaptive(
                          value: _allDay,
                          onChanged: (v) {
                            setState(() => _allDay = v);
                            _recomputeConflicts();
                          },
                          activeTrackColor: AppTheme.brand,
                        ),
                      ],
                    ),
                  ],

                  TextField(
                    controller: _descriptionController,
                    maxLines: 2,
                    style: TextStyle(
                        fontSize: 14, color: AppTheme.textPrimary(context)),
                    decoration: _inputDecoration('Description (optional)'),
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                          child: Text('Remind me',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: AppTheme.textSecondary(context)))),
                      Switch.adaptive(
                        value: _sendReminder,
                        onChanged: (v) => setState(() => _sendReminder = v),
                        activeTrackColor: AppTheme.brand,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(_mode == 'task' ? 'Add Task' : 'Add Event'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment(String value, String label) {
    final isActive = _mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppTheme.brand : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radius - 1),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.white : AppTheme.textSecondary(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Amber banner listing the timed events the chosen window overlaps.
  /// Non-blocking — the user can still submit. Shows each conflict's title and
  /// time so it's clear *what* it overlaps (not a vague "+N more").
  Widget _buildConflictBanner() {
    if (_conflicts.isEmpty) return const SizedBox.shrink();
    final shown = _conflicts.take(3).toList();
    final extra = _conflicts.length - shown.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: const Color(0xFFF59E0B)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFB45309), size: 18),
                const SizedBox(width: 8),
                Text(
                  _conflicts.length == 1
                      ? 'Overlaps 1 event'
                      : 'Overlaps ${_conflicts.length} events',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF92400E),
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...shown.map((e) => Padding(
                  padding: const EdgeInsets.only(left: 26, top: 2),
                  child: Text(
                    '${e.title} · ${_eventTimeLabel(e)}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                  ),
                )),
            if (extra > 0)
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 2),
                child: Text('+ $extra more',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF92400E))),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventDateTime() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Date',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary(context))),
        const SizedBox(height: 8),
        _datePicker(
          value: _eventDate,
          onPicked: (d) {
            setState(() => _eventDate = d);
            _recomputeConflicts();
          },
          allowPast: true,
        ),
        if (!_allDay) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Start time',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textSecondary(context))),
                    const SizedBox(height: 8),
                    _timeField(
                      value: _eventTime,
                      onPicked: (t) {
                        // No auto-fill — the user sets start and end themselves.
                        // The conflict check only runs once both are in.
                        setState(() => _eventTime = t);
                        _recomputeConflicts();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('End time',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textSecondary(context))),
                    const SizedBox(height: 8),
                    _timeField(
                      value: _eventEndTime,
                      onPicked: (t) {
                        setState(() => _eventEndTime = t);
                        _recomputeConflicts();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_eventTime != null &&
              _eventEndTime != null &&
              _toMinutes(_eventEndTime!) <= _toMinutes(_eventTime!))
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'End time must be after start time',
                style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
              ),
            ),
        ],
      ],
    );
  }

  int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  Widget _timeField({
    required TimeOfDay? value,
    required ValueChanged<TimeOfDay> onPicked,
  }) {
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: value ?? TimeOfDay.now(),
        );
        if (picked != null) onPicked(picked);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surface2(context),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
        child: Text(
          value != null
              ? '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}'
              : 'Select',
          style: TextStyle(
            fontSize: 14,
            color: value != null
                ? AppTheme.textPrimary(context)
                : AppTheme.textMuted(context),
          ),
        ),
      ),
    );
  }

  Widget _datePicker({
    required DateTime? value,
    required ValueChanged<DateTime> onPicked,
    required bool allowPast,
  }) {
    return GestureDetector(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? (allowPast ? now : now.add(const Duration(days: 1))),
          firstDate: allowPast ? now.subtract(const Duration(days: 30)) : now,
          lastDate: now.add(const Duration(days: 365)),
        );
        if (picked != null) onPicked(picked);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surface2(context),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
        child: Text(
          value != null ? '${value.day}/${value.month}/${value.year}' : 'Select date',
          style: TextStyle(
            fontSize: 14,
            color: value != null
                ? AppTheme.textPrimary(context)
                : AppTheme.textMuted(context),
          ),
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required Map<T, String> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface2(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        dropdownColor: AppTheme.surface2(context),
        style: TextStyle(fontSize: 14, color: AppTheme.textPrimary(context)),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16),
        ),
        items: items.entries
            .map((e) => DropdownMenuItem<T>(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: AppTheme.surface2(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

class _PriorityPills extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const _PriorityPills({required this.selected, required this.onChanged});

  static const _options = [
    {'value': 'low', 'label': 'Low', 'color': 0xFF6b7280},
    {'value': 'normal', 'label': 'Normal', 'color': 0xFF0ea5e9},
    {'value': 'high', 'label': 'High', 'color': 0xFFf59e0b},
    {'value': 'critical', 'label': 'Critical', 'color': 0xFFef4444},
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _options.map((opt) {
        final value = opt['value'] as String;
        final isActive = selected == value;
        final color = Color(opt['color'] as int);
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(value),
            child: Container(
              margin: EdgeInsets.only(right: opt != _options.last ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isActive ? color.withValues(alpha: 0.15) : AppTheme.surface2(context),
                borderRadius: BorderRadius.circular(AppTheme.radius),
                border: isActive ? Border.all(color: color.withValues(alpha: 0.4)) : null,
              ),
              child: Center(
                child: Text(
                  opt['label'] as String,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isActive ? color : AppTheme.textSecondary(context),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
