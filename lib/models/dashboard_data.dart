/// Tolerant JSON coercion helpers. The backend occasionally sends ids as
/// strings, numbers as doubles, or a nested object as a scalar/null. These
/// never throw on type drift, so a single odd field can't take out the whole
/// dashboard/Today parse.
int _jInt(dynamic v, [int fallback = 0]) =>
    v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? fallback;
int? _jIntOrNull(dynamic v) =>
    v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
String _jStr(dynamic v, [String fallback = '']) => v?.toString() ?? fallback;
String? _jStrOrNull(dynamic v) => v?.toString();
Map<String, dynamic>? _jMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;

/// One attendee on a calendar event, with their RSVP response.
/// Server emits `attendees: [{ user_id, name, response }, ...]` under
/// `GET /command-center/calendar/{id}` and the range fetch.
class EventAttendee {
  final int? userId;
  final String name;
  /// `accepted` | `tentative` | `declined` | `pending`
  final String response;

  const EventAttendee({this.userId, this.name = '', this.response = 'pending'});

  factory EventAttendee.fromJson(Map<String, dynamic> json) {
    return EventAttendee(
      userId: (json['user_id'] as num?)?.toInt() ??
          (json['id'] as num?)?.toInt(),
      name: (json['name'] ?? json['user']?['name'] ?? '').toString(),
      response: (json['response'] ?? json['status'] ?? 'pending').toString(),
    );
  }
}

class CalendarEvent {
  final int id;
  final String title;
  final String eventType;
  final String? category;
  final DateTime eventDate;
  final DateTime? endDate;
  final bool allDay;
  final String priority;
  final String status;
  final String? resolution;
  final String? resolutionNote;
  final String colour;
  final int? propertyId;
  final int? contactId;
  final String? propertyAddress;
  final String? contactName;
  final String? pillarTag; // server-supplied: 'property' | 'deal' | 'contact' | null
  final bool sendReminder;
  final String? description;
  // Extended fields for the rich event detail sheet (Calendar screen). These
  // fields are permissively parsed from the same payload — if the server
  // doesn't include them they stay null/empty rather than failing the parse.
  final String? location;
  final int? eventClassId;
  final String? eventClassName;
  final String? createdByName;
  final List<EventAttendee> attendees;

  CalendarEvent({
    required this.id,
    required this.title,
    this.eventType = 'manual',
    this.category,
    required this.eventDate,
    this.endDate,
    this.allDay = false,
    this.priority = 'normal',
    this.status = 'pending',
    this.resolution,
    this.resolutionNote,
    this.colour = '#6b7280',
    this.propertyId,
    this.contactId,
    this.propertyAddress,
    this.contactName,
    this.pillarTag,
    this.sendReminder = true,
    this.description,
    this.location,
    this.eventClassId,
    this.eventClassName,
    this.createdByName,
    this.attendees = const [],
  });

  bool get isOverdue =>
      status == 'overdue' || (status == 'pending' && eventDate.isBefore(DateTime.now()));

  String get overdueDuration {
    final diff = DateTime.now().difference(eventDate);
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    return '${diff.inMinutes}m';
  }

