import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/env.dart';
import '../models/calendar_form.dart';
import '../models/contact.dart';
import '../models/contact_compliance.dart';
import '../models/core_match.dart';
import '../models/dashboard_data.dart';
import '../models/gallery_tags.dart';
import '../models/notification_models.dart';
import '../models/portal_lead.dart';
import '../models/p24_location.dart';
import '../models/property.dart';
import '../models/property_compliance.dart';
import '../models/property_options.dart';
import '../models/property_overview.dart';
import '../models/rental_inspections.dart';
import '../models/branding.dart';
import '../models/space.dart';
import '../models/task_extras.dart';
import '../models/today_card.dart';
import '../models/visibility.dart';

class ApiService {
  static String get baseUrl => Env.apiBaseUrl;
  static bool get useMockData => Env.useMockData;
  static const Duration _timeout = Duration(seconds: 15);

  static const String _tokenKey = 'auth_token';
  static const String _spacesCatalogKey = 'spaces_catalog_v1';
  static const String _spacesCatalogTsKey = 'spaces_catalog_v1_ts';
  static const Duration _spacesCatalogTtl = Duration(hours: 24);

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  /// In-memory copy of the auth token for the lifetime of the app process.
  /// This is the source of truth during a session: secure storage on some
  /// devices/emulators silently fails to round-trip a value (keystore quirks),
  /// which would otherwise leave a freshly-logged-in user with no token on the
  /// very next request → a 401 storm → an immediate bounce back to login.
  /// Persistence to secure storage is best-effort, for cold-start restore.
  static String? _inMemoryToken;

