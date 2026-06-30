import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/calendar_form.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/api_service.dart';
import '../../theme.dart';
import '../../utils/app_time.dart';

/// Full "Add / Edit Event" flow — at parity with the web add-event panel.
///
/// Pick an event class, search & attach properties, search & add attendees
/// (contacts + agents, each with a role), set priority/reminder, then save.
/// The backend owns all link/invitation filing — this sheet only collects
/// `property_ids` + `attendees` + fields and POSTs/PUTs them.

/// Open the create-event sheet. Returns `true` if an event was created.
Future<bool> showCreateEventSheet(
  BuildContext context, {
  DateTime? initialDate,
  int? dealId,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EventFormSheet(initialDate: initialDate, dealId: dealId),
  );
  return result == true;
}

/// Fetch an event's full detail and, if editable, open the edit sheet
/// pre-filled. Returns `true` if the event was updated. Honours the
/// server's `is_editable` flag (source-driven events aren't user-editable).
Future<bool> openEventForEdit(BuildContext context, int eventId) async {
  // Lightweight blocking loader while we fetch detail.
  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black45,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  EventFormData data;
  try {
    data = await ApiService().getCalendarEventDetail(eventId);
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context).pop(); // dismiss loader
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn\'t load event: $e')),
      );
    }
    return false;
  }

  if (!context.mounted) return false;
  Navigator.of(context).pop(); // dismiss loader

  if (!data.isEditable) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This event can\'t be edited.')),
    );
    return false;
  }

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EventFormSheet(existing: data),
  );
  return result == true;
}

class _EventFormSheet extends StatefulWidget {
  final DateTime? initialDate;
  final EventFormData? existing;
  final int? dealId;

  const _EventFormSheet({this.initialDate, this.existing, this.dealId});

  @override
  State<_EventFormSheet> createState() => _EventFormSheetState();
}

class _EventFormSheetState extends State<_EventFormSheet> {
  final _api = ApiService();

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  CalendarOptions? _options;
  bool _loadingOptions = true;
  String? _optionsError;

  EventClassOption? _class;
  late DateTime _start;
  DateTime? _end;
  bool _allDay = false;
  String _priority = 'normal';
  bool _sendReminder = true;

  final List<SelectedProperty> _properties = [];
  // Owner suggestions keyed by the property they came from, so removing a
  // property also drops its suggestions.
  final Map<int, List<PropertyOwner>> _ownersByProperty = {};
  bool _loadingOwners = false;

  final List<SelectedAttendee> _attendees = [];