  /// Derived pillar tag, falling back to server-computed value or the
  /// `event_type in ['deal','lease']` convention described in the cockpit spec.
  String? get effectivePillarTag {
    if (pillarTag != null && pillarTag!.isNotEmpty) return pillarTag;
    if (propertyId != null) return 'property';
    if (eventType == 'deal' || eventType == 'lease') return 'deal';
    if (contactId != null) return 'contact';
    return null;
  }

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    final ec = json['event_class'];
    final ecMap = ec is Map ? Map<String, dynamic>.from(ec) : null;
    final attendeesRaw = json['attendees'];
    final attendees = attendeesRaw is List
        ? attendeesRaw
            .whereType<Map>()
            .map((e) => EventAttendee.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const <EventAttendee>[];

    // Spec uses `starts_at`/`ends_at`; legacy server uses `event_date`/`end_date`.
    // Accept both so the range endpoint and legacy endpoint can share the model.
    final startsRaw = json['starts_at'] ?? json['event_date'] ?? '';
    final endsRaw = json['ends_at'] ?? json['end_date'];

    return CalendarEvent(
      id: _jInt(json['id']),
      title: _jStr(json['title']),
      eventType: _jStr(json['event_type'], 'manual'),
      category: _jStrOrNull(json['category']),
      eventDate: DateTime.tryParse(startsRaw.toString()) ?? DateTime.now(),
      endDate: endsRaw == null ? null : DateTime.tryParse(endsRaw.toString()),
      allDay: json['all_day'] == true || json['all_day'] == 1,
      priority: _jStr(json['priority'], 'normal'),
      status: _jStr(json['status'], 'pending'),
      resolution: _jStrOrNull(json['resolution']),
      resolutionNote: _jStrOrNull(json['resolution_note']),
      colour: (ecMap?['color'] ??
              json['colour'] ??
              json['color'] ??
              _typeColour(_jStrOrNull(json['event_type'])))
          .toString(),
      propertyId: _jIntOrNull(json['property_id']),
      contactId: _jIntOrNull(json['contact_id']),
      propertyAddress: _jStrOrNull(_jMap(json['property'])?['display_address']) ??
          _jStrOrNull(json['property_address']),
      contactName: _jStrOrNull(_jMap(json['contact'])?['name']) ??
          _jStrOrNull(json['contact_name']),
      pillarTag: _jStrOrNull(json['pillar_tag']),
      sendReminder: json['send_reminder'] == true || json['send_reminder'] == 1,
      description: _jStrOrNull(json['description']),
      location: _jStrOrNull(json['location']),
      eventClassId: _jIntOrNull(ecMap?['id']) ??
          _jIntOrNull(json['event_class_id']),
      eventClassName:
          _jStrOrNull(ecMap?['name']) ?? _jStrOrNull(json['event_class_name']),
      createdByName: _jStrOrNull(_jMap(json['created_by'])?['name']) ??
          _jStrOrNull(json['created_by_name']),
      attendees: attendees,
    );
  }

  static String _typeColour(String? type) {
    switch (type) {
      case 'deal': return '#3b82f6';
      case 'lease': return '#10b981';
      case 'compliance': return '#f59e0b';
      case 'document': return '#8b5cf6';
      case 'prospecting': return '#06b6d4';
      case 'property': return '#f97316';
      default: return '#6b7280';
    }
  }
}

class CommandTask {
  final int id;
  final String title;
  final String taskType;
  final String status;
  final String priority;
  final String? resolution;
  final String? resolutionNote;
  final int? assignedTo;
  final DateTime? dueDate;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? deletedAt;
  final int? propertyId;
  final int? contactId;
  final int? dealId;
  final String? propertyAddress;
  final String? contactName;
  final String? pillarTag;
  final String? description;
  final bool sendReminder;
  // Server-computed overdue flag (takes precedence over client-side calc when present).
  final bool? serverIsOverdue;

  CommandTask({
    required this.id,
    required this.title,
    this.taskType = 'custom',
    this.status = 'todo',
    this.priority = 'normal',
    this.resolution,
    this.resolutionNote,
    this.assignedTo,
    this.dueDate,
    this.startedAt,
    this.completedAt,
    this.deletedAt,
    this.propertyId,
    this.contactId,
    this.dealId,
    this.propertyAddress,
    this.contactName,
    this.pillarTag,
    this.description,
    this.sendReminder = true,
    this.serverIsOverdue,
  });

  bool get isOverdue =>
      serverIsOverdue ??
      (dueDate != null &&
          dueDate!.isBefore(DateTime.now()) &&
          status != 'done' &&
          status != 'dismissed');

  bool get isArchived => deletedAt != null;

  String get overdueDuration {
    if (dueDate == null) return '';
    final diff = DateTime.now().difference(dueDate!);
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    return '${diff.inMinutes}m';
  }

  String? get effectivePillarTag {
    if (pillarTag != null && pillarTag!.isNotEmpty) return pillarTag;
    if (propertyId != null) return 'property';
    if (dealId != null) return 'deal';
    if (contactId != null) return 'contact';
    return null;
  }