  /// Reads the auth token. Prefers the in-memory copy, then secure storage,
  /// then the legacy plaintext SharedPreferences key (migrated forward once).
  /// All storage access is fault-tolerant so a failing keystore can't throw
  /// the request path off the rails.
  Future<String?> getToken() async {
    if (_inMemoryToken != null) return _inMemoryToken;

    try {
      final secure = await _secureStorage.read(key: _tokenKey);
      if (secure != null) {
        _inMemoryToken = secure;
        return secure;
      }
    } catch (e) {
      debugPrint('[auth] secure storage read failed: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(_tokenKey);
    if (legacy != null) {
      _inMemoryToken = legacy;
      try {
        await _secureStorage.write(key: _tokenKey, value: legacy);
        await prefs.remove(_tokenKey);
      } catch (e) {
        debugPrint('[auth] legacy token migration failed: $e');
      }
      return legacy;
    }
    return null;
  }

  Future<void> saveToken(String token) async {
    _inMemoryToken = token;
    // Fresh session — clear any stale 401 streak from a previous session.
    _consecutive401s = 0;
    _last401At = null;
    try {
      await _secureStorage.write(key: _tokenKey, value: token);
    } catch (e) {
      debugPrint('[auth] secure storage write failed: $e');
    }
  }

  Future<void> clearToken() async {
    _inMemoryToken = null;
    try {
      await _secureStorage.delete(key: _tokenKey);
    } catch (e) {
      debugPrint('[auth] secure storage delete failed: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  /// Bumped whenever an authenticated request returns 401. The auth layer
  /// ([AuthProvider]) listens and drops the session live, so a token that goes
  /// invalid mid-session routes the user back to login instead of stranding
  /// them on a screen whose data silently fails to load. An int counter (not a
  /// bool) means repeated 401s each notify, while listeners stay free to
  /// debounce by ignoring the signal when already logged out.
  static final ValueNotifier<int> sessionExpired = ValueNotifier<int>(0);

  /// Tracks consecutive 401s so a single spurious 401 (a token-refresh race,
  /// a gateway blip) doesn't bounce a still-valid session back to login. Only
  /// a second 401 inside [_unauthorizedWindow] is treated as a real expiry.
  static int _consecutive401s = 0;
  static DateTime? _last401At;
  static const Duration _unauthorizedWindow = Duration(seconds: 12);

  /// On a 401, drop the (now invalid) token and signal the auth layer to route
  /// the user back to login. Safe to call on unauthenticated endpoints (e.g. a
  /// failed login) — listeners guard on being logged in, so a login 401 is a
  /// no-op for them.
  ///
  /// Debounced: the first 401 is treated as possibly-transient and the token is
  /// left intact; a second 401 within [_unauthorizedWindow] confirms the
  /// session is genuinely gone, at which point we clear the token and signal.
  Future<void> _handleUnauthorized(int status) async {
    if (status != 401) return;
    final now = DateTime.now();
    if (_last401At == null ||
        now.difference(_last401At!) > _unauthorizedWindow) {
      _consecutive401s = 0;
    }
    _consecutive401s++;
    _last401At = now;
    if (_consecutive401s < 2) return;
    _consecutive401s = 0;
    _last401At = null;
    await clearToken();
    sessionExpired.value++;
  }

  Future<Map<String, String>> _headers() async {
    final token = await getToken();
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // --- Login ---

  Future<Map<String, dynamic>> login(String email, String password) async {
    if (useMockData) {
      await Future.delayed(const Duration(milliseconds: 800));
      return {
        'token': 'mock-token-abc123',
        'user': {
          'id': 1,
          'name': 'John Moosa',
          'email': email,
          'branch': 'Amanzimtoti',
          'ffc_status': 'Active',
        },
      };
    }

    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) return body;
      throw ApiException(response.statusCode, 'Login failed');
    }
    await _handleUnauthorized(response.statusCode);
    String message = 'Login failed';
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['message'] is String) message = body['message'];
    } catch (_) {}
    throw ApiException(response.statusCode, message);
  }

  // --- Demo Mode ---

  /// `GET /v1/demo/status` — unauthenticated. Returns `{enabled, roles}`.
  /// Throws on non-200 / network error; caller falls back to the normal form.
  Future<({bool enabled, List<String> roles})> getDemoStatus() async {
    final response = await http.get(
      Uri.parse('$baseUrl/v1/demo/status'),
      headers: const {'Accept': 'application/json'},
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body is! Map) {
        throw ApiException(response.statusCode, 'Demo status failed');
      }
      return (
        enabled: body['enabled'] == true,
        roles: (body['roles'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
    }
    throw ApiException(response.statusCode, 'Demo status failed');
  }

  /// `POST /v1/demo/login` — unauthenticated. Same response shape as /login.
  Future<Map<String, dynamic>> demoLogin(String role) async {
    final response = await http.post(
      Uri.parse('$baseUrl/v1/demo/login'),
      headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
      body: jsonEncode({'role': role}),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    String message = 'Demo login failed';
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['message'] is String) message = body['message'];
    } catch (_) {}
    throw ApiException(response.statusCode, message);
  }

  // --- Agent visibility ---

  /// `GET /mobile/visibility` — per-module data-visibility descriptor.
  /// Throws on any non-200 so the caller can apply its safe fallback.
  Future<VisibilityDescriptor> getVisibility() async {
    final response = await http.get(
      Uri.parse('$baseUrl/mobile/visibility'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      return VisibilityDescriptor.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    }
    throw ApiException(response.statusCode, 'Failed to load visibility');
  }

  // --- Branding ---

  /// Pre-login (public). Fetch agency branding by slug.
  Future<Branding> getBrandingBySlug(String slug) async {
    final response = await http.get(
      Uri.parse('$baseUrl/v1/branding/$slug'),
      headers: {'Accept': 'application/json'},
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final block = (body['branding'] as Map?) ?? body;
      return Branding.fromJson(Map<String, dynamic>.from(block));
    }
    throw ApiException(response.statusCode, 'Failed to load branding');
  }

  /// Post-login. Returns the full logged-user payload (user, agency,
  /// permissions, server_time, branding).
  Future<Map<String, dynamic>> getLoggedUser() async {
    final response = await http.get(
      Uri.parse('$baseUrl/v1/logged-user'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) return body;
      throw ApiException(response.statusCode, 'Failed to load logged-user');
    }
    // Deliberately NOT routed through [_handleUnauthorized]: this endpoint can
    // return 401 even when the session is perfectly valid (it sits behind a
    // different guard than the `/v1/mobile/*` data endpoints, which keep
    // returning 200 with the same token). Treating its 401 as session-expiry
    // would clear a good token and bounce a freshly-logged-in user back to
    // login. The caller already falls back to slug-based branding, so a failure
    // here is non-fatal.
    throw ApiException(response.statusCode, 'Failed to load logged-user');
  }

  // --- User theme (mobile preference) ---

  /// `GET /v1/me/theme` → `{ "theme": "light" | "dark" }`. Backed by the
  /// `users.theme` column; default `dark`. Pulled on login so the app
  /// mirrors the user's saved web/mobile preference.
  Future<String?> getUserTheme() async {
    final response = await http.get(
      Uri.parse('$baseUrl/v1/me/theme'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body is Map && body['theme'] is String) return body['theme'] as String;
      return null;
    }
    throw ApiException(response.statusCode, 'Failed to load theme');
  }

  /// `PUT /v1/me/theme` body `{ "theme": "light" | "dark" }`. Persists the
  /// in-app toggle back to the server so the web cockpit picks up the same
  /// value.
  Future<void> setUserTheme(String theme) async {
    final response = await http.put(
      Uri.parse('$baseUrl/v1/me/theme'),
      headers: await _headers(),
      body: jsonEncode({'theme': theme}),
    ).timeout(_timeout);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Failed to update theme');
    }
  }

  // --- Agent QR ---

  Future<Map<String, dynamic>> getMyAgentQr() async {
    final response = await http.get(
      Uri.parse('$baseUrl/me/agent-qr'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(response.body));
    }
    throw ApiException(response.statusCode, 'Failed to load agent QR');
  }

  // --- Profile ---

  Future<Map<String, dynamic>> getProfile() async {
    if (useMockData) {
      await Future.delayed(const Duration(milliseconds: 500));
      return {
        'id': 1,
        'name': 'John Moosa',
        'email': 'john@hfcoastal.co.za',
        'branch': 'Amanzimtoti',
        'ffc_status': 'Active',
      };
    }

    final response = await http.get(
      Uri.parse('$baseUrl/profile'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) return body;
      throw ApiException(response.statusCode, 'Failed to load profile');
    }
    await _handleUnauthorized(response.statusCode);
    throw ApiException(response.statusCode, 'Failed to load profile');
  }

  // --- Today (card-driven cockpit) ---

  /// `GET /api/command-center/today` — role-aware list of cards rendered by
  /// the new generic Today screen. Replaces the legacy `dashboard` shape for
  /// that screen; other consumers (KPI tiles, mock test) still use
  /// [getDashboard].
  Future<TodayPayload> getToday() async {
    final response = await http
        .get(Uri.parse('$baseUrl/command-center/today'), headers: await _headers())
        .timeout(_timeout);

    if (response.statusCode == 200) {
      return TodayPayload.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    }
    throw ApiException(response.statusCode, 'Failed to load today');
  }

  /// `POST /api/command-center/today/refresh` — busts the 5-minute server
  /// cache then returns the same shape as [getToday].
  Future<TodayPayload> refreshToday() async {
    final response = await http
        .post(Uri.parse('$baseUrl/command-center/today/refresh'),
            headers: await _headers())
        .timeout(_timeout);

    if (response.statusCode == 200) {
      return TodayPayload.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    }
    throw ApiException(response.statusCode, 'Failed to refresh today');
  }

  // --- Tasks ---

  Future<List<CommandTask>> getTasks({String? status}) async {
    if (useMockData) return _mockTasks();

    final uri = Uri.parse('$baseUrl/command-center/tasks')
        .replace(queryParameters: status != null ? {'status': status} : null);

    final response = await http.get(uri, headers: await _headers()).timeout(_timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final list = data is List ? data : (data['data'] ?? data['tasks'] ?? []);
      return (list as List).map((e) => CommandTask.fromJson(e)).toList();
    }
    throw ApiException(response.statusCode, 'Failed to load tasks');
  }

  Future<CommandTask> createTask({
    required String title,
    String taskType = 'custom',
    String priority = 'normal',
    String? dueDate,
    String? description,
    bool sendReminder = true,
    int? propertyId,
    int? contactId,
  }) async {
    if (useMockData) {
      await Future.delayed(const Duration(milliseconds: 500));
      return CommandTask(id: 999, title: title, taskType: taskType, priority: priority);
    }

    final response = await http.post(
      Uri.parse('$baseUrl/command-center/tasks'),
      headers: await _headers(),
      body: jsonEncode({
        'title': title,
        'task_type': taskType,
        'priority': priority,
        if (dueDate != null) 'due_date': dueDate,
        if (description != null) 'description': description,
        'send_reminder': sendReminder,
        if (propertyId != null) 'property_id': propertyId,
        if (contactId != null) 'contact_id': contactId,
      }),
    ).timeout(_timeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return CommandTask.fromJson(jsonDecode(response.body));
    }
    throw ApiException(response.statusCode, 'Failed to create task');
  }

  /// Full task update (PUT /command-center/tasks/{id}). Pass only the fields
  /// you want changed; nulls are skipped. Used by the task detail edit form.
  Future<CommandTask> updateTask(int taskId, Map<String, dynamic> payload) async {
    if (useMockData) return CommandTask(id: taskId, title: payload['title']?.toString() ?? '');
    final response = await http.put(
      Uri.parse('$baseUrl/command-center/tasks/$taskId'),
      headers: await _headers(),
      body: jsonEncode(payload),
    ).timeout(_timeout);
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final map = body is Map && body['task'] is Map
          ? Map<String, dynamic>.from(body['task'])
          : Map<String, dynamic>.from(body as Map);
      return CommandTask.fromJson(map);
    }
    if (response.statusCode == 422) throw _parseValidationError(response.body);
    throw ApiException(response.statusCode, _serverErrorMessage(response.body, 'update task'));
  }

  Future<void> completeTask(int taskId) async {
    if (useMockData) return;

    final response = await http.post(
      Uri.parse('$baseUrl/command-center/tasks/$taskId/complete'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Failed to complete task');
    }
  }

  Future<void> updateTaskStatus(int taskId, String status) async {
    if (useMockData) return;

    final response = await http.patch(
      Uri.parse('$baseUrl/command-center/tasks/$taskId/status'),
      headers: await _headers(),
      body: jsonEncode({'status': status}),
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Failed to update task status');
    }
  }

  Future<void> resolveTask(int taskId, {required String resolution, int? extendDays, String? note}) async {
    if (useMockData) return;

    final response = await http.post(
      Uri.parse('$baseUrl/command-center/resolve-task/$taskId'),
      headers: await _headers(),
      body: jsonEncode({
        'resolution': resolution,
        if (extendDays != null) 'extend_days': extendDays,
        if (note != null) 'resolution_note': note,
      }),
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Failed to resolve task');
    }
  }

  /// Inbox reschedule — extends the task's due date by [days] days. Maps to
  /// the `resolve-task` endpoint with `resolution: extended`.
  Future<void> rescheduleTask(int taskId, int days) async {
    await resolveTask(taskId, resolution: 'extended', extendDays: days);
  }

  /// Inbox reschedule for events — extends the event date by [days] days.
  Future<void> rescheduleEvent(int eventId, int days) async {
    await resolveEvent(eventId, resolution: 'extended', extendDays: days);
  }

  /// Soft-delete (archive) a single task. Used by the Done-column per-card
  /// archive icon and also called by the server observer on status
  /// transition when `auto_archive_done_days = 0` (so after `completeTask`
  /// the task may already be archived — re-fetch rather than assume).
  Future<void> archiveTask(int taskId) async {
    if (useMockData) return;

    final response = await http.delete(
      Uri.parse('$baseUrl/command-center/tasks/$taskId'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw ApiException(response.statusCode, 'Failed to archive task');
    }
  }

  /// Bulk archive — soft-deletes every Done-column task for the current user.
  /// Returns the server's `archived` count.
  Future<int> archiveAllDone() async {
    if (useMockData) return 0;

    final response = await http.post(
      Uri.parse('$baseUrl/command-center/tasks/archive-done'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      return body is Map && body['archived'] is int ? body['archived'] as int : 0;
    }
    throw ApiException(response.statusCode, 'Failed to clear Done column');
  }

  /// Archived tasks, pre-grouped by `deleted_at` day.
  Future<ArchivedTasksData> getArchivedTasks() async {
    if (useMockData) return ArchivedTasksData();

    final response = await http.get(
      Uri.parse('$baseUrl/command-center/tasks/archived'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      return ArchivedTasksData.fromJson(jsonDecode(response.body));
    }
    throw ApiException(response.statusCode, 'Failed to load archived tasks');
  }

  /// Restore a soft-deleted task. Returns the restored task (now back in the
  /// Done column).
  Future<CommandTask> restoreTask(int taskId) async {
    if (useMockData) {
      await Future.delayed(const Duration(milliseconds: 300));
      return CommandTask(id: taskId, title: '');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/command-center/tasks/$taskId/restore'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      return CommandTask.fromJson(body is Map<String, dynamic> ? body : (body['task'] ?? {}));
    }
    throw ApiException(response.statusCode, 'Failed to restore task');
  }

  /// Performance payload (full scorecard, activity, property health).
  /// Returned as a raw Map for now — a dedicated model lands in PR 3.
  Future<Map<String, dynamic>> getPerformance() async {
    if (useMockData) return {};

    final response = await http.get(
      Uri.parse('$baseUrl/command-center/performance'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    }
    throw ApiException(response.statusCode, 'Failed to load performance');
  }

  /// User settings (reminder panels, task board, calendar prefs, channels).
  /// The response includes `is_agency_controlled` — when true the UI must
  /// disable inputs and show the amber banner.
  Future<Map<String, dynamic>> getUserSettings() async {
    if (useMockData) return {};

    final response = await http.get(
      Uri.parse('$baseUrl/command-center/user-settings'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    }
    throw ApiException(response.statusCode, 'Failed to load user settings');
  }

  /// PUT user settings. `auto_archive_done_days` accepts null (never), 0
  /// (immediate, via server observer), or 1..365. Empty-string submissions
  /// are coerced to null server-side.
  Future<Map<String, dynamic>> updateUserSettings(Map<String, dynamic> payload) async {
    if (useMockData) return payload;

    final response = await http.put(
      Uri.parse('$baseUrl/command-center/user-settings'),
      headers: await _headers(),
      body: jsonEncode(payload),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    }
    if (response.statusCode == 403) {
      throw ApiException(403, 'Agency-controlled — only agency admins can change these');
    }
    throw ApiException(response.statusCode, 'Failed to update user settings');
  }

  // --- Task Notes & Checklist ---

  Future<List<TaskNote>> getTaskNotes(int taskId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/command-center/tasks/$taskId/notes'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final list = body is Map ? (body['notes'] as List? ?? const []) : const [];
      return list
          .whereType<Map>()
          .map((e) => TaskNote.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    if (response.statusCode == 403) throw ApiException(403, "You don't have access to this task.");
    throw ApiException(response.statusCode, 'Failed to load notes');
  }

  Future<TaskNote> createTaskNote(int taskId, String body) async {
    final response = await http.post(
      Uri.parse('$baseUrl/command-center/tasks/$taskId/notes'),
      headers: await _headers(),
      body: jsonEncode({'body': body}),
    ).timeout(_timeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final json = jsonDecode(response.body);
      final map = json is Map && json['note'] is Map
          ? Map<String, dynamic>.from(json['note'])
          : Map<String, dynamic>.from(json as Map);
      return TaskNote.fromJson(map);
    }
    throw ApiException(response.statusCode, 'Failed to add note');
  }

  Future<TaskNote> updateTaskNote(int taskId, int noteId, String body) async {
    final response = await http.put(
      Uri.parse('$baseUrl/command-center/tasks/$taskId/notes/$noteId'),
      headers: await _headers(),
      body: jsonEncode({'body': body}),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final map = json is Map && json['note'] is Map
          ? Map<String, dynamic>.from(json['note'])
          : Map<String, dynamic>.from(json as Map);
      return TaskNote.fromJson(map);
    }
    throw ApiException(response.statusCode, 'Failed to update note');
  }

  Future<void> deleteTaskNote(int taskId, int noteId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/command-center/tasks/$taskId/notes/$noteId'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw ApiException(response.statusCode, 'Failed to delete note');
    }
  }

  Future<List<ChecklistItem>> getTaskChecklist(int taskId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/command-center/tasks/$taskId/checklist'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final list = body is Map ? (body['items'] as List? ?? const []) : const [];
      return list
          .whereType<Map>()
          .map((e) => ChecklistItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    if (response.statusCode == 403) throw ApiException(403, "You don't have access to this task.");
    throw ApiException(response.statusCode, 'Failed to load checklist');
  }

  Future<ChecklistItem> createChecklistItem(int taskId, String text) async {
    final response = await http.post(
      Uri.parse('$baseUrl/command-center/tasks/$taskId/checklist'),
      headers: await _headers(),
      body: jsonEncode({'text': text}),
    ).timeout(_timeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final json = jsonDecode(response.body);
      final map = json is Map && json['item'] is Map
          ? Map<String, dynamic>.from(json['item'])
          : Map<String, dynamic>.from(json as Map);
      return ChecklistItem.fromJson(map);
    }
    throw ApiException(response.statusCode, 'Failed to add item');
  }

  Future<ChecklistItem> updateChecklistItem(int taskId, String itemId, {bool? done, String? text}) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/command-center/tasks/$taskId/checklist/$itemId'),
      headers: await _headers(),
      body: jsonEncode({
        if (done != null) 'done': done,
        if (text != null) 'text': text,
      }),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final map = json is Map && json['item'] is Map
          ? Map<String, dynamic>.from(json['item'])
          : Map<String, dynamic>.from(json as Map);
      return ChecklistItem.fromJson(map);
    }
    throw ApiException(response.statusCode, 'Failed to update item');
  }

  Future<void> deleteChecklistItem(int taskId, String itemId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/command-center/tasks/$taskId/checklist/$itemId'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw ApiException(response.statusCode, 'Failed to delete item');
    }
  }

  // --- Calendar Events ---

  Future<List<CalendarEvent>> getCalendarEvents({String? month}) async {
    if (useMockData) return _mockEvents();

    final uri = Uri.parse('$baseUrl/command-center/calendar/events')
        .replace(queryParameters: month != null ? {'month': month} : null);

    final response = await http.get(uri, headers: await _headers()).timeout(_timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final list = data is List ? data : (data['data'] ?? data['events'] ?? []);
      return (list as List).map((e) => CalendarEvent.fromJson(e)).toList();
    }
    throw ApiException(response.statusCode, 'Failed to load events');
  }

  /// `GET /v1/mobile/calendar?year=YYYY&month=MM`.
  /// Range fetch used by the Calendar screen (Month/Week/Day/Agenda).
  /// Scoped server-side to the authenticated user and the same visible-class
  /// filter the web cockpit uses.
  Future<List<CalendarEvent>> getCalendarRange({
    required String start,
    required String end,
  }) async {
    if (useMockData) return _mockEvents();
    final s = DateTime.tryParse(start);
    final e = DateTime.tryParse(end);
    final mid = (s != null && e != null)
        ? DateTime.fromMillisecondsSinceEpoch(
            (s.millisecondsSinceEpoch + e.millisecondsSinceEpoch) ~/ 2)
        : (s ?? e ?? DateTime.now());
    final uri = Uri.parse('$baseUrl/v1/mobile/calendar').replace(
      queryParameters: {
        'year': '${mid.year}',
        'month': mid.month.toString().padLeft(2, '0'),
      },
    );
    debugPrint('[calendar] GET $uri');
    final response =
        await http.get(uri, headers: await _headers()).timeout(_timeout);
    if (kDebugMode) {
      debugPrint('[calendar] ← ${response.statusCode} '
          '(${response.body.length} bytes) ${response.body.length > 800 ? "${response.body.substring(0, 800)}…" : response.body}');
    }
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final list = body is List
          ? body
          : (body is Map ? (body['events'] ?? body['data'] ?? []) : []);
      return (list as List)
          .whereType<Map>()
          .map((e) => CalendarEvent.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    await _handleUnauthorized(response.statusCode);
    throw ApiException(response.statusCode, 'Failed to load calendar range');
  }

  /// `GET /v1/mobile/calendar?year=YYYY&month=MM`.
  /// Returns the events list AND a client-grouped `by_date` map keyed by
  /// `YYYY-MM-DD`. Scoped server-side to the authenticated user.
  Future<({List<CalendarEvent> events, Map<String, List<CalendarEvent>> byDate})>
      getCalendarByMonth(int year, int month) async {
    if (useMockData) {
      final ev = _mockEvents();
      return (events: ev, byDate: <String, List<CalendarEvent>>{});
    }
    final uri = Uri.parse('$baseUrl/v1/mobile/calendar').replace(queryParameters: {
      'year': '$year',
      'month': month.toString().padLeft(2, '0'),
    });
    final response = await http.get(uri, headers: await _headers()).timeout(_timeout);
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body is! Map) {
        throw ApiException(response.statusCode, 'Failed to load calendar');
      }
      final events = (body['events'] as List? ?? [])
          .whereType<Map>()
          .map((e) => CalendarEvent.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final byDate = <String, List<CalendarEvent>>{};
      for (final ev in events) {
        final d = ev.eventDate;
        final key = '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
        (byDate[key] ??= <CalendarEvent>[]).add(ev);
      }
      return (events: events, byDate: byDate);
    }
    await _handleUnauthorized(response.statusCode);
    throw ApiException(response.statusCode, 'Failed to load calendar');
  }

  Future<CalendarEvent> createEvent({
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
    if (useMockData) {
      await Future.delayed(const Duration(milliseconds: 500));
      return CalendarEvent(id: 999, title: title, eventDate: DateTime.parse(eventDate));
    }

    final response = await http.post(
      Uri.parse('$baseUrl/command-center/calendar'),
      headers: await _headers(),
      body: jsonEncode({
        'title': title,
        'event_date': eventDate,
        if (endDate != null) 'end_date': endDate,
        'event_type': eventType,
        'priority': priority,
        'all_day': allDay,
        if (description != null) 'description': description,
        'send_reminder': sendReminder,
        if (propertyId != null) 'property_id': propertyId,
        if (contactId != null) 'contact_id': contactId,
        if (category != null) 'category': category,
      }),
    ).timeout(_timeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return CalendarEvent.fromJson(jsonDecode(response.body));
    }
    if (response.statusCode == 422) throw _parseValidationError(response.body);
    throw ApiException(response.statusCode, 'Failed to create event');
  }

  /// PUT /command-center/calendar/{id}. Used for both the edit form and
  /// drag-to-reschedule (in the latter case pass only `event_date` +
  /// optional `end_date`).
  Future<CalendarEvent> updateEvent(int eventId, Map<String, dynamic> payload) async {
    if (useMockData) return CalendarEvent(id: eventId, title: payload['title']?.toString() ?? '', eventDate: DateTime.now());
    final response = await http.put(
      Uri.parse('$baseUrl/command-center/calendar/$eventId'),
      headers: await _headers(),
      body: jsonEncode(payload),
    ).timeout(_timeout);
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final map = body is Map && body['event'] is Map
          ? Map<String, dynamic>.from(body['event'])
          : Map<String, dynamic>.from(body as Map);
      return CalendarEvent.fromJson(map);
    }
    if (response.statusCode == 422) throw _parseValidationError(response.body);
    throw ApiException(response.statusCode, _serverErrorMessage(response.body, 'update event'));
  }

  /// DELETE /command-center/calendar/{id}. Cascades on the server: cancels
  /// pending invitations and notifies attendees.
  Future<void> deleteEvent(int eventId) async {
    if (useMockData) return;
    final response = await http.delete(
      Uri.parse('$baseUrl/command-center/calendar/$eventId'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw ApiException(response.statusCode, 'Failed to delete event');
    }
  }

  /// POST /command-center/calendar/{id}/dismiss — quick-action on the Today
  /// "today_events" card.
  Future<void> dismissEvent(int eventId) async {
    if (useMockData) return;
    final response = await http.post(
      Uri.parse('$baseUrl/command-center/calendar/$eventId/dismiss'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Failed to dismiss event');
    }
  }

  /// GET /command-center/calendar/conflicts?start=&end=&exclude_event_id=
  /// Called from the create/edit event form on date-time change (debounced).
  Future<List<CalendarEvent>> getCalendarConflicts({
    required String start,
    required String end,
    int? excludeEventId,
  }) async {
    if (useMockData) return const [];
    final uri = Uri.parse('$baseUrl/command-center/calendar/conflicts').replace(queryParameters: {
      'start': start,
      'end': end,
      if (excludeEventId != null) 'exclude_event_id': '$excludeEventId',
    });
    final response = await http.get(uri, headers: await _headers()).timeout(_timeout);
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final list = body is List ? body : (body is Map ? (body['conflicts'] as List? ?? const []) : const []);
      return list
          .whereType<Map>()
          .map((e) => CalendarEvent.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    throw ApiException(response.statusCode, 'Failed to load conflicts');
  }

  // --- Calendar Invitations ---

  Future<List<CalendarInvitation>> getCalendarInvitations() async {
    if (useMockData) return const [];
    final response = await http.get(
      Uri.parse('$baseUrl/command-center/calendar/invitations'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final list = body is Map ? (body['invitations'] as List? ?? const []) : const [];
      return list
          .whereType<Map>()
          .map((e) => CalendarInvitation.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    throw ApiException(response.statusCode, 'Failed to load invitations');
  }

  /// POST /command-center/calendar/invitations/{id}/respond
  /// [action] must be one of `accepted`, `tentative`, `declined`.
  Future<CalendarInvitation> respondToInvitation(int invitationId, String action, {String? notes}) async {
    if (useMockData) return CalendarInvitation(id: invitationId, eventId: 0, status: action);
    final response = await http.post(
      Uri.parse('$baseUrl/command-center/calendar/invitations/$invitationId/respond'),
      headers: await _headers(),
      body: jsonEncode({'action': action, if (notes != null) 'notes': notes}),
    ).timeout(_timeout);
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final map = body is Map && body['invitation'] is Map
          ? Map<String, dynamic>.from(body['invitation'])
          : Map<String, dynamic>.from(body as Map);
      return CalendarInvitation.fromJson(map);
    }
    if (response.statusCode == 422) throw _parseValidationError(response.body);
    throw ApiException(response.statusCode, 'Failed to respond to invitation');
  }

  /// POST /command-center/calendar/invitations/{id}/acknowledge — organizer
  /// confirms they've seen a declined invitation.
  Future<void> acknowledgeInvitation(int invitationId) async {
    if (useMockData) return;
    final response = await http.post(
      Uri.parse('$baseUrl/command-center/calendar/invitations/$invitationId/acknowledge'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Failed to acknowledge invitation');
    }
  }

  Future<void> completeEvent(int eventId) async {
    if (useMockData) return;

    final response = await http.post(
      Uri.parse('$baseUrl/command-center/calendar/$eventId/complete'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Failed to complete event');
    }
  }

  Future<void> resolveEvent(int eventId, {required String resolution, int? extendDays, String? note}) async {
    if (useMockData) return;

    final response = await http.post(
      Uri.parse('$baseUrl/command-center/resolve-event/$eventId'),
      headers: await _headers(),
      body: jsonEncode({
        'resolution': resolution,
        if (extendDays != null) 'extend_days': extendDays,
        if (note != null) 'resolution_note': note,
      }),
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Failed to resolve event');
    }
  }

  // --- Full Add / Edit Event flow (v1 command-center) ---
  //
  // These hit the `/api/v1/command-center/calendar/*` endpoints (note the `v1`
  // prefix) that mirror the web add-event panel: form bootstrap, property +
  // attendee search, property-owner suggestions, and the rich create/update
  // that auto-files link records and sends agent invitations server-side.

  /// `GET /v1/command-center/calendar/options` — event classes, priorities and
  /// attendee roles used to render the add-event form.
  Future<CalendarOptions> getCalendarOptions() async {
    final response = await http.get(
      Uri.parse('$baseUrl/v1/command-center/calendar/options'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 200) {
      return CalendarOptions.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    }
    await _handleUnauthorized(response.statusCode);
    throw ApiException(response.statusCode, 'Failed to load event options');
  }

  /// `GET /v1/mobile/properties?q=` — lightweight property search for the
  /// add-event property picker (id, address, price_display, thumbnail, …).
  Future<List<PropertySearchResult>> searchCalendarProperties(String q) async {
    final uri = Uri.parse('$baseUrl/v1/mobile/properties')
        .replace(queryParameters: {'q': q});
    final response =
        await http.get(uri, headers: await _headers()).timeout(_timeout);
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final list = body is Map
          ? (body['properties'] as List? ?? body['data'] as List? ?? const [])
          : (body is List ? body : const []);
      return list
          .whereType<Map>()
          .map((e) =>
              PropertySearchResult.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    await _handleUnauthorized(response.statusCode);
    throw ApiException(response.statusCode, 'Failed to search properties');
  }

  /// `GET /v1/command-center/calendar/properties/{id}/owners` — the linked
  /// contacts (with a pre-set role) offered as one-tap attendee suggestions
  /// when a property is added.
  Future<List<PropertyOwner>> getPropertyOwners(int propertyId) async {
    final response = await http.get(
      Uri.parse(
          '$baseUrl/v1/command-center/calendar/properties/$propertyId/owners'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final list = body is List
          ? body
          : (body is Map ? (body['owners'] as List? ?? body['data'] as List? ?? const []) : const []);
      return list
          .whereType<Map>()
          .map((e) => PropertyOwner.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    await _handleUnauthorized(response.statusCode);
    throw ApiException(response.statusCode, 'Failed to load property owners');
  }

  /// `GET /v1/command-center/calendar/search/attendees?q=` — contacts + agents,
  /// scoped to the agent's visibility. Each carries a `type` of
  /// `contact` | `agent`.
  Future<List<AttendeeSearchResult>> searchAttendees(String q) async {
    final uri = Uri.parse('$baseUrl/v1/command-center/calendar/search/attendees')
        .replace(queryParameters: {'q': q});
    final response =
        await http.get(uri, headers: await _headers()).timeout(_timeout);
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final list = body is List
          ? body
          : (body is Map ? (body['results'] as List? ?? body['data'] as List? ?? const []) : const []);
      return list
          .whereType<Map>()
          .map((e) =>
              AttendeeSearchResult.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    await _handleUnauthorized(response.statusCode);
    throw ApiException(response.statusCode, 'Failed to search attendees');
  }

  /// `POST /v1/command-center/calendar` — full create. The backend auto-files
  /// property/contact link records and sends invitations to agent attendees.
  /// Returns the full event payload as [EventFormData]. Throws
  /// [ValidationException] on 422 so the form can map errors to fields.
  Future<EventFormData> createCalendarEventFull(
      Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('$baseUrl/v1/command-center/calendar'),
      headers: await _headers(),
      body: jsonEncode(body),
    ).timeout(_timeout);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return EventFormData.fromResponseBody(response.body);
    }
    if (response.statusCode == 422) throw _parseValidationError(response.body);
    await _handleUnauthorized(response.statusCode);
    throw ApiException(
        response.statusCode, _serverErrorMessage(response.body, 'create event'));
  }

  /// `GET /v1/command-center/calendar/{id}` — full event for pre-filling the
  /// edit sheet (linked properties + rich attendees + `is_editable`).
  Future<EventFormData> getCalendarEventDetail(int eventId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/v1/command-center/calendar/$eventId'),
      headers: await _headers(),
    ).timeout(_timeout);
    if (response.statusCode == 200) {
      return EventFormData.fromResponseBody(response.body);
    }
    await _handleUnauthorized(response.statusCode);
    throw ApiException(response.statusCode, 'Failed to load event');
  }

  /// `PUT /v1/command-center/calendar/{id}` — full update. Sending
  /// `property_ids`/`attendees`/`deal_id` re-syncs those links (and invites any
  /// newly added agents). Returns the full updated event.
  Future<EventFormData> updateCalendarEventFull(
      int eventId, Map<String, dynamic> body) async {
    final response = await http.put(
      Uri.parse('$baseUrl/v1/command-center/calendar/$eventId'),
      headers: await _headers(),
      body: jsonEncode(body),
    ).timeout(_timeout);
    if (response.statusCode == 200) {
      return EventFormData.fromResponseBody(response.body);
    }
    if (response.statusCode == 422) throw _parseValidationError(response.body);
    await _handleUnauthorized(response.statusCode);
    throw ApiException(
        response.statusCode, _serverErrorMessage(response.body, 'update event'));
  }

  // --- Properties ---

  /// Session-scoped in-memory cache for the property options dropdown data.
  /// Static so every [ApiService] instance shares it; cleared on app
  /// restart because it's never persisted to disk (per the spec — admins
  /// edit these on the web and stale cached entries would be confusing).
  static PropertyOptions? _cachedPropertyOptions;

  Future<PropertyOptions> getPropertyOptions({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedPropertyOptions != null) {
      return _cachedPropertyOptions!;
    }
    final response = await http.get(
      Uri.parse('$baseUrl/mobile/properties/options'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final options =
          PropertyOptions.fromJson(Map<String, dynamic>.from(data));
      _cachedPropertyOptions = options;
      return options;
    }
    throw ApiException(response.statusCode, 'Failed to load property options');
  }

  Future<List<Property>> getProperties({AgentFilter? agentFilter}) async {
    final agentValue = agentFilter?.queryValue;
    final uri = Uri.parse('$baseUrl/mobile/properties').replace(
      queryParameters: {
        // Mine → omitted; All → '' ; specific agent → '<id>'.
        if (agentValue != null) 'agent_id': agentValue,
      },
    );
    final response = await http.get(
      agentValue != null ? uri : Uri.parse('$baseUrl/mobile/properties'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is! Map) {
        throw ApiException(response.statusCode, 'Failed to load properties');
      }
      final list = data['properties'] as List? ?? [];
      return list.map((e) => Property.fromJson(e)).toList();
    }
    await _handleUnauthorized(response.statusCode);
    throw ApiException(response.statusCode, 'Failed to load properties');
  }

  Future<Property> getProperty(int id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/mobile/properties/$id'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is! Map || data['property'] is! Map) {
        throw ApiException(response.statusCode, 'Failed to load property');
      }
      return Property.fromJson(data['property']);
    }
    if (response.statusCode == 403) {
      throw ApiException(403, _scopeForbiddenMessage(response.body));
    }
    await _handleUnauthorized(response.statusCode);
    throw ApiException(response.statusCode, 'Failed to load property');
  }

  // --- Property24 location cascade ---

  Future<List<P24Location>> _getP24(String path, Map<String, String> qp) async {
    final uri = Uri.parse('$baseUrl/mobile/p24/$path')
        .replace(queryParameters: {
      for (final e in qp.entries)
        if (e.value.isNotEmpty) e.key: e.value,
    });
    final response =
        await http.get(uri, headers: await _headers()).timeout(_timeout);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final list = (data['data'] as List?) ?? const [];
      return list
          .map((e) => P24Location.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    throw ApiException(response.statusCode, 'Failed to load $path');
  }

  Future<List<P24Location>> getP24Provinces({String q = ''}) =>
      _getP24('provinces', {'q': q});

  Future<List<P24Location>> getP24Cities(
          {required int provinceId, String q = ''}) =>
      _getP24('cities', {'province_id': '$provinceId', 'q': q});

  Future<List<P24Location>> getP24Suburbs(
          {required int cityId, String q = ''}) =>
      _getP24('suburbs', {'city_id': '$cityId', 'q': q});

  // NOTE: the Core Matches / Buyer Wishlist suburb picker uses the same
  // `/mobile/p24/*` cascade above (getP24Provinces/Cities/Suburbs). The
  // suburb `id` it returns is what gets submitted as `p24_suburb_ids`, and
  // is the same value stored as `p24_suburb_id` on a property — so a
  // match's suburbs always line up with property suburbs.

  Future<Property> createProperty(Map<String, dynamic> data) async {
    final reqBody = jsonEncode(data);
    if (kDebugMode) debugPrint('[createProperty] body: $reqBody');
    final response = await http.post(
      Uri.parse('$baseUrl/mobile/properties'),
      headers: await _headers(),
      body: reqBody,
    ).timeout(_timeout);

    if (kDebugMode) {
      debugPrint('[createProperty] ${response.statusCode}: ${response.body}');
    }

    if (response.statusCode == 200 || response.statusCode == 201) {
      final body = jsonDecode(response.body);
      return Property.fromJson(body['property'] ?? body);
    }
    if (response.statusCode == 422) {
      throw _parseValidationError(response.body);
    }
    throw ApiException(
        response.statusCode, _serverErrorMessage(response.body, 'create'));
  }

  Future<Property> updateProperty(int id, Map<String, dynamic> data) async {
    final reqBody = jsonEncode(data);
    if (kDebugMode) debugPrint('[updateProperty] body: $reqBody');
    final response = await http.put(
      Uri.parse('$baseUrl/mobile/properties/$id'),
      headers: await _headers(),
      body: reqBody,
    ).timeout(_timeout);

    if (kDebugMode) {
      debugPrint('[updateProperty] ${response.statusCode}: ${response.body}');
    }

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      return Property.fromJson(body['property'] ?? body);
    }
    if (response.statusCode == 422) {
      throw _parseValidationError(response.body);
    }
    throw ApiException(
        response.statusCode, _serverErrorMessage(response.body, 'update'));
  }

  /// Best-effort extraction of a useful error message from a non-success
  /// response body. Tries Laravel's `message`/`exception` shape first,
  /// falls back to a truncated raw body so the user (and console log) can
  /// actually see what the server complained about instead of just
  /// "Failed to create property".
  String _serverErrorMessage(String body, String verb) {
    try {
      final json = jsonDecode(body);
      if (json is Map) {
        final msg = json['message']?.toString();
        final exc = json['exception']?.toString();
        if (msg != null && msg.isNotEmpty) {
          return exc != null ? '$msg ($exc)' : msg;
        }
      }
    } catch (_) {}
    if (body.isEmpty) return 'Failed to $verb property (empty response)';
    return body.length > 400
        ? '${body.substring(0, 400)}…'
        : body;
  }

  /// Parses a Laravel-style 422 body into a [ValidationException] with one
  /// message per field (the first message in each `errors[field]` list).
  ValidationException _parseValidationError(String body) {
    String topMessage = 'Validation failed';
    final fieldErrors = <String, String>{};
    try {
      final json = jsonDecode(body);
      if (json is Map) {
        if (json['message'] is String) topMessage = json['message'] as String;
        final errors = json['errors'];
        if (errors is Map) {
          errors.forEach((k, v) {
            if (v is List && v.isNotEmpty) {
              fieldErrors[k.toString()] = v.first.toString();
            } else if (v is String) {
              fieldErrors[k.toString()] = v;
            }
          });
        }
      }
    } catch (_) {}
    return ValidationException(topMessage, fieldErrors);
  }

  // --- Spaces & Features ---

  Future<SpacesCatalog> getSpacesCatalog({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();

    if (!forceRefresh) {
      final cached = prefs.getString(_spacesCatalogKey);
      final ts = prefs.getInt(_spacesCatalogTsKey);
      if (cached != null && ts != null) {
        final age = DateTime.now().millisecondsSinceEpoch - ts;
        if (age < _spacesCatalogTtl.inMilliseconds) {
          try {
            return SpacesCatalog.fromJson(
                Map<String, dynamic>.from(jsonDecode(cached)));
          } catch (_) {
            // fall through to network
          }
        }
      }
    }

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/mobile/properties/spaces/catalog'),
        headers: await _headers(),
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final map = decoded is Map<String, dynamic>
            ? decoded
            : <String, dynamic>{};
        await prefs.setString(_spacesCatalogKey, jsonEncode(map));
        await prefs.setInt(
            _spacesCatalogTsKey, DateTime.now().millisecondsSinceEpoch);
        return SpacesCatalog.fromJson(map);
      }
      throw ApiException(response.statusCode, 'Failed to load spaces catalog');
    } on SocketException {
      // offline — fall back to stale cache if we have one
      final cached = prefs.getString(_spacesCatalogKey);
      if (cached != null) {
        return SpacesCatalog.fromJson(
            Map<String, dynamic>.from(jsonDecode(cached)));
      }
      rethrow;
    }
  }

  Future<PropertySpacesData> getPropertySpaces(int id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/mobile/properties/$id/spaces'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return PropertySpacesData.fromJson(Map<String, dynamic>.from(data));
    }
    throw ApiException(response.statusCode, 'Failed to load property spaces');
  }

  Future<PropertySpacesData> updatePropertySpaces(
      int id, Map<String, dynamic> payload) async {
    final response = await http.put(
      Uri.parse('$baseUrl/mobile/properties/$id/spaces'),
      headers: await _headers(),
      body: jsonEncode(payload),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return PropertySpacesData.fromJson(Map<String, dynamic>.from(data));
    }

    if (response.statusCode == 403) {
      throw ApiException(
          403, "You don't have permission to edit this property");
    }

    if (response.statusCode == 422) {
      String msg = 'Validation failed';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['errors'] is Map) {
          final errors = body['errors'] as Map;
          if (errors.isNotEmpty) {
            final firstKey = errors.keys.first.toString();
            final firstVal = errors[firstKey];
            final firstMsg = (firstVal is List && firstVal.isNotEmpty)
                ? firstVal.first.toString()
                : firstVal.toString();
            msg = '$firstKey: $firstMsg';
          }
        } else if (body is Map && body['message'] is String) {
          msg = body['message'] as String;
        }
      } catch (_) {}
      throw ApiException(422, msg);
    }

    throw ApiException(response.statusCode, 'Failed to save spaces');
  }

  // --- Property Overview ---

  /// 60-second in-memory cache of the overview payload, keyed by property id.
  /// Expires the moment the TTL is exceeded; pull-to-refresh callers should
  /// pass [forceRefresh] to bypass it.
  static final Map<int, ({DateTime fetchedAt, PropertyOverview data})>
      _overviewCache = {};
  static const Duration _overviewTtl = Duration(seconds: 60);

  Future<PropertyOverview> getPropertyOverview(int id,
      {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = _overviewCache[id];
      if (cached != null &&
          DateTime.now().difference(cached.fetchedAt) < _overviewTtl) {
        return cached.data;
      }
    }

    final response = await http.get(
      Uri.parse('$baseUrl/mobile/properties/$id/overview'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final raw = jsonDecode(response.body);
      final map = raw is Map<String, dynamic>
          ? (raw['property'] is Map<String, dynamic>
              ? raw['property'] as Map<String, dynamic>
              : raw)
          : <String, dynamic>{};
      // The backend returns the full property record at the top level with
      // sibling `portal_links` / `placements` arrays; if they live outside
      // `property` when wrapped, fold them in so the model sees a flat shape.
      if (raw is Map<String, dynamic> &&
          raw['portal_links'] != null &&
          map['portal_links'] == null) {
        map['portal_links'] = raw['portal_links'];
      }
      if (raw is Map<String, dynamic> &&
          raw['placements'] != null &&
          map['placements'] == null) {
        map['placements'] = raw['placements'];
      }
      final overview = PropertyOverview.fromJson(map);
      _overviewCache[id] =
          (fetchedAt: DateTime.now(), data: overview);
      return overview;
    }
    if (response.statusCode == 403) {
      throw ApiException(403, "You don't have access to this property");
    }
    throw ApiException(response.statusCode, 'Failed to load overview');
  }

  void invalidateOverviewCache(int id) => _overviewCache.remove(id);

  // --- Property Compliance ---

  Future<PropertyCompliance> getPropertyCompliance(int id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/mobile/properties/$id/compliance'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      return PropertyCompliance.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    }
    if (response.statusCode == 403) {
      throw ApiException(403, "You don't have access to this property");
    }
    throw ApiException(response.statusCode, 'Failed to load compliance');
  }

  /// "Send Authority to Market". Clears the property and makes it
  /// marketable. Throws [MarketingBlockedException] on a 422
  /// `marketing_blocked` response so the caller can re-render the gates.
  Future<PropertyCompliance> sendToMarket(int id) async {
    final response = await http.post(
      Uri.parse('$baseUrl/mobile/properties/$id/compliance/send-to-market'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      // The success body is a thin confirmation; refetch the full report so
      // the live banner has snapshot_at/first_marketed_at + checklist.
      invalidateOverviewCache(id);
      return getPropertyCompliance(id);
    }
    if (response.statusCode == 422) {
      Map<String, dynamic> body = const {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) body = Map<String, dynamic>.from(decoded);
      } catch (_) {}
      throw MarketingBlockedException(
        body['message']?.toString() ??
            'Marketing is blocked — property not compliance-ready.',
        (body['blocked_by'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        PropertyCompliance.fromBlockedReport(id, body),
      );
    }
    if (response.statusCode == 403) {
      throw ApiException(
          403, "You don't have permission to market this property");
    }
    throw ApiException(response.statusCode, 'Failed to send to market');
  }

  // --- Property Contacts ---

  Future<List<PropertyContact>> getPropertyContacts(int id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/mobile/properties/$id/contacts'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final list = body is Map ? (body['contacts'] as List? ?? []) : [];
      return list
          .whereType<Map>()
          .map((e) => PropertyContact.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    if (response.statusCode == 403) {
      throw ApiException(403, "You don't have access to this property");
    }
    throw ApiException(response.statusCode, 'Failed to load contacts');
  }

  /// Link an existing contact (pass `contact_id`) or create + link a new one.
  /// Throws [DuplicateContactException] on a 422 carrying `duplicate_id`.
  Future<void> addPropertyContact(int id, Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('$baseUrl/mobile/properties/$id/contacts'),
      headers: await _headers(),
      body: jsonEncode(body),
    ).timeout(_timeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      invalidateOverviewCache(id);
      return;
    }
    if (response.statusCode == 422) {
      try {
        final json = jsonDecode(response.body);
        if (json is Map && json['duplicate_id'] != null) {
          final dup = json['duplicate_id'];
          final dupId =
              dup is num ? dup.toInt() : int.tryParse(dup.toString()) ?? 0;
          throw DuplicateContactException(
              dupId,
              json['message']?.toString() ??
                  'A contact with that phone or email already exists');
        }
      } catch (e) {
        if (e is DuplicateContactException) rethrow;
      }
      throw _parseValidationError(response.body);
    }
    if (response.statusCode == 403) {
      throw ApiException(
          403, "You don't have permission to edit this property");
    }
    throw ApiException(
        response.statusCode, _serverErrorMessage(response.body, 'link contact'));
  }

  /// Unlinks (does not delete) a contact from a property.
  Future<void> deletePropertyContact(int id, int contactId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/mobile/properties/$id/contacts/$contactId'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200 || response.statusCode == 204) {
      invalidateOverviewCache(id);
      return;
    }
    if (response.statusCode == 403) {
      throw ApiException(
          403, "You don't have permission to edit this property");
    }
    throw ApiException(response.statusCode, 'Failed to unlink contact');
  }

  // --- Gallery Tags (custom tag CRUD) ---

  Future<GalleryTagsData> addGalleryTag(int propertyId, String tag) async {
    final response = await http.post(
      Uri.parse('$baseUrl/mobile/properties/$propertyId/gallery/tags'),
      headers: await _headers(),
      body: jsonEncode({'tag': tag}),
    ).timeout(_timeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return GalleryTagsData.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body)));
    }
    if (response.statusCode == 422) {
      String msg = 'Tag is invalid';
      try {
        final body = jsonDecode(response.body);
        if (body is Map) {
          if (body['message'] is String) {
            msg = body['message'] as String;
          } else if (body['errors'] is Map) {
            final errors = body['errors'] as Map;
            if (errors['tag'] is List && (errors['tag'] as List).isNotEmpty) {
              msg = (errors['tag'] as List).first.toString();
            }
          }
        }
      } catch (_) {}
      throw ApiException(422, msg);
    }
    if (response.statusCode == 403) {
      throw ApiException(403, "You don't have permission to edit tags");
    }
    throw ApiException(response.statusCode, 'Failed to add tag');
  }

  Future<GalleryTagsData> deleteGalleryTag(int propertyId, String tag) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/mobile/properties/$propertyId/gallery/tags'),
      headers: await _headers(),
      body: jsonEncode({'tag': tag}),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      return GalleryTagsData.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body)));
    }
    if (response.statusCode == 403) {
      throw ApiException(403, "You don't have permission to edit tags");
    }
    throw ApiException(response.statusCode, 'Failed to remove tag');
  }

  Future<GalleryTagsData> getGalleryTags(int propertyId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/mobile/properties/$propertyId/gallery/tags'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return GalleryTagsData.fromJson(Map<String, dynamic>.from(data));
    }
    if (response.statusCode == 403) {
      throw ApiException(
          403, "You don't have permission to view this property");
    }
    throw ApiException(response.statusCode, 'Failed to load gallery tags');
  }

  /// Uploads a single image. Pass [roomTag] `null` to upload untagged.
  ///
  /// Throws [TagValidationException] on a 422 response whose body contains
  /// `available_tags`, so the caller can refresh its local tag list.
  Future<UploadedImage> uploadPropertyImage(
      int propertyId, File image, String? roomTag) async {
    final token = await getToken();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/mobile/properties/$propertyId/images'),
    );
    request.headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(await http.MultipartFile.fromPath('image', image.path));
    if (roomTag != null) request.fields['room_tag'] = roomTag;

    final streamed = await request.send().timeout(_timeout);
    final body = await streamed.stream.bytesToString().timeout(_timeout);
    final status = streamed.statusCode;

    if (status == 200 || status == 201) {
      try {
        final json = jsonDecode(body);
        if (json is Map) {
          final aid = json['analysis_id'];
          return UploadedImage(
            url: json['url']?.toString() ?? '',
            roomTag: json['room_tag']?.toString(),
            analysisId: aid is num
                ? aid.toInt()
                : (aid is String ? int.tryParse(aid) : null),
          );
        }
      } catch (_) {}
      return const UploadedImage(url: '');
    }

    if (status == 422) {
      List<String> available = const [];
      String message = "Tag is not available on this property";
      try {
        final json = jsonDecode(body);
        if (json is Map) {
          if (json['available_tags'] is List) {
            available = (json['available_tags'] as List)
                .map((e) => e.toString())
                .toList();
          }
          if (json['message'] is String) {
            message = json['message'] as String;
          } else if (json['errors'] is Map) {
            final errors = json['errors'] as Map;
            if (errors['room_tag'] is List &&
                (errors['room_tag'] as List).isNotEmpty) {
              message = (errors['room_tag'] as List).first.toString();
            }
          }
        }
      } catch (_) {}
      throw TagValidationException(message, available);
    }

    if (status == 403) {
      throw ApiException(
          403, "You don't have permission to upload to this property");
    }

    throw ApiException(status, 'Failed to upload image');
  }

  // --- Rental inspections ---
  //
  // All endpoints live under `/v1/mobile/properties/{id}/rental-images`. The
  // backend is the source of truth: every mutating call returns the full
  // `rental_images` structure, so callers re-render from the response rather
  // than mutating local state. Gate the feature on the property's
  // `rental_inspections_available` flag; the 422 `not_a_rental` / `not_live`
  // codes are a defensive backstop and surface as [RentalNotEligibleException].

  String _rentalBase(int propertyId) =>
      '$baseUrl/v1/mobile/properties/$propertyId/rental-images';

  /// Decodes a rental-images success body into [RentalInspections] and maps
  /// the eligibility / access / stale-section failure modes onto typed
  /// exceptions the UI handles.
  RentalInspections _parseRentalBody(int status, String body) {
    if (status == 200 || status == 201) {
      final json = jsonDecode(body);
      return RentalInspections.fromJson(Map<String, dynamic>.from(json as Map));
    }
    if (status == 403) {
      throw ApiException(403, _scopeForbiddenMessage(body));
    }
    if (status == 404) {
      throw ApiException(404, 'That section no longer exists.');
    }
    if (status == 422) {
      String? code;
      String message = 'This property is not eligible for rental inspections.';
      try {
        final json = jsonDecode(body);
        if (json is Map) {
          code = json['code']?.toString();
          if (json['message'] is String &&
              (json['message'] as String).isNotEmpty) {
            message = json['message'] as String;
          }
        }
      } catch (_) {}
      if (code == 'not_a_rental' || code == 'not_live') {
        throw RentalNotEligibleException(code!, message);
      }
      throw _parseValidationError(body);
    }
    throw ApiException(status, 'Failed to load rental inspections');
  }

  /// GET — fetch the full rental-images structure for a property.
  Future<RentalInspections> getRentalInspections(int propertyId) async {
    final response = await http
        .get(Uri.parse(_rentalBase(propertyId)), headers: await _headers())
        .timeout(_timeout);
    return _parseRentalBody(response.statusCode, response.body);
  }

  /// POST (multipart) — upload one or more images to a section. Pass
  /// [customId] only when [section] is [RentalSectionType.custom].
  ///
  /// Uploads can be large (up to 50 MB each); we widen the timeout to match.
  Future<RentalInspections> uploadRentalImages(
    int propertyId,
    RentalSectionType section,
    List<File> images, {
    String? customId,
  }) async {
    final token = await getToken();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${_rentalBase(propertyId)}/upload'),
    );
    request.headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.fields['section'] = section.apiValue;
    if (section == RentalSectionType.custom && customId != null) {
      request.fields['custom_id'] = customId;
    }
    for (final image in images) {
      request.files
          .add(await http.MultipartFile.fromPath('images[]', image.path));
    }

    final streamed = await request.send().timeout(const Duration(minutes: 5));
    final body =
        await streamed.stream.bytesToString().timeout(const Duration(minutes: 5));
    return _parseRentalBody(streamed.statusCode, body);
  }

  Future<RentalInspections> _rentalSave(
      int propertyId, Map<String, dynamic> payload) async {
    final response = await http
        .post(Uri.parse('${_rentalBase(propertyId)}/save'),
            headers: await _headers(), body: jsonEncode(payload))
        .timeout(_timeout);
    return _parseRentalBody(response.statusCode, response.body);
  }

  /// POST /save — set (or clear, when [date] is null) a section's date. Pass
  /// [customId] only for a custom section.
  Future<RentalInspections> setRentalDate(
    int propertyId,
    RentalSectionType section,
    String? date, {
    String? customId,
  }) {
    return _rentalSave(propertyId, {
      'action': 'set_date',
      'section': section.apiValue,
      'date': date,
      if (section == RentalSectionType.custom && customId != null)
        'custom_id': customId,
    });
  }

  /// POST /save — add a custom section. The server mints the id.
  Future<RentalInspections> addRentalSection(int propertyId, String name) {
    return _rentalSave(propertyId, {'action': 'add_section', 'name': name});
  }

  /// POST /save — rename a custom section.
  Future<RentalInspections> renameRentalSection(
    int propertyId,
    String customId,
    String name,
  ) {
    return _rentalSave(propertyId, {
      'action': 'rename_section',
      'custom_id': customId,
      'name': name,
    });
  }

  /// POST /delete — remove one image at [index] within a section. Pass
  /// [customId] only for a custom section.
  Future<RentalInspections> deleteRentalImage(
    int propertyId,
    RentalSectionType section,
    int index, {
    String? customId,
  }) async {
    final response = await http
        .post(Uri.parse('${_rentalBase(propertyId)}/delete'),
            headers: await _headers(),
            body: jsonEncode({
              'section': section.apiValue,
              'custom_id':
                  section == RentalSectionType.custom ? customId : null,
              'index': index,
            }))
        .timeout(_timeout);
    return _parseRentalBody(response.statusCode, response.body);
  }

  // --- Contacts ---

  Future<List<Contact>> listContacts({
    String? search,
    int perPage = 50,
    AgentFilter? agentFilter,
  }) async {
    final agentValue = agentFilter?.queryValue;
    final qp = <String, String>{
      'per_page': '$perPage',
      if (search != null && search.isNotEmpty) 'search': search,
      // Mine → queryValue is null → param omitted.
      // All → '' ; specific agent → '<id>'.
      if (agentValue != null) 'agent_id': agentValue,
    };
    final uri = Uri.parse('$baseUrl/mobile/contacts').replace(queryParameters: qp);
    final response = await http.get(uri, headers: await _headers()).timeout(_timeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final list = body is List
          ? body
          : (body['data'] ?? body['contacts'] ?? []);
      return (list as List)
          .whereType<Map>()
          .map((e) => Contact.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    throw ApiException(response.statusCode, 'Failed to load contacts');
  }

  Future<Contact> getContact(int id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/mobile/contacts/$id'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final map = body is Map && body['contact'] is Map
          ? Map<String, dynamic>.from(body['contact'])
          : Map<String, dynamic>.from(body as Map);
      return Contact.fromJson(map);
    }
    if (response.statusCode == 403) {
      throw ApiException(403, _scopeForbiddenMessage(response.body));
    }
    throw ApiException(response.statusCode, 'Failed to load contact');
  }

  /// 403 body → server `message`, defaulting to the agreed visibility copy.
  String _scopeForbiddenMessage(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map && json['message'] is String) {
        final m = (json['message'] as String).trim();
        if (m.isNotEmpty) return m;
      }
    } catch (_) {}
    return 'Outside your visibility scope';
  }

  // --- Contact compliance (Consent / Drive / FICA) ---

  /// Pulls the server `message` out of a 403 body, defaulting to the
  /// agreed "Not your contact." copy when the agent doesn't own the contact.
  String _forbiddenMessage(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map && json['message'] is String) {
        final m = (json['message'] as String).trim();
        if (m.isNotEmpty) return m;
      }
    } catch (_) {}
    return 'Not your contact.';
  }

  Future<ContactConsentData> getContactConsent(int id) async {
    final response = await http
        .get(Uri.parse('$baseUrl/mobile/contacts/$id/consent'),
            headers: await _headers())
        .timeout(_timeout);
    if (response.statusCode == 200) {
      return ContactConsentData.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    }
    if (response.statusCode == 403) {
      throw ApiException(403, _forbiddenMessage(response.body));
    }
    throw ApiException(response.statusCode, 'Failed to load consent');
  }

  Future<ContactConsentData> giveContactConsent(
      int id, String consentType, String method) async {
    final response = await http
        .post(Uri.parse('$baseUrl/mobile/contacts/$id/consent'),
            headers: await _headers(),
            body: jsonEncode({'consent_type': consentType, 'method': method}))
        .timeout(_timeout);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return ContactConsentData.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    }
    if (response.statusCode == 403) {
      throw ApiException(403, _forbiddenMessage(response.body));
    }
    if (response.statusCode == 422) throw _parseValidationError(response.body);
    throw ApiException(
        response.statusCode, _serverErrorMessage(response.body, 'give consent'));
  }

  Future<ContactConsentData> revokeContactConsent(int id, String consentType,
      {String? reason}) async {
    final response = await http
        .post(Uri.parse('$baseUrl/mobile/contacts/$id/consent/revoke'),
            headers: await _headers(),
            body: jsonEncode({
              'consent_type': consentType,
              if (reason != null && reason.isNotEmpty) 'reason': reason,
            }))
        .timeout(_timeout);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return ContactConsentData.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    }
    if (response.statusCode == 403) {
      throw ApiException(403, _forbiddenMessage(response.body));
    }
    if (response.statusCode == 422) throw _parseValidationError(response.body);
    throw ApiException(response.statusCode,
        _serverErrorMessage(response.body, 'revoke consent'));
  }

  Future<ContactDriveData> getContactDrive(int id) async {
    final response = await http
        .get(Uri.parse('$baseUrl/mobile/contacts/$id/drive'),
            headers: await _headers())
        .timeout(_timeout);
    if (response.statusCode == 200) {
      return ContactDriveData.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    }
    if (response.statusCode == 403) {
      throw ApiException(403, _forbiddenMessage(response.body));
    }
    throw ApiException(response.statusCode, 'Failed to load documents');
  }

  /// Uploads a document (multipart). [documentTypeId] / [propertyId] optional.
  Future<DriveDoc> uploadContactDocument(int id, File file,
      {int? documentTypeId, int? propertyId}) async {
    final token = await getToken();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/mobile/contacts/$id/drive'),
    );
    request.headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    if (documentTypeId != null) {
      request.fields['document_type_id'] = '$documentTypeId';
    }
    if (propertyId != null) request.fields['property_id'] = '$propertyId';

    final streamed = await request.send().timeout(_timeout);
    final body = await streamed.stream.bytesToString().timeout(_timeout);
    final status = streamed.statusCode;

    if (status == 200 || status == 201) {
      final json = jsonDecode(body);
      final doc = json is Map && json['document'] is Map
          ? Map<String, dynamic>.from(json['document'])
          : Map<String, dynamic>.from(json as Map);
      return DriveDoc.fromJson(doc);
    }
    if (status == 403) throw ApiException(403, _forbiddenMessage(body));
    if (status == 422) throw _parseValidationError(body);
    throw ApiException(status, _serverErrorMessage(body, 'upload document'));
  }

  /// Re-tag / (un)link a document. Pass [unlinkProperty] true to send
  /// `property_id: null` (server unlinks from the property).
  Future<DriveDoc> updateContactDocument(int id, int docId,
      {int? documentTypeId,
      int? propertyId,
      bool unlinkProperty = false}) async {
    final payload = <String, dynamic>{
      if (documentTypeId != null) 'document_type_id': documentTypeId,
      if (unlinkProperty)
        'property_id': null
      else if (propertyId != null)
        'property_id': propertyId,
    };
    final response = await http
        .put(Uri.parse('$baseUrl/mobile/contacts/$id/drive/$docId'),
            headers: await _headers(), body: jsonEncode(payload))
        .timeout(_timeout);
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final doc = json is Map && json['document'] is Map
          ? Map<String, dynamic>.from(json['document'])
          : Map<String, dynamic>.from(json as Map);
      return DriveDoc.fromJson(doc);
    }
    if (response.statusCode == 403) {
      throw ApiException(403, _forbiddenMessage(response.body));
    }
    if (response.statusCode == 422) throw _parseValidationError(response.body);
    throw ApiException(response.statusCode,
        _serverErrorMessage(response.body, 'update document'));
  }

  /// Downloads a document, returning its bytes + a best-effort filename.
  Future<DownloadedFile> downloadContactDocument(
      int id, int docId, String fallbackName) async {
    final response = await http
        .get(Uri.parse('$baseUrl/mobile/contacts/$id/drive/$docId/download'),
            headers: await _headers())
        .timeout(_timeout);
    if (response.statusCode == 200) {
      var name = fallbackName;
      final cd = response.headers['content-disposition'];
      if (cd != null) {
        final m = RegExp(r'filename\*?=(?:UTF-8'
                "''"
                r')?\"?([^\";]+)\"?')
            .firstMatch(cd);
        if (m != null) name = Uri.decodeComponent(m.group(1)!.trim());
      }
      return DownloadedFile(
        bytes: response.bodyBytes,
        fileName: name,
        mimeType: response.headers['content-type'],
      );
    }
    if (response.statusCode == 403) {
      throw ApiException(403, _forbiddenMessage(response.body));
    }
    throw ApiException(response.statusCode, 'Failed to download document');
  }

  Future<void> deleteContactDocument(int id, int docId) async {
    final response = await http
        .delete(Uri.parse('$baseUrl/mobile/contacts/$id/drive/$docId'),
            headers: await _headers())
        .timeout(_timeout);
    if (response.statusCode == 200 || response.statusCode == 204) return;
    if (response.statusCode == 403) {
      throw ApiException(403, _forbiddenMessage(response.body));
    }
    throw ApiException(response.statusCode,
        _serverErrorMessage(response.body, 'delete document'));
  }

  Future<ContactFicaData> getContactFica(int id) async {
    final response = await http
        .get(Uri.parse('$baseUrl/mobile/contacts/$id/fica'),
            headers: await _headers())
        .timeout(_timeout);
    if (response.statusCode == 200) {
      return ContactFicaData.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body) as Map));
    }
    if (response.statusCode == 403) {
      throw ApiException(403, _forbiddenMessage(response.body));
    }
    throw ApiException(response.statusCode, 'Failed to load FICA');
  }

  Future<List<ContactType>> getContactOptions() async {
    final response = await http.get(
      Uri.parse('$baseUrl/mobile/contacts/options'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final list = body is Map ? (body['contact_types'] as List? ?? []) : [];
      return list
          .whereType<Map>()
          .map((e) => ContactType.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    throw ApiException(response.statusCode, 'Failed to load contact options');
  }

  Future<Contact> createContact(Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('$baseUrl/mobile/contacts'),
      headers: await _headers(),
      body: jsonEncode(body),
    ).timeout(_timeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final json = jsonDecode(response.body);
      final map = json is Map && json['contact'] is Map
          ? Map<String, dynamic>.from(json['contact'])
          : Map<String, dynamic>.from(json as Map);
      return Contact.fromJson(map);
    }
    if (response.statusCode == 422) {
      try {
        final json = jsonDecode(response.body);
        if (json is Map && json['duplicate_id'] != null) {
          final dup = json['duplicate_id'];
          final dupId = dup is num ? dup.toInt() : int.tryParse(dup.toString()) ?? 0;
          throw DuplicateContactException(dupId, json['message']?.toString() ?? 'This contact already exists');
        }
      } catch (e) {
        if (e is DuplicateContactException) rethrow;
      }
      throw _parseValidationError(response.body);
    }
    throw ApiException(response.statusCode, _serverErrorMessage(response.body, 'create'));
  }

  Future<Contact> updateContact(int id, Map<String, dynamic> body) async {
    final response = await http.put(
      Uri.parse('$baseUrl/mobile/contacts/$id'),
      headers: await _headers(),
      body: jsonEncode(body),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final map = json is Map && json['contact'] is Map
          ? Map<String, dynamic>.from(json['contact'])
          : Map<String, dynamic>.from(json as Map);
      return Contact.fromJson(map);
    }
    if (response.statusCode == 422) throw _parseValidationError(response.body);
    throw ApiException(response.statusCode, _serverErrorMessage(response.body, 'update'));
  }

  Future<Map<String, dynamic>> whatsappContact(int id) async {
    final response = await http.post(
      Uri.parse('$baseUrl/mobile/contacts/$id/whatsapp'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final body = jsonDecode(response.body);
      return body is Map<String, dynamic> ? body : <String, dynamic>{};
    }
    throw ApiException(response.statusCode, 'Failed to log WhatsApp');
  }

  Future<ContactMatch> createMatch(int contactId, Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('$baseUrl/mobile/contacts/$contactId/matches'),
      headers: await _headers(),
      body: jsonEncode(body),
    ).timeout(_timeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final json = jsonDecode(response.body);
      final map = json is Map && json['match'] is Map
          ? Map<String, dynamic>.from(json['match'])
          : Map<String, dynamic>.from(json as Map);
      return ContactMatch.fromJson(map);
    }
    if (response.statusCode == 422) throw _parseValidationError(response.body);
    throw ApiException(response.statusCode, _serverErrorMessage(response.body, 'create match'));
  }

  Future<Property> createPropertyForContact(
      int contactId, String role, Map<String, dynamic> propertyBody) async {
    final merged = {
      ...propertyBody,
      'link_contact_id': contactId,
      'link_contact_role': role,
    };
    return createProperty(merged);
  }

  // --- Core Matches ---

  Future<List<CoreMatchGroup>> listCoreMatches() async {
    final response = await http.get(
      Uri.parse('$baseUrl/mobile/core-matches'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final list = body is Map ? (body['groups'] as List? ?? const []) : const [];
      return list
          .whereType<Map>()
          .map((e) => CoreMatchGroup.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    throw ApiException(response.statusCode, 'Failed to load core matches');
  }

  Future<CoreMatchDetail> getCoreMatch(int id,
      {bool showOtherAgents = false}) async {
    final uri = Uri.parse('$baseUrl/mobile/core-matches/$id').replace(
      queryParameters: showOtherAgents ? {'show_other_agents': '1'} : null,
    );
    final response =
        await http.get(uri, headers: await _headers()).timeout(_timeout);

    if (response.statusCode == 200) {
      return CoreMatchDetail.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body)));
    }
    throw ApiException(response.statusCode, 'Failed to load core match');
  }

  Future<bool> getCoreMatchAllowCrossAgent() async {
    final response = await http.get(
      Uri.parse('$baseUrl/mobile/core-matches/settings'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      return body is Map && body['allow_cross_agent'] == true;
    }
    throw ApiException(response.statusCode, 'Failed to load core match settings');
  }

  Future<CoreMatch> updateCoreMatch(int id, Map<String, dynamic> body) async {
    final response = await http.put(
      Uri.parse('$baseUrl/mobile/core-matches/$id'),
      headers: await _headers(),
      body: jsonEncode(body),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final map = json is Map && json['match'] is Map
          ? Map<String, dynamic>.from(json['match'])
          : Map<String, dynamic>.from(json as Map);
      return CoreMatch.fromJson(map);
    }
    if (response.statusCode == 422) throw _parseValidationError(response.body);
    throw ApiException(response.statusCode, _serverErrorMessage(response.body, 'update match'));
  }

  Future<void> setCoreMatchStatus(int id, String status) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/mobile/core-matches/$id/status'),
      headers: await _headers(),
      body: jsonEncode({'status': status}),
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Failed to update status');
    }
  }

  /// Toggles a property's visibility within a Core Match.
  ///
  /// When hiding (property currently visible) the server requires a [reason]
  /// of 3–500 characters, sent as the request body. When un-hiding, pass a
  /// null/empty [reason] and no body is sent — the stored reason is cleared.
  ///
  /// Throws [ValidationException] on a 422 (e.g. a missing/too-short reason).
  Future<HidePropertyResult> toggleHideMatchProperty(
      int matchId, int propertyId,
      {String? reason}) async {
    final hasReason = reason != null && reason.trim().isNotEmpty;
    final response = await http.post(
      Uri.parse('$baseUrl/mobile/core-matches/$matchId/hide/$propertyId'),
      headers: await _headers(),
      body: hasReason ? jsonEncode({'reason': reason.trim()}) : null,
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body is Map) {
        return HidePropertyResult(
          hidden: body['hidden'] == true,
          hiddenReason: body['hidden_reason']?.toString(),
        );
      }
      return const HidePropertyResult(hidden: false);
    }
    if (response.statusCode == 422) throw _parseValidationError(response.body);
    throw ApiException(response.statusCode, 'Failed to toggle visibility');
  }

  Future<WhatsAppShare> previewMatchWhatsApp(int matchId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/mobile/core-matches/$matchId/share-whatsapp'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      return WhatsAppShare.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body)));
    }
    throw ApiException(response.statusCode, 'Failed to load WhatsApp preview');
  }

  Future<WhatsAppShare> sendMatchWhatsApp(int matchId, String message) async {
    final response = await http.post(
      Uri.parse('$baseUrl/mobile/core-matches/$matchId/share-whatsapp'),
      headers: await _headers(),
      body: jsonEncode({'message': message}),
    ).timeout(_timeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return WhatsAppShare.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body)));
    }
    throw ApiException(response.statusCode, 'Failed to send WhatsApp');
  }

  Future<void> deleteCoreMatch(int id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/mobile/core-matches/$id'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw ApiException(response.statusCode, 'Failed to delete match');
    }
  }

  // --- Notifications ---

  /// Register an FCM/APNs token with the backend so the user receives push.
  Future<void> registerDeviceToken({
    required String platform,
    required String token,
    String? appVersion,
  }) async {
    if (useMockData) return;
    final response = await http.post(
      Uri.parse('$baseUrl/v1/device-tokens'),
      headers: await _headers(),
      body: jsonEncode({
        'platform': platform,
        'token': token,
        if (appVersion != null) 'app_version': appVersion,
      }),
    ).timeout(_timeout);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ApiException(response.statusCode, 'Failed to register device token');
    }
  }

  Future<void> revokeDeviceToken(String token) async {
    if (useMockData) return;
    final response = await http.delete(
      Uri.parse('$baseUrl/v1/device-tokens/${Uri.encodeComponent(token)}'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw ApiException(response.statusCode, 'Failed to revoke device token');
    }
  }

  Future<({List<NotificationItem> items, int unread})> getNotifications({
    bool unreadOnly = false,
    int limit = 20,
    int? beforeId,
  }) async {
    if (useMockData) return (items: <NotificationItem>[], unread: 0);

    final qp = <String, String>{
      if (unreadOnly) 'unread': '1',
      'limit': '$limit',
      if (beforeId != null) 'before_id': '$beforeId',
    };
    final uri = Uri.parse('$baseUrl/notifications').replace(queryParameters: qp);
    final response = await http.get(uri, headers: await _headers()).timeout(_timeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body is! Map) {
        throw ApiException(response.statusCode, 'Failed to load notifications');
      }
      final list = (body['items'] as List? ?? [])
          .whereType<Map>()
          .map((e) => NotificationItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final unread = body['unread'] is num ? (body['unread'] as num).toInt() : 0;
      return (items: list, unread: unread);
    }
    await _handleUnauthorized(response.statusCode);
    throw ApiException(response.statusCode, 'Failed to load notifications');
  }

  Future<void> markNotificationRead(String id) async {
    if (useMockData) return;
    final response = await http.post(
      Uri.parse('$baseUrl/notifications/$id/read'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Failed to mark read');
    }
  }

  Future<void> markAllNotificationsRead() async {
    if (useMockData) return;
    final response = await http.post(
      Uri.parse('$baseUrl/notifications/mark-all-read'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Failed to mark all read');
    }
  }

  Future<OverdueSnapshot> getOverdueSnapshot() async {
    if (useMockData) return OverdueSnapshot.empty();
    final response = await http.get(
      Uri.parse('$baseUrl/notifications/overdue'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      return OverdueSnapshot.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body)));
    }
    throw ApiException(response.statusCode, 'Failed to load overdue snapshot');
  }

  Future<NotificationPreferencesData> getNotificationPreferences() async {
    final response = await http.get(
      Uri.parse('$baseUrl/v1/notification-preferences'),
      headers: await _headers(),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      return NotificationPreferencesData.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body)));
    }
    throw ApiException(response.statusCode, 'Failed to load notification preferences');
  }

  /// Returns saved count on success. Throws [AgencyControlledException] when
  /// the server returns 409 with `{ error: "agency_controlled" }`.
  ///
  /// When [lockedPushOnly] is true (agency-locked screen), only `master.push`
  /// is sent — every other field is suppressed to keep the wire clean.
  Future<int> updateNotificationPreferences({
    MasterChannels? master,
    OpenHours? openHours,
    int? cooldownMinutes,
    List<NotificationPreference> preferences = const [],
    bool lockedPushOnly = false,
  }) async {
    final Map<String, dynamic> payload;
    if (lockedPushOnly) {
      payload = {
        if (master != null) 'master': {'push': master.push},
      };
    } else {
      payload = {
        if (master != null) 'master': master.toJson(),
        if (openHours != null) 'open_hours': openHours.toJson(),
        if (cooldownMinutes != null) 'cooldown_minutes': cooldownMinutes,
        if (preferences.isNotEmpty)
          'preferences': preferences.map((p) => p.toJson()).toList(),
      };
    }

    final response = await http.put(
      Uri.parse('$baseUrl/v1/notification-preferences'),
      headers: await _headers(),
      body: jsonEncode(payload),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body is Map && body['saved'] is num) {
        return (body['saved'] as num).toInt();
      }
      return preferences.length;
    }
    if (response.statusCode == 409) {
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['error'] == 'agency_controlled') {
          throw AgencyControlledException();
        }
      } catch (e) {
        if (e is AgencyControlledException) rethrow;
      }
      throw AgencyControlledException();
    }
    throw ApiException(response.statusCode, 'Failed to save preferences');
  }

  // --- Mock Data ---


  List<CommandTask> _mockTasks() {
    final now = DateTime.now();
    return [
      CommandTask(id: 1, title: 'Call attorney re: transfer', taskType: 'follow_up', priority: 'high',
          status: 'todo', dueDate: now.add(const Duration(days: 1)), propertyAddress: '12 Marine Drive, Amanzimtoti'),
      CommandTask(id: 2, title: 'Upload FICA documents', taskType: 'document_upload', priority: 'critical',
          status: 'in_progress', dueDate: now.subtract(const Duration(days: 1)), propertyAddress: '45 Beach Road, Umkomaas'),
      CommandTask(id: 3, title: 'Follow up with seller', taskType: 'follow_up', priority: 'normal',
          status: 'todo', dueDate: now.add(const Duration(days: 3))),
      CommandTask(id: 4, title: 'Schedule property photos', taskType: 'custom', priority: 'low',
          status: 'awaiting', dueDate: now.add(const Duration(days: 5)), propertyAddress: '8 Ocean View, Warner Beach'),
      CommandTask(id: 5, title: 'Review offer to purchase', taskType: 'deal_action', priority: 'critical',
          status: 'todo', dueDate: now, propertyAddress: '23 Kingsway, Scottburgh'),
    ];
  }

  List<CalendarEvent> _mockEvents() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [
      CalendarEvent(id: 1, title: 'Property viewing - Marine Drive', eventType: 'deal',
          eventDate: today.add(const Duration(hours: 10)), colour: '#3b82f6',
          propertyAddress: '12 Marine Drive, Amanzimtoti', propertyId: 1),
      CalendarEvent(id: 2, title: 'Lease signing', eventType: 'lease',
          eventDate: today.add(const Duration(hours: 14)), colour: '#10b981',
          propertyAddress: '45 Beach Road, Umkomaas', propertyId: 2),
      CalendarEvent(id: 3, title: 'Compliance check', eventType: 'compliance',
          eventDate: today.add(const Duration(hours: 16)), colour: '#f59e0b'),
      CalendarEvent(id: 4, title: 'Open house', eventType: 'prospecting',
          eventDate: today.add(const Duration(days: 2, hours: 9)), colour: '#06b6d4',
          propertyAddress: '8 Ocean View, Warner Beach', propertyId: 3),
      CalendarEvent(id: 5, title: 'Meet with bond originator', eventType: 'deal',
          eventDate: today.add(const Duration(days: 3, hours: 11)), colour: '#3b82f6'),
    ];
  }

  // --- Portal Leads ---

  Future<({String date, int total, int page, int pages, List<PortalLead> leads})>
      getPortalLeads({String? date, String? portal, int page = 1, int perPage = 25}) async {
    final qp = <String, String>{
      if (date != null) 'date': date,
      if (portal != null) 'portal': portal,
      'page': '$page',
      'per_page': '$perPage',
    };
    final uri =
        Uri.parse('$baseUrl/v1/mobile/portal-leads').replace(queryParameters: qp);
    final response =
        await http.get(uri, headers: await _headers()).timeout(_timeout);
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body is! Map) {
        throw ApiException(response.statusCode, 'Failed to load portal leads');
      }
      final leads = (body['leads'] as List? ?? [])
          .whereType<Map>()
          .map((e) => PortalLead.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return (
        date: body['date']?.toString() ?? (date ?? ''),
        total: body['total'] is num ? (body['total'] as num).toInt() : leads.length,
        page: body['page'] is num ? (body['page'] as num).toInt() : page,
        pages: body['pages'] is num ? (body['pages'] as num).toInt() : 1,
        leads: leads,
      );
    }
    await _handleUnauthorized(response.statusCode);
    throw ApiException(response.statusCode, 'Failed to load portal leads');
  }

  Future<List<PortalLeadDate>> getPortalLeadDates() async {
    final response = await http
        .get(Uri.parse('$baseUrl/v1/mobile/portal-leads/dates'),
            headers: await _headers())
        .timeout(_timeout);
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body is! Map) {
        throw ApiException(response.statusCode, 'Failed to load portal lead dates');
      }
      return (body['dates'] as List? ?? [])
          .whereType<Map>()
          .map((e) => PortalLeadDate.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    await _handleUnauthorized(response.statusCode);
    throw ApiException(response.statusCode, 'Failed to load portal lead dates');
  }

  Future<PortalLead> getPortalLead(int id) async {
    final response = await http
        .get(Uri.parse('$baseUrl/v1/mobile/portal-leads/$id'),
            headers: await _headers())
        .timeout(_timeout);
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body is! Map) {
        throw ApiException(response.statusCode, 'Failed to load portal lead');
      }
      final lead = (body['lead'] is Map)
          ? Map<String, dynamic>.from(body['lead'] as Map)
          : Map<String, dynamic>.from(body);
      return PortalLead.fromJson(lead);
    }
    await _handleUnauthorized(response.statusCode);
    throw ApiException(response.statusCode, 'Failed to load portal lead');
  }

  Future<void> markPortalLeadRead(int id) async {
    final response = await http
        .post(Uri.parse('$baseUrl/v1/mobile/portal-leads/$id/mark-read'),
            headers: await _headers())
        .timeout(_timeout);
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw ApiException(response.statusCode, 'Failed to mark portal lead read');
    }
  }
}