  bool _saving = false;
  Map<String, String> _fieldErrors = {};

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _titleController.text = existing.title;
      _descriptionController.text = existing.description ?? '';
      _start = jhb(existing.eventDate);
      _end = existing.endDate == null ? null : jhb(existing.endDate!);
      _allDay = existing.allDay;
      _priority = existing.priority;
      _sendReminder = existing.sendReminder;
      _properties.addAll(existing.linkedProperties);
      _attendees.addAll(existing.attendees);
    } else {
      final base = widget.initialDate ?? DateTime.now();
      _start = jhbWallClock(base.year, base.month, base.day, 9, 0);
    }
    _loadOptions();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loadingOptions = true;
      _optionsError = null;
    });
    try {
      final opts = await _api.getCalendarOptions();
      if (!mounted) return;
      setState(() {
        _options = opts;
        _loadingOptions = false;
        // Match the existing event's class, else default to `meeting`, else
        // the first class on offer.
        final wanted = widget.existing?.category;
        _class = _resolveClass(opts, wanted);
        // Keep priority within the offered set.
        if (!opts.priorities.contains(_priority)) {
          _priority =
              opts.priorities.contains('normal') ? 'normal' : opts.priorities.first;
        }
        _enforceSinglePropertyCap();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingOptions = false;
        _optionsError = 'Couldn\'t load the form. $e';
      });
    }
  }

  EventClassOption? _resolveClass(CalendarOptions opts, String? wanted) {
    if (opts.classes.isEmpty) return null;
    if (wanted != null) {
      for (final c in opts.classes) {
        if (c.eventClass == wanted) return c;
      }
    }
    for (final c in opts.classes) {
      if (c.eventClass == 'meeting') return c;
    }
    return opts.classes.first;
  }

  bool get _allowMultipleProperties => _class?.allowMultipleProperties ?? true;

  /// When the class only allows a single property, keep just the first.
  void _enforceSinglePropertyCap() {
    if (!_allowMultipleProperties && _properties.length > 1) {
      final first = _properties.first;
      _properties
        ..clear()
        ..add(first);
    }
  }

  String _apiDate(DateTime d) => jhbApiString(d).replaceFirst('T', ' ');

  List<PropertyOwner> get _visibleOwnerSuggestions {
    final attendeeKeys = _attendees.map((a) => a.key).toSet();
    final seen = <String>{};
    final out = <PropertyOwner>[];
    for (final list in _ownersByProperty.values) {
      for (final o in list) {
        final key = '${o.type}:${o.id}';
        if (attendeeKeys.contains(key)) continue;
        if (seen.add(key)) out.add(o);
      }
    }
    return out;
  }

  // --- Pickers ---

  Future<void> _pickStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;
    setState(() {
      _start = jhbWallClock(
          date.year, date.month, date.day, _start.hour, _start.minute);
    });
  }

  Future<void> _pickStartTime() async {
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (time == null || !mounted) return;
    setState(() {
      _start = jhbWallClock(
          _start.year, _start.month, _start.day, time.hour, time.minute);
    });
  }

  Future<void> _pickEndDate() async {
    final initial = _end ?? _start.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;
    setState(() {
      _end = jhbWallClock(
          date.year, date.month, date.day, initial.hour, initial.minute);
    });
  }

  Future<void> _pickEndTime() async {
    final initial = _end ?? _start.add(const Duration(hours: 1));
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null || !mounted) return;
    setState(() {
      _end = jhbWallClock(
          initial.year, initial.month, initial.day, time.hour, time.minute);
    });
  }

  Future<void> _addProperty() async {
    final result = await showModalBottomSheet<PropertySearchResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SearchPickerSheet<PropertySearchResult>(
        title: 'Add property',
        hint: 'Search by address…',
        loader: (q) => _api.searchCalendarProperties(q),
        itemBuilder: (ctx, p) => _PropertyResultTile(property: p),
      ),
    );
    if (result == null || !mounted) return;
    if (_properties.any((p) => p.id == result.id)) return; // dedupe
    setState(() {
      if (!_allowMultipleProperties) {
        _properties.clear();
        _ownersByProperty.clear();
      }
      _properties.add(SelectedProperty.fromSearch(result));
    });
    await _loadOwners(result.id);
  }

  Future<void> _loadOwners(int propertyId) async {
    setState(() => _loadingOwners = true);
    try {
      final owners = await _api.getPropertyOwners(propertyId);
      if (!mounted) return;
      setState(() => _ownersByProperty[propertyId] = owners);
    } catch (_) {
      // Suggestions are a nicety; a failure here shouldn't disrupt the form.
    } finally {
      if (mounted) setState(() => _loadingOwners = false);
    }
  }

  void _removeProperty(SelectedProperty p) {
    setState(() {
      _properties.removeWhere((x) => x.id == p.id);
      _ownersByProperty.remove(p.id);
    });
  }

  Future<void> _addAttendee() async {
    final result = await showModalBottomSheet<AttendeeSearchResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SearchPickerSheet<AttendeeSearchResult>(
        title: 'Add attendee',
        hint: 'Search contacts & agents…',
        loader: (q) => _api.searchAttendees(q),
        itemBuilder: (ctx, a) => _AttendeeResultTile(attendee: a),
      ),
    );
    if (result == null || !mounted) return;
    _addSelectedAttendee(SelectedAttendee.fromSearch(result));
  }

  void _addSelectedAttendee(SelectedAttendee a) {
    if (_attendees.any((x) => x.key == a.key)) return; // dedupe
    setState(() => _attendees.add(a));
  }

  void _removeAttendee(SelectedAttendee a) {
    setState(() => _attendees.removeWhere((x) => x.key == a.key));
  }

  // --- Save ---

  String? _validate() {
    if (_titleController.text.trim().isEmpty) return 'Please add a title.';
    if (_class == null) return 'Please pick an event type.';
    if (!_allDay && _end != null && !_end!.isAfter(_start)) {
      return 'End time must be after the start time.';
    }
    return null;
  }

  Map<String, dynamic> _buildBody() {
    final desc = _descriptionController.text.trim();
    return {
      'title': _titleController.text.trim(),
      'category': _class!.eventClass,
      'event_date': _apiDate(_start),
      if (!_allDay && _end != null && _end!.isAfter(_start))
        'end_date': _apiDate(_end!),
      'all_day': _allDay,
      'priority': _priority,
      'send_reminder': _sendReminder,
      if (desc.isNotEmpty) 'description': desc,
      'property_ids': _properties.map((p) => p.id).toList(),
      'attendees': _attendees.map((a) => a.toBody()).toList(),
      if (widget.dealId != null) 'deal_id': widget.dealId,
      if (_isEdit && widget.existing!.dealId != null)
        'deal_id': widget.existing!.dealId,
    };
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error),
            backgroundColor: const Color(0xFFB45309)),
      );
      return;
    }
    setState(() {
      _saving = true;
      _fieldErrors = {};
    });
    final dash = context.read<DashboardProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final body = _buildBody();
      if (_isEdit) {
        await _api.updateCalendarEventFull(widget.existing!.id, body);
      } else {
        await _api.createCalendarEventFull(body);
      }
      if (!mounted) return;
      // Refresh the role-aware Today cards; the calendar screen re-pulls its
      // visible range when this sheet pops `true`.
      await dash.loadToday();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _fieldErrors = e.fieldErrors;
      });
      messenger.showSnackBar(
        SnackBar(
            content: Text(e.fieldErrors.isNotEmpty
                ? e.fieldErrors.values.first
                : e.message),
            backgroundColor: const Color(0xFFef4444)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(
            content: Text('Couldn\'t save event: $e'),
            backgroundColor: const Color(0xFFef4444)),
      );
    }
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _grabber(),
          _header(),
          Flexible(child: _bodyContent()),
        ],
      ),
    );
  }

  Widget _grabber() => Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          decoration: BoxDecoration(
            color: AppTheme.textMuted(context),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
        child: Row(
          children: [
            Text(_isEdit ? 'Edit Event' : 'New Event',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context))),
            const Spacer(),
            IconButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              icon: Icon(Icons.close,
                  size: 20, color: AppTheme.textSecondary(context)),
            ),
          ],
        ),
      );

  Widget _bodyContent() {
    if (_loadingOptions) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_optionsError != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_optionsError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary(context))),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadOptions, child: const Text('Retry')),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Event type'),
          const SizedBox(height: 8),
          _classPicker(),
          const SizedBox(height: 16),

          _titleField(),
          const SizedBox(height: 16),

          _dateTimeSection(),
          const SizedBox(height: 16),

          _sectionLabel('Priority'),
          const SizedBox(height: 8),
          _priorityPills(),
          const SizedBox(height: 16),

          _propertiesSection(),
          const SizedBox(height: 16),

          _attendeesSection(),
          const SizedBox(height: 16),

          _descriptionField(),
          const SizedBox(height: 8),

          _reminderRow(),
          const SizedBox(height: 20),

          _saveButton(),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppTheme.textSecondary(context)),
      );

  Widget _classPicker() {
    final classes = _options?.classes ?? const <EventClassOption>[];
    return _boxedDropdown<EventClassOption>(
      value: _class,
      items: [
        for (final c in classes)
          DropdownMenuItem(value: c, child: Text(c.label)),
      ],
      onChanged: (c) {
        if (c == null) return;
        setState(() {
          _class = c;
          _enforceSinglePropertyCap();
        });
      },
    );
  }

  Widget _titleField() {
    final err = _fieldErrors['title'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleController,
          style: TextStyle(fontSize: 14, color: AppTheme.textPrimary(context)),
          decoration: _inputDecoration('Event title', errorText: err),
        ),
      ],
    );
  }

  Widget _dateTimeSection() {
    final dateErr = _fieldErrors['event_date'];
    final endErr = _fieldErrors['end_date'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _sectionLabel('Starts')),
            Text('All day',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary(context))),
            Switch.adaptive(
              value: _allDay,
              onChanged: (v) => setState(() => _allDay = v),
              activeTrackColor: AppTheme.brand,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _pickerBox(
                icon: Icons.calendar_today_outlined,
                text: _fmtDate(_start),
                onTap: _pickStartDate,
              ),
            ),
            if (!_allDay) ...[
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _pickerBox(
                  icon: Icons.access_time,
                  text: _fmtTime(_start),
                  onTap: _pickStartTime,
                ),
              ),
            ],
          ],
        ),
        if (dateErr != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(dateErr,
                style: const TextStyle(fontSize: 12, color: Color(0xFFef4444))),
          ),
        const SizedBox(height: 12),
        _sectionLabel('Ends (optional)'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _pickerBox(
                icon: Icons.calendar_today_outlined,
                text: _fmtDate(_end ?? _start.add(const Duration(hours: 1))),
                placeholder: _end == null,
                onTap: _pickEndDate,
              ),
            ),
            if (!_allDay) ...[
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _pickerBox(
                  icon: Icons.access_time,
                  text: _fmtTime(_end ?? _start.add(const Duration(hours: 1))),
                  placeholder: _end == null,
                  onTap: _pickEndTime,
                ),
              ),
            ],
          ],
        ),
        if (_end != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() => _end = null),
              child: const Text('Clear end'),
            ),
          ),
        if (endErr != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(endErr,
                style: const TextStyle(fontSize: 12, color: Color(0xFFef4444))),
          ),
        if (!_allDay &&
            _end != null &&
            !_end!.isAfter(_start))
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('End time must be after start time',
                style: TextStyle(fontSize: 12, color: Color(0xFFB45309))),
          ),
      ],
    );
  }

  Widget _priorityPills() {
    final priorities = _options?.priorities ?? const ['low', 'normal', 'high', 'critical'];
    const colors = {
      'low': 0xFF6b7280,
      'normal': 0xFF0ea5e9,
      'high': 0xFFf59e0b,
      'critical': 0xFFef4444,
    };
    return Row(
      children: [
        for (final p in priorities)
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _priority = p),
              child: Container(
                margin: EdgeInsets.only(right: p == priorities.last ? 0 : 8),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _priority == p
                      ? Color(colors[p] ?? 0xFF0ea5e9).withValues(alpha: 0.15)
                      : AppTheme.surface2(context),
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  border: _priority == p
                      ? Border.all(
                          color: Color(colors[p] ?? 0xFF0ea5e9)
                              .withValues(alpha: 0.4))
                      : null,
                ),
                child: Center(
                  child: Text(
                    _titleCase(p),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _priority == p
                          ? Color(colors[p] ?? 0xFF0ea5e9)
                          : AppTheme.textSecondary(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _propertiesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _sectionLabel(_allowMultipleProperties
                  ? 'Properties'
                  : 'Property (one)'),
            ),
            TextButton.icon(
              onPressed: _addProperty,
              icon: const Icon(Icons.add, size: 16),
              label: Text(_allowMultipleProperties || _properties.isEmpty
                  ? 'Add'
                  : 'Change'),
            ),
          ],
        ),
        if (_properties.isEmpty)
          Text('No properties linked',
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textMuted(context)))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _properties)
                _chip(
                  label: p.address.isEmpty ? 'Property #${p.id}' : p.address,
                  icon: Icons.home_outlined,
                  onRemove: () => _removeProperty(p),
                ),
            ],
          ),
        if (_loadingOwners)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        if (_visibleOwnerSuggestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Suggested from properties',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textMuted(context))),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in _visibleOwnerSuggestions)
                ActionChip(
                  avatar: const Icon(Icons.person_add_alt, size: 16),
                  label: Text(
                    o.roleLabel != null && o.roleLabel!.isNotEmpty
                        ? '${o.name} · ${o.roleLabel}'
                        : o.name,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () =>
                      _addSelectedAttendee(SelectedAttendee.fromOwner(o)),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _attendeesSection() {
    final roles = _options?.attendeeRoles ?? const <AttendeeRoleOption>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _sectionLabel('Attendees')),
            TextButton.icon(
              onPressed: _addAttendee,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add'),
            ),
          ],
        ),
        if (_attendees.isEmpty)
          Text('No attendees added',
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textMuted(context)))
        else
          Column(
            children: [
              for (final a in _attendees)
                _attendeeRow(a, roles),
            ],
          ),
      ],
    );
  }

  Widget _attendeeRow(SelectedAttendee a, List<AttendeeRoleOption> roles) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppTheme.surface2(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        a.name.isEmpty ? '(unnamed)' : a.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textPrimary(context)),
                      ),
                    ),
                    if (a.isAgent) ...[
                      const SizedBox(width: 6),
                      _badge('Agent'),
                    ],
                  ],
                ),
                if (a.isAgent && a.invitationStatus != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Invitation: ${a.invitationStatus}',
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary(context)),
                    ),
                  ),
                if (!a.isAgent && roles.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _roleDropdown(a, roles),
                  ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _removeAttendee(a),
            icon: Icon(Icons.close,
                size: 18, color: AppTheme.textMuted(context)),
          ),
        ],
      ),
    );
  }

  Widget _roleDropdown(SelectedAttendee a, List<AttendeeRoleOption> roles) {
    final values = roles.map((r) => r.key).toList();
    final current = values.contains(a.role)
        ? a.role
        : (values.contains('attendee') ? 'attendee' : values.first);
    return SizedBox(
      height: 32,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isDense: true,
          value: current,
          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context)),
          dropdownColor: AppTheme.surface2(context),
          items: [
            for (final r in roles)
              DropdownMenuItem(value: r.key, child: Text(r.label)),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => a.role = v);
          },
        ),
      ),
    );
  }

  Widget _descriptionField() {
    return TextField(
      controller: _descriptionController,
      maxLines: 2,
      style: TextStyle(fontSize: 14, color: AppTheme.textPrimary(context)),
      decoration: _inputDecoration('Description (optional)',
          errorText: _fieldErrors['description']),
    );
  }

  Widget _reminderRow() {
    return Row(
      children: [
        Expanded(
          child: Text('Remind me',
              style: TextStyle(
                  fontSize: 14, color: AppTheme.textSecondary(context))),
        ),
        Switch.adaptive(
          value: _sendReminder,
          onChanged: (v) => setState(() => _sendReminder = v),
          activeTrackColor: AppTheme.brand,
        ),
      ],
    );
  }

  Widget _saveButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(_isEdit ? 'Save Changes' : 'Create Event'),
      ),
    );
  }

  // --- Small shared widgets ---

  Widget _badge(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.brand.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppTheme.brand)),
      );

  Widget _chip({
    required String label,
    required IconData icon,
    required VoidCallback onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: AppTheme.surface2(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textMuted(context)),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13, color: AppTheme.textPrimary(context))),
          ),
          InkWell(
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close,
                  size: 14, color: AppTheme.textMuted(context)),
            ),
          ),
        ],
      ),
    );
  }

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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surface2(context),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.textMuted(context)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: placeholder
                      ? AppTheme.textMuted(context)
                      : AppTheme.textPrimary(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boxedDropdown<T>({
    required T? value,
    required List<DropdownMenuItem<T>> items,
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
        isExpanded: true,
        dropdownColor: AppTheme.surface2(context),
        style: TextStyle(fontSize: 14, color: AppTheme.textPrimary(context)),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16),
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, {String? errorText}) {
    return InputDecoration(
      hintText: hint,
      errorText: errorText,
      filled: true,
      fillColor: AppTheme.surface2(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day} ${_monthAbbr(d.month)} ${d.year}';

  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _monthAbbr(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m - 1];

  String _titleCase(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

/// Generic debounced search sheet — mirrors the app's existing picker pattern
/// (300 ms debounce, min 2 chars). Pops the picked item to the caller.
class _SearchPickerSheet<T> extends StatefulWidget {
  final String title;
  final String hint;
  final Future<List<T>> Function(String q) loader;
  final Widget Function(BuildContext context, T item) itemBuilder;

  const _SearchPickerSheet({
    required this.title,
    required this.hint,
    required this.loader,
    required this.itemBuilder,
  });

  @override
  State<_SearchPickerSheet<T>> createState() => _SearchPickerSheetState<T>();
}

class _SearchPickerSheetState<T> extends State<_SearchPickerSheet<T>> {
  final _controller = TextEditingController();
  Timer? _debounce;
  int _reqSeq = 0;

  List<T> _items = const [];
  bool _loading = false;
  String? _error;
  bool _searched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    final text = q.trim();
    if (text.length < 2) {
      setState(() {
        _items = const [];
        _loading = false;
        _searched = false;
        _error = null;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _query(text));
  }

  Future<void> _query(String q) async {
    final reqId = ++_reqSeq;
    try {
      final items = await widget.loader(q);
      if (!mounted || reqId != _reqSeq) return;
      setState(() {
        _items = items;
        _loading = false;
        _searched = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted || reqId != _reqSeq) return;
      setState(() {
        _loading = false;
        _searched = true;
        _error = 'Search failed. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
            child: Row(
              children: [
                Text(widget.title,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary(context))),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close,
                      size: 20, color: AppTheme.textSecondary(context)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              style:
                  TextStyle(fontSize: 14, color: AppTheme.textPrimary(context)),
              decoration: InputDecoration(
                hintText: widget.hint,
                prefixIcon: Icon(Icons.search,
                    size: 20, color: AppTheme.textMuted(context)),
                filled: true,
                fillColor: AppTheme.surface2(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(child: _results()),
        ],
      ),
    );
  }

  Widget _results() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return _centeredHint(_error!);
    }
    if (!_searched) {
      return _centeredHint('Type at least 2 characters to search.');
    }
    if (_items.isEmpty) {
      return _centeredHint('No results.');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      itemCount: _items.length,
      separatorBuilder: (_, __) => Divider(
          height: 1, color: AppTheme.borderColor(context)),
      itemBuilder: (context, i) {
        final item = _items[i];
        return InkWell(
          onTap: () => Navigator.of(context).pop(item),
          child: widget.itemBuilder(context, item),
        );
      },
    );
  }

  Widget _centeredHint(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Center(
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textMuted(context))),
        ),
      );
}

class _PropertyResultTile extends StatelessWidget {
  final PropertySearchResult property;
  const _PropertyResultTile({required this.property});

  @override
  Widget build(BuildContext context) {
    final sub = <String>[
      if (property.priceDisplay != null && property.priceDisplay!.isNotEmpty)
        property.priceDisplay!,
      if (property.beds != null) '${property.beds} bed',
      if (property.baths != null) '${property.baths} bath',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 48,
              height: 48,
              child: property.thumbnail != null &&
                      property.thumbnail!.isNotEmpty
                  ? Image.network(
                      property.thumbnail!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _thumbFallback(context),
                    )
                  : _thumbFallback(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(property.address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary(context))),
                if (sub.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(sub,
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary(context))),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbFallback(BuildContext context) => Container(
        color: AppTheme.surface2(context),
        child: Icon(Icons.home_outlined,
            size: 22, color: AppTheme.textMuted(context)),
      );
}

class _AttendeeResultTile extends StatelessWidget {
  final AttendeeSearchResult attendee;
  const _AttendeeResultTile({required this.attendee});

  @override
  Widget build(BuildContext context) {
    final sub = <String>[
      if (attendee.contactType != null && attendee.contactType!.isNotEmpty)
        attendee.contactType!,
      if (attendee.email != null && attendee.email!.isNotEmpty) attendee.email!,
      if (attendee.phone != null && attendee.phone!.isNotEmpty) attendee.phone!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.surface2(context),
            child: Icon(
              attendee.isAgent ? Icons.badge_outlined : Icons.person_outline,
              size: 18,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        attendee.name.isEmpty ? '(unnamed)' : attendee.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textPrimary(context)),
                      ),
                    ),
                    if (attendee.isAgent) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.brand.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('Agent',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.brand)),
                      ),
                    ],
                  ],
                ),
                if (sub.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary(context))),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
