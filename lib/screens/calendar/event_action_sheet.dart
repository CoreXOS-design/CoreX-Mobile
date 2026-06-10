import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/dashboard_data.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/api_service.dart';
import '../../theme.dart';
import '../../utils/app_time.dart';

/// Bottom sheet shown when tapping a calendar event. Surfaces the four spec
/// quick-actions (Complete / Dismiss / Edit / Delete) plus the Resolve
/// bottom-sheet entry for overdue events.
Future<void> showEventActionsSheet(BuildContext context, CalendarEvent event) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _EventDetailSheet(event: event),
  );
}

class _EventDetailSheet extends StatelessWidget {
  final CalendarEvent event;
  const _EventDetailSheet({required this.event});

  Color get _accent {
    var s = event.colour.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 6) s = 'FF$s';
    final n = int.tryParse(s, radix: 16);
    return n == null ? const Color(0xFF6B7280) : Color(n);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textMuted(context).withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(color: _accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(event.title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 12),
              _kv(context, Icons.schedule, _fullTimeLabel(event)),
              if (event.allDay)
                _kv(context, Icons.brightness_5_outlined, 'All day'),
              if (event.location != null && event.location!.isNotEmpty)
                _kv(context, Icons.place_outlined, event.location!),
              if (event.propertyAddress != null &&
                  event.propertyAddress!.isNotEmpty)
                _kv(context, Icons.home_outlined, event.propertyAddress!),
              if (event.eventClassName != null &&
                  event.eventClassName!.isNotEmpty)
                _kv(context, Icons.label_outline, event.eventClassName!),
              if (event.createdByName != null &&
                  event.createdByName!.isNotEmpty)
                _kv(context, Icons.person_outline,
                    'Created by ${event.createdByName}'),
              if (event.attendees.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Attendees (${event.attendees.length})',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary(context),
                        letterSpacing: 0.4)),
                const SizedBox(height: 6),
                ...event.attendees.map((a) => _attendeeRow(context, a)),
              ],
              if (event.description != null &&
                  event.description!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Description',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary(context),
                        letterSpacing: 0.4)),
                const SizedBox(height: 4),
                Text(event.description!,
                    style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textPrimary(context))),
              ],
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await context
                          .read<DashboardProvider>()
                          .completeEvent(event.id);
                    },
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Complete'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      try {
                        await ApiService().dismissEvent(event.id);
                        if (!context.mounted) return;
                        await context
                            .read<DashboardProvider>()
                            .loadToday();
                      } catch (_) {}
                    },
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Dismiss'),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      showEventEditSheet(context, event);
                    },
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final dash = context.read<DashboardProvider>();
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          title: const Text('Delete event?'),
                          content: const Text(
                              'This will cancel any pending invitations and notify attendees.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.of(dCtx).pop(false),
                                child: const Text('Cancel')),
                            TextButton(
                                onPressed: () => Navigator.of(dCtx).pop(true),
                                style: TextButton.styleFrom(
                                    foregroundColor: Colors.red),
                                child: const Text('Delete')),
                          ],
                        ),
                      );
                      if (confirm != true) return;
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                      try {
                        await ApiService().deleteEvent(event.id);
                        await dash.loadToday();
                        final now = DateTime.now();
                        await dash.loadEventsRange(
                          start: now.subtract(const Duration(days: 30)),
                          end: now.add(const Duration(days: 60)),
                        );
                      } catch (e) {
                        messenger.showSnackBar(
                            SnackBar(content: Text('Delete failed: $e')));
                      }
                    },
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Delete'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: AppTheme.textMuted(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textPrimary(context))),
        ),
      ]),
    );
  }

  Widget _attendeeRow(BuildContext context, EventAttendee a) {
    Color c;
    IconData ico;
    switch (a.response) {
      case 'accepted':
        c = const Color(0xFF10B981);
        ico = Icons.check_circle;
        break;
      case 'declined':
        c = const Color(0xFFEF4444);
        ico = Icons.cancel;
        break;
      case 'tentative':
        c = const Color(0xFFF59E0B);
        ico = Icons.help_outline;
        break;
      default:
        c = AppTheme.textMuted(context);
        ico = Icons.schedule;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(ico, size: 14, color: c),
        const SizedBox(width: 8),
        Expanded(
          child: Text(a.name.isEmpty ? '(unnamed)' : a.name,
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textPrimary(context))),
        ),
        Text(a.response,
            style: TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary(context),
                fontWeight: FontWeight.w500)),
      ]),
    );
  }

  String _fullTimeLabel(CalendarEvent e) {
    final s = jhb(e.eventDate);
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    if (e.endDate != null) return '${fmt(s)} – ${fmt(jhb(e.endDate!))}';
    return fmt(s);
  }
}

/// Edit-event modal. Includes a debounced (400 ms) live conflict check on
/// the start/end pickers — surfaces an amber "Conflicts with N" banner.
Future<void> showEventEditSheet(BuildContext context, CalendarEvent event) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _EventEditForm(event: event),
  );
}

class _EventEditForm extends StatefulWidget {
  final CalendarEvent event;
  const _EventEditForm({required this.event});

  @override
  State<_EventEditForm> createState() => _EventEditFormState();
}

class _EventEditFormState extends State<_EventEditForm> {
  late TextEditingController _title;
  late TextEditingController _description;
  late DateTime _start;
  late DateTime? _end;
  late String _priority;
  late bool _allDay;