/// In-memory result of a streamed document download. Kept in memory because
/// the app has no `path_provider`; callers hand [bytes] to `share_plus`
/// (`XFile.fromData`) or `gal` so the user can save/open it.
class DownloadedFile {
  final Uint8List bytes;
  final String fileName;
  final String? mimeType;
  const DownloadedFile({
    required this.bytes,
    required this.fileName,
    this.mimeType,
  });
}

/// Outcome of [ApiService.toggleHideMatchProperty]: the new visibility state
/// and, when hidden, the agent-supplied reason.
class HidePropertyResult {
  final bool hidden;
  final String? hiddenReason;
  const HidePropertyResult({required this.hidden, this.hiddenReason});
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Thrown by [ApiService.uploadPropertyImage] when the server rejects a
/// [roomTag] because it isn't on the property's live tag list. The caller
/// should use [availableTags] to refresh its local picker and re-prompt.
class TagValidationException extends ApiException {
  final List<String> availableTags;
  TagValidationException(String message, this.availableTags)
      : super(422, message);
}

/// Thrown by create / update endpoints when the server returns a Laravel-
/// shaped 422 validation error. [fieldErrors] maps field name → first error
/// message, ready to surface inline in the form.
class ValidationException extends ApiException {
  final Map<String, String> fieldErrors;
  ValidationException(String message, this.fieldErrors) : super(422, message);
}

/// Server returned 409 + `{ error: "agency_controlled" }` from the
/// notification-preferences PUT — agency admin owns these settings, the UI
/// must freeze the form and surface the banner.
class AgencyControlledException extends ApiException {
  AgencyControlledException()
      : super(409, 'Your agency manages notification settings centrally.');
}

/// Thrown by [ApiService.sendToMarket] on a 422 `marketing_blocked`
/// response. Carries the human-readable [blockedBy] reasons and a freshly
/// parsed [report] so the caller can re-render the compliance gates.
class MarketingBlockedException extends ApiException {
  final List<String> blockedBy;
  final PropertyCompliance report;
  MarketingBlockedException(String message, this.blockedBy, this.report)
      : super(422, message);
}

/// Server returned 422 with `duplicate_id` from POST /mobile/contacts —
/// caller should offer to open the existing contact instead of erroring.
class DuplicateContactException extends ApiException {
  final int duplicateId;
  DuplicateContactException(this.duplicateId, String message) : super(422, message);
}

/// Thrown by the rental-inspection endpoints on a 422 whose `code` is
/// `not_a_rental` or `not_live` — the property isn't eligible, so the caller
/// should hide the feature. This shouldn't happen when gating on
/// `rental_inspections_available`; it's a defensive backstop.
class RentalNotEligibleException extends ApiException {
  /// Either `not_a_rental` or `not_live`.
  final String code;
  RentalNotEligibleException(this.code, String message) : super(422, message);
}
