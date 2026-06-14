import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification_models.dart';
import '../services/api_service.dart';

class NotificationsProvider extends ChangeNotifier {
  static const _kPrefsCacheKey = 'notification_prefs_cache_v2';
  static const _kPrefsCacheStampKey = 'notification_prefs_cache_v2_at';
  static const Duration _prefsCacheTtl = Duration(minutes: 5);
  DateTime? _prefsFetchedAt;

  /// Whether the local user has push enabled (mirrors `master.push`). Used by
  /// [MessagingService] to belt-and-braces suppress foreground notifications
  /// when push is locally disabled.
  bool get localPushEnabled => _prefs?.master.push ?? true;

  /// Whether the user's open-hours schedule permits surfacing a notification
  /// right now. Used by [MessagingService] to suppress foreground delivery
  /// outside the configured window. Returns true when prefs aren't loaded yet
  /// (fail-open — better to show a notification than silently swallow one).
  bool get notificationsAllowedNow => _prefs?.openHours.allowsAt(DateTime.now()) ?? true;

  final ApiService _api = ApiService();

  // Feed
  final List<NotificationItem> _items = [];
  int _unread = 0;
  bool _loadingFeed = false;
  String? _feedError;

  // Overdue
  OverdueSnapshot _overdue = OverdueSnapshot.empty();
  bool _loadingOverdue = false;

  // Preferences
  NotificationPreferencesData? _prefs;
  bool _loadingPrefs = false;
  String? _prefsError;
  bool _saving = false;

  List<NotificationItem> get items => List.unmodifiable(_items);
  int get unread => _unread;
  bool get loadingFeed => _loadingFeed;
  String? get feedError => _feedError;

  OverdueSnapshot get overdue => _overdue;
  bool get loadingOverdue => _loadingOverdue;

  NotificationPreferencesData? get prefs => _prefs;
  bool get loadingPrefs => _loadingPrefs;
  String? get prefsError => _prefsError;
  bool get saving => _saving;

  Future<void> loadFeed({bool unreadOnly = false}) async {
    _loadingFeed = true;
    _feedError = null;
    notifyListeners();
    try {
      final res = await _api.getNotifications(unreadOnly: unreadOnly);
      _items
        ..clear()
        ..addAll(res.items);
      _unread = res.unread;
    } catch (e) {
      _feedError = e.toString();
    }
    _loadingFeed = false;
    notifyListeners();
  }

  Future<void> markRead(String id) async {
    final idx = _items.indexWhere((n) => n.id == id);
    if (idx == -1) return;
    final n = _items[idx];
    if (n.isRead) return;

    // Optimistic.
    _items[idx] = NotificationItem(
      id: n.id,
      type: n.type,
      eventKey: n.eventKey,
      pillar: n.pillar,
      title: n.title,
      body: n.body,
      severity: n.severity,
      createdAt: n.createdAt,
      subject: n.subject,
      actionUrl: n.actionUrl,
      readAt: DateTime.now(),
      data: n.data,
    );
    _unread = (_unread - 1).clamp(0, 1 << 30);
    notifyListeners();

    try {
      await _api.markNotificationRead(id);
    } catch (_) {
      // Best-effort. Next refresh will reconcile.
    }
  }

  Future<void> markAllRead() async {
    _unread = 0;
    final now = DateTime.now();
    for (var i = 0; i < _items.length; i++) {
      final n = _items[i];
      if (n.isRead) continue;
      _items[i] = NotificationItem(
        id: n.id,
        type: n.type,
        eventKey: n.eventKey,
        pillar: n.pillar,
        title: n.title,
        body: n.body,
        severity: n.severity,
        createdAt: n.createdAt,
        subject: n.subject,
        actionUrl: n.actionUrl,
        readAt: now,
        data: n.data,
      );
    }
    notifyListeners();

    try {
      await _api.markAllNotificationsRead();
    } catch (_) {}
  }

  Future<void> loadOverdue() async {
    _loadingOverdue = true;
    notifyListeners();
    try {
      _overdue = await _api.getOverdueSnapshot();
    } catch (e) {
      debugPrint('[notifications] overdue failed: $e');
    }
    _loadingOverdue = false;
    notifyListeners();
  }

  /// Loads cached prefs immediately (instant render), then revalidates from
  /// the server in the background.
  Future<void> loadPreferences({bool force = false}) async {
    _loadingPrefs = true;
    _prefsError = null;

    if (!force) {
      final cached = await _readCachedPrefs();
      if (cached != null) {
        _prefs = cached.data;
        _prefsFetchedAt = cached.fetchedAt;
      }
      // Cache is fresh enough — skip the network hop. Settings can change
      // agency-side, so we cap this at _prefsCacheTtl (5 min).
      final stamp = _prefsFetchedAt;
      if (stamp != null &&
          DateTime.now().difference(stamp) < _prefsCacheTtl &&
          _prefs != null) {
        _loadingPrefs = false;
        notifyListeners();
        return;
      }
    }
    notifyListeners();

    try {
      final fresh = await _api.getNotificationPreferences();
      _prefs = fresh;
      _prefsFetchedAt = DateTime.now();
      await _writeCachedPrefs(fresh);
    } catch (e) {
      _prefsError = e.toString();
    }
    _loadingPrefs = false;
    notifyListeners();
  }

  /// Returns true on success. Caller should already have guarded against the
  /// `agency_controlled` case in the UI; we still throw here so a 409 race
  /// surfaces a banner instead of silently no-op'ing.
  Future<bool> savePreferences() async {
    final p = _prefs;
    if (p == null) return false;

    _saving = true;
    _prefsError = null;
    notifyListeners();

    try {
      if (p.locked) {
        // Locked: server ignores anything but master.push — keep the wire clean.
        await _api.updateNotificationPreferences(
          master: p.master,
          lockedPushOnly: true,
        );
      } else {
        final flat = p.groups.expand((g) => g.items).toList();
        await _api.updateNotificationPreferences(
          master: p.master,
          openHours: p.openHours,
          cooldownMinutes: p.cooldownMinutes,
          preferences: flat,
        );
      }
      await _writeCachedPrefs(p);
      _saving = false;
      notifyListeners();
      return true;
    } on AgencyControlledException {
      // Server flipped to agency-controlled since the form loaded.
      _prefs = NotificationPreferencesData(
        mode: 'agency',
        locked: true,
        master: p.master,
        openHours: p.openHours,
        cooldownMinutes: p.cooldownMinutes,
        groups: p.groups,
      );
      _saving = false;
      notifyListeners();
      return false;
    } catch (e) {
      _prefsError = e.toString();
      _saving = false;
      notifyListeners();
      return false;
    }
  }

  Future<({NotificationPreferencesData data, DateTime fetchedAt})?>
      _readCachedPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefsCacheKey);
      if (raw == null) return null;
      final data = NotificationPreferencesData.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw)));
      final stamp = prefs.getInt(_kPrefsCacheStampKey);
      final fetchedAt = stamp != null
          ? DateTime.fromMillisecondsSinceEpoch(stamp)
          : DateTime.fromMillisecondsSinceEpoch(0);
      return (data: data, fetchedAt: fetchedAt);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCachedPrefs(NotificationPreferencesData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefsCacheKey, jsonEncode(data.toJson()));
      await prefs.setInt(
          _kPrefsCacheStampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Called when the auth provider logs out — clear in-memory state.
  void reset() {
    _items.clear();
    _unread = 0;
    _overdue = OverdueSnapshot.empty();
    _prefs = null;
    notifyListeners();
  }
}