  factory CommandTask.fromJson(Map<String, dynamic> json) {
    return CommandTask(
      id: _jInt(json['id']),
      title: _jStr(json['title']),
      taskType: _jStr(json['task_type'], 'custom'),
      status: _jStr(json['status'], 'todo'),
      priority: _jStr(json['priority'], 'normal'),
      resolution: _jStrOrNull(json['resolution']),
      resolutionNote: _jStrOrNull(json['resolution_note']),
      assignedTo: _jIntOrNull(json['assigned_to']),
      dueDate: DateTime.tryParse(_jStr(json['due_date'])),
      startedAt: DateTime.tryParse(_jStr(json['started_at'])),
      completedAt: DateTime.tryParse(_jStr(json['completed_at'])),
      deletedAt: DateTime.tryParse(_jStr(json['deleted_at'])),
      propertyId: _jIntOrNull(json['property_id']),
      contactId: _jIntOrNull(json['contact_id']),
      dealId: _jIntOrNull(json['deal_id']),
      propertyAddress: _jStrOrNull(_jMap(json['property'])?['display_address']) ??
          _jStrOrNull(json['property_address']),
      contactName: _jStrOrNull(_jMap(json['contact'])?['name']) ??
          _jStrOrNull(json['contact_name']),
      pillarTag: _jStrOrNull(json['pillar_tag']),
      description: _jStrOrNull(json['description']),
      sendReminder: json['send_reminder'] == true || json['send_reminder'] == 1,
      serverIsOverdue: json['is_overdue'] is bool ? json['is_overdue'] as bool : null,
    );
  }
}

/// A calendar invitation from another user. Fed by
/// `GET /api/command-center/calendar/invitations`.
class CalendarInvitation {
  final int id;
  final int eventId;
  /// `pending` | `accepted` | `tentative` | `declined`
  final String status;
  final String? inviterName;
  final DateTime? createdAt;
  final DateTime? responseAt;
  final DateTime? acknowledgedAt;
  final CalendarEvent? event;
  final List<CalendarEvent> liveConflicts;

  CalendarInvitation({
    required this.id,
    required this.eventId,
    this.status = 'pending',
    this.inviterName,
    this.createdAt,
    this.responseAt,
    this.acknowledgedAt,
    this.event,
    this.liveConflicts = const [],
  });

  bool get hasConflicts => liveConflicts.isNotEmpty;

  factory CalendarInvitation.fromJson(Map<String, dynamic> json) {
    return CalendarInvitation(
      id: json['id'] ?? 0,
      eventId: json['event_id'] ?? json['event']?['id'] ?? 0,
      status: json['status']?.toString() ?? 'pending',
      inviterName: json['inviter_name'] ?? json['inviter']?['name'],
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
      responseAt: json['response_at'] != null ? DateTime.tryParse(json['response_at']) : null,
      acknowledgedAt:
          json['acknowledged_at'] != null ? DateTime.tryParse(json['acknowledged_at']) : null,
      event: json['event'] is Map
          ? CalendarEvent.fromJson(Map<String, dynamic>.from(json['event'] as Map))
          : null,
      liveConflicts: (json['live_conflicts'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => CalendarEvent.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// Response shape for `GET /api/command-center/tasks/archived` — tasks
/// pre-grouped by the day they were archived.
class ArchivedTasksData {
  final int total;
  final List<ArchivedGroup> groups;

  ArchivedTasksData({this.total = 0, this.groups = const []});

  factory ArchivedTasksData.fromJson(Map<String, dynamic> json) {
    return ArchivedTasksData(
      total: json['total'] ?? 0,
      groups: (json['groups'] as List? ?? [])
          .map((g) => ArchivedGroup.fromJson(g))
          .toList(),
    );
  }
}

class ArchivedGroup {
  final DateTime date;
  final List<CommandTask> tasks;

  ArchivedGroup({required this.date, this.tasks = const []});

  factory ArchivedGroup.fromJson(Map<String, dynamic> json) {
    return ArchivedGroup(
      date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
      tasks: (json['tasks'] as List? ?? [])
          .map((t) => CommandTask.fromJson(t))
          .toList(),
    );
  }
}
