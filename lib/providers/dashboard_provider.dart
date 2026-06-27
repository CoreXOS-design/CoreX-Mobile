import 'package:flutter/material.dart';
import '../models/dashboard_data.dart';
import '../models/today_card.dart';
import '../services/api_service.dart';

/// Cockpit state — Today cards, tasks, events, calendar invitations.
///
/// The legacy `/dashboard` KPI surface was removed; the provider name is
/// retained for now to avoid a wide rename across 14 consumer files. After
/// any cockpit mutation we re-fetch [loadToday] so the role-aware card list
/// stays in sync.
class DashboardProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  bool _disposed = false;

  // Stale-response guards (one sequence per logical load).
  int _todaySeq = 0;
  int _eventsSeq = 0;

  // Poller backoff + failure cap for loadToday (project convention).
  static const int _maxConsecutiveFailures = 3;
  static const Duration _backoffWindow = Duration(seconds: 30);
  int _todayFailures = 0;
  DateTime? _todayLastFailureAt;

  String? _error;
  TodayPayload _today = const TodayPayload();
  bool _todayLoading = false;
  List<CommandTask> _tasks = [];
  List<CalendarEvent> _events = [];
  List<CalendarInvitation> _invitations = [];

  String? get error => _error;
  TodayPayload get today => _today;
  bool get todayLoading => _todayLoading;
  List<TodayCard> get cards => _today.cards;
  List<CommandTask> get tasks => _tasks;
  List<CalendarEvent> get events => _events;
  List<CalendarInvitation> get invitations => _invitations;
  int get pendingInvitationCount =>
      _invitations.where((i) => i.status == 'pending').length;

  /// Clear all per-user cockpit state on logout so the next account never
  /// sees the previous user's cards/tasks/events/invitations.
  void reset() {
    _error = null;
    _today = const TodayPayload();
    _todayLoading = false;
    _tasks = [];
    _events = [];
    _invitations = [];
    // Invalidate any in-flight loads and clear poller backoff state.
    _todaySeq++;
    _eventsSeq++;
    _todayFailures = 0;
    _todayLastFailureAt = null;
    _safeNotify();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Load the role-aware Today payload (`GET /command-center/today`).
  /// Server-side cache TTL is 5 min; use [refreshToday] to bust it.
  Future<void> loadToday({bool manual = false}) async {
    // Poller backoff + failure cap: auto refetches back off after repeated
    // failures; a manual/explicit refresh always proceeds and resets the gate.
    if (!manual && _todayFailures >= _maxConsecutiveFailures) {
      final last = _todayLastFailureAt;
      if (last != null && DateTime.now().difference(last) < _backoffWindow) {
        return;
      }
    }
    if (manual) {
      _todayFailures = 0;
      _todayLastFailureAt = null;
    }
    final reqId = ++_todaySeq;
    _todayLoading = true;
    _safeNotify();
    try {
      final payload = await _api.getToday();
      if (reqId != _todaySeq) return;
      _today = payload;
      _error = null;
      _todayFailures = 0;
      _todayLastFailureAt = null;
    } catch (_) {
      if (reqId != _todaySeq) return;
      _error = 'Failed to load today';
      _todayFailures++;
      _todayLastFailureAt = DateTime.now();
    } finally {
      if (reqId == _todaySeq) {
        _todayLoading = false;
        _safeNotify();
      }
    }
  }

  /// `POST /command-center/today/refresh` — pull-to-refresh handler.
  Future<void> refreshToday() async {
    // Manual pull-to-refresh — clear the poller gate so a backed-off auto
    // load doesn't keep us stale after the user explicitly asked.
    _todayFailures = 0;
    _todayLastFailureAt = null;
    final reqId = ++_todaySeq;
    try {
      final payload = await _api.refreshToday();
      if (reqId != _todaySeq) return;
      _today = payload;
      _error = null;
    } catch (_) {
      if (reqId != _todaySeq) return;
      _error = 'Failed to refresh today';
    }
    if (reqId == _todaySeq) _safeNotify();
  }

  Future<void> loadTasks() async {
    try {
      _tasks = await _api.getTasks();
      _safeNotify();
    } catch (_) {
      _error = 'Failed to load tasks';
      _safeNotify();
    }
  }

  Future<void> loadEvents({String? month}) async {
    final reqId = ++_eventsSeq;
    try {
      final events = await _api.getCalendarEvents(month: month);
      if (reqId != _eventsSeq) return;
      _events = events;
      _safeNotify();
    } catch (_) {
      if (reqId != _eventsSeq) return;
      _error = 'Failed to load events';
      _safeNotify();
    }
  }

  /// Range fetch for the Calendar screen — paged tightly around the visible
  /// window (+1 day padding on either side, handled by the screen).
  Future<void> loadEventsRange(
      {required DateTime start, required DateTime end}) async {
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final reqId = ++_eventsSeq;
    try {
      final events =
          await _api.getCalendarRange(start: fmt(start), end: fmt(end));
      if (reqId != _eventsSeq) return;
      _events = events;
      _safeNotify();
    } catch (_) {
      if (reqId != _eventsSeq) return;
      _error = 'Failed to load events';
      _safeNotify();
    }
  }

  /// After every mutation we refresh the Today cards + Tasks list. Callers
  /// that also need a specific month should call [loadEvents] themselves.
  Future<void> _refreshAfterMutation() async {
    await Future.wait([loadToday(), loadTasks()]);
  }

  Future<bool> createTask({
    required String title,
    String taskType = 'custom',
    String priority = 'normal',
    String? dueDate,
    String? description,
    bool sendReminder = true,
    int? propertyId,
    int? contactId,
  }) async {
    _error = null;
    try {
      await _api.createTask(
        title: title,
        taskType: taskType,
        priority: priority,
        dueDate: dueDate,
        description: description,
        sendReminder: sendReminder,
        propertyId: propertyId,
        contactId: contactId,
      );
      await _refreshAfterMutation();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> createEvent({
    required String title,
    required String eventDate,
    String? endDate,
    String eventType = 'manual',
    String priority = 'normal',
    bool allDay = false,
    String? description,
    bool sendReminder = true,
    int? propertyId,
    int? contactId,
    String? category,
  }) async {
    _error = null;
    try {
      await _api.createEvent(
        title: title,
        eventDate: eventDate,
        endDate: endDate,
        eventType: eventType,
        priority: priority,
        allDay: allDay,
        description: description,
        sendReminder: sendReminder,
        propertyId: propertyId,
        contactId: contactId,
        category: category,
      );
      await loadToday();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> completeTask(int taskId) async {
    _error = null;
    try {
      await _api.completeTask(taskId);
      await _refreshAfterMutation();
    } catch (_) {}
  }

  Future<void> completeEvent(int eventId) async {
    _error = null;
    try {
      await _api.completeEvent(eventId);
      await loadToday();
    } catch (_) {}
  }

  Future<void> resolveTask(int taskId, {required String resolution, int? extendDays}) async {
    _error = null;
    try {
      await _api.resolveTask(taskId, resolution: resolution, extendDays: extendDays);
      await _refreshAfterMutation();
    } catch (_) {}
  }

  Future<void> resolveEvent(int eventId, {required String resolution, int? extendDays}) async {
    _error = null;
    try {
      await _api.resolveEvent(eventId, resolution: resolution, extendDays: extendDays);
      await loadToday();
    } catch (_) {}
  }

  /// Optimistic status change — mutates the local `_tasks` row immediately so
  /// the kanban column re-renders without waiting for the network round-trip.
  /// Rolls back on failure. Spec: `PATCH /command-center/tasks/{id}/status`.
  Future<bool> updateTaskStatus(int taskId, String status) async {
    _error = null;
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    CommandTask? original;
    if (idx >= 0) {
      original = _tasks[idx];
      _tasks[idx] = CommandTask(
        id: original.id,
        title: original.title,
        taskType: original.taskType,
        status: status,
        priority: original.priority,
        resolution: original.resolution,
        resolutionNote: original.resolutionNote,
        assignedTo: original.assignedTo,
        dueDate: original.dueDate,
        startedAt: original.startedAt,
        completedAt: original.completedAt,
        deletedAt: original.deletedAt,
        propertyId: original.propertyId,
        contactId: original.contactId,
        dealId: original.dealId,
        propertyAddress: original.propertyAddress,
        contactName: original.contactName,
        pillarTag: original.pillarTag,
        description: original.description,
        sendReminder: original.sendReminder,
        serverIsOverdue: original.serverIsOverdue,
      );
      _safeNotify();
    }
    try {
      await _api.updateTaskStatus(taskId, status);
      // Refresh in the background so server-side flags (completed_at, etc.)
      // catch up — but the UI already reflects the new column.
      _refreshAfterMutation();
      return true;
    } catch (_) {
      if (idx >= 0 && original != null) {
        _tasks[idx] = original;
        _safeNotify();
      }
      return false;
    }
  }

  /// Wraps resolve-task with extend_days. Used by inline reschedule actions.
  Future<void> rescheduleTask(int taskId, int days) async {
    _error = null;
    try {
      await _api.rescheduleTask(taskId, days);
      await _refreshAfterMutation();
    } catch (_) {}
  }

  Future<void> rescheduleEvent(int eventId, int days) async {
    _error = null;
    try {
      await _api.rescheduleEvent(eventId, days);
      await loadToday();
    } catch (_) {}
  }

  /// Per-card archive (Done column and elsewhere). If the server's
  /// `auto_archive_done_days = 0` observer already archived the row on
  /// `completeTask`, calling this again is a safe no-op from the user's
  /// perspective (a 404 is swallowed by the try/catch).
  Future<void> archiveTask(int taskId) async {
    _error = null;
    try {
      await _api.archiveTask(taskId);
      await loadTasks();
    } catch (_) {}
  }

  Future<void> loadInvitations() async {
    try {
      _invitations = await _api.getCalendarInvitations();
      _safeNotify();
    } catch (_) {
      // leave previous list; do not surface a hard error for this side panel
    }
  }

  Future<bool> respondToInvitation(int invitationId, String action, {String? notes}) async {
    _error = null;
    try {
      final updated = await _api.respondToInvitation(invitationId, action, notes: notes);
      final idx = _invitations.indexWhere((i) => i.id == invitationId);
      if (idx >= 0) {
        _invitations[idx] = updated;
      }
      _safeNotify();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> acknowledgeInvitation(int invitationId) async {
    _error = null;
    try {
      await _api.acknowledgeInvitation(invitationId);
      await loadInvitations();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int> archiveAllDone() async {
    _error = null;
    try {
      final archived = await _api.archiveAllDone();
      await loadTasks();
      return archived;
    } catch (_) {
      return 0;
    }
  }
}