  List<CalendarEvent> _conflicts = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.event.title);
    _description = TextEditingController(text: widget.event.description ?? '');
    // Event times are anchored to Africa/Johannesburg. Keep working state in
    // that zone (not the device zone) so pickers and labels match what the user
    // sees elsewhere regardless of device timezone. `_save` converts the SA
    // wall-clock value back to a UTC instant on the way out.
    _start = jhb(widget.event.eventDate);
    _end = widget.event.endDate == null ? null : jhb(widget.event.endDate!);
    _priority = widget.event.priority;
    _allDay = widget.event.allDay;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Recompute overlapping events locally against the events already loaded for
  /// the calendar — same approach as the Quick Add sheet, no server round-trip
  /// and no timezone ambiguity. Crucially excludes the event being edited so it
  /// never conflicts with its own (old) slot. Skipped for all-day events and
  /// invalid (end-not-after-start) windows.
  void _recomputeConflicts() {
    final end = _end ?? _start.add(const Duration(hours: 1));
    if (_allDay || !end.isAfter(_start)) {
      if (_conflicts.isNotEmpty) setState(() => _conflicts = const []);
      return;
    }
    final events = context.read<DashboardProvider>().events;
    final overlaps = <CalendarEvent>[];
    for (final e in events) {
      if (e.id == widget.event.id) continue; // never conflict with self
      if (e.allDay) continue; // all-day events don't block a timed slot
      final eStart = jhb(e.eventDate);
      final eEnd = jhb(e.endDate ?? e.eventDate);
      // Half-open overlap: [start,end) intersects [eStart,eEnd].
      final intersects = _start.isBefore(eEnd) && eStart.isBefore(end);
      // Zero-length (point) events: overlap only if strictly inside the window.
      final pointInside =
          eEnd == eStart && !eStart.isBefore(_start) && eStart.isBefore(end);
      if (eEnd == eStart ? pointInside : intersects) overlaps.add(e);
    }
    setState(() => _conflicts = overlaps);
  }

  Future<void> _pickStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (date == null) return;
    setState(() {
      _start = jhbWallClock(
          date.year, date.month, date.day, _start.hour, _start.minute);
    });
    _recomputeConflicts();
  }

  Future<void> _pickStartTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (time == null) return;
    setState(() {
      _start = jhbWallClock(
          _start.year, _start.month, _start.day, time.hour, time.minute);
    });
    _recomputeConflicts();
  }

  Future<void> _pickEndDate() async {
    final initial = _end ?? _start.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (date == null) return;
    setState(() {
      _end = jhbWallClock(
          date.year, date.month, date.day, initial.hour, initial.minute);
    });
    _recomputeConflicts();
  }

  Future<void> _pickEndTime() async {
    final initial = _end ?? _start.add(const Duration(hours: 1));
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    setState(() {
      _end = jhbWallClock(
          initial.year, initial.month, initial.day, time.hour, time.minute);
    });
    _recomputeConflicts();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ApiService().updateEvent(widget.event.id, {
        'title': _title.text.trim(),
        'event_date': _start.toUtc().toIso8601String(),
        if (_end != null) 'end_date': _end!.toUtc().toIso8601String(),
        'priority': _priority,
        if (_description.text.trim().isNotEmpty) 'description': _description.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      final dash = context.read<DashboardProvider>();
      await dash.loadToday();
      final m = DateTime.now();
      await dash.loadEvents(month: '${m.year}-${m.month.toString().padLeft(2, '0')}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: pad),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit event', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('All day'),
              value: _allDay,
              onChanged: (v) {
                setState(() => _allDay = v);
                _recomputeConflicts();
              },
            ),
            // Start & end dates stacked underneath each other.
            _fieldLabel('Start date'),
            const SizedBox(height: 8),
            _pickerBox(
              icon: Icons.calendar_today_outlined,
              text: _fmtDate(_start),
              onTap: _pickStartDate,
            ),
            const SizedBox(height: 12),
            _fieldLabel('End date'),
            const SizedBox(height: 8),
            _pickerBox(
              icon: Icons.calendar_today_outlined,
              text: _fmtDate(_end ?? _start.add(const Duration(hours: 1))),
              placeholder: _end == null,
              onTap: _pickEndDate,
            ),
            // Start & end times side by side.
            if (!_allDay) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('Start time'),
                        const SizedBox(height: 8),
                        _pickerBox(
                          icon: Icons.access_time,
                          text: _fmtTime(_start),
                          onTap: _pickStartTime,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('End time'),
                        const SizedBox(height: 8),
                        _pickerBox(
                          icon: Icons.access_time,
                          text: _fmtTime(
                              _end ?? _start.add(const Duration(hours: 1))),
                          placeholder: _end == null,
                          onTap: _pickEndTime,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _priority,
              decoration: const InputDecoration(labelText: 'Priority'),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Low')),
                DropdownMenuItem(value: 'normal', child: Text('Normal')),
                DropdownMenuItem(value: 'high', child: Text('High')),
                DropdownMenuItem(value: 'critical', child: Text('Critical')),
              ],
              onChanged: (v) => setState(() => _priority = v ?? 'normal'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            if (_conflicts.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Conflicts with ${_conflicts.first.title}'
                        '${_conflicts.length > 1 ? ' (+${_conflicts.length - 1} more)' : ''}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
          ),
        ),
      ),
    );
  }

  /// Section label above a field — matches the Quick Add sheet styling.
  Widget _fieldLabel(String text) => Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppTheme.textSecondary(context),
        ),
      );

  /// Tappable boxed field matching Quick Add's `_datePicker`/`_timeField`:
  /// full-width, `surface2` fill, bordered, rounded. `placeholder` dims the
  /// value text when the underlying value is still unset.
  Widget _pickerBox({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
    bool placeholder = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surface2(context),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.textMuted(context)),
            const SizedBox(width: 10),
            Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: placeholder
                    ? AppTheme.textMuted(context)
                    : AppTheme.textPrimary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
