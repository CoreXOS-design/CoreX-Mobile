import 'package:flutter/material.dart';

/// One row in `GET /api/notifications`.
///
/// `id` is a Laravel notification UUID (string), not an int — the server uses
/// `Illuminate\Notifications\DatabaseNotification` which keys on UUID.
class NotificationItem {
  final String id;
  final String type;
  final String eventKey;
  final String pillar;
  final String title;
  final String body;
  final NotificationSubject? subject;
  final String? actionUrl;
  final String severity; // info | warning | overdue
  final DateTime? readAt;
  final DateTime createdAt;
  final Map<String, dynamic> data;

  NotificationItem({
    required this.id,
    required this.type,
    required this.eventKey,
    required this.pillar,
    required this.title,
    required this.body,
    required this.severity,
    required this.createdAt,
    this.subject,
    this.actionUrl,
    this.readAt,
    this.data = const {},
  });

  bool get isRead => readAt != null;

  factory NotificationItem.fromJson(Map<String, dynamic> j) => NotificationItem(
        id: j['id'].toString(),
        type: j['type']?.toString() ?? '',
        eventKey: j['event_key']?.toString() ?? '',
        pillar: j['pillar']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        body: j['body']?.toString() ?? '',
        subject: j['subject'] is Map
            ? NotificationSubject.fromJson(
                Map<String, dynamic>.from(j['subject']))
            : null,
        actionUrl: j['action_url']?.toString(),
        severity: j['severity']?.toString() ?? 'info',
        readAt: _parseDate(j['read_at']),
        createdAt: _parseDate(j['created_at']) ?? DateTime.now(),
        data: j['data'] is Map
            ? Map<String, dynamic>.from(j['data'])
            : <String, dynamic>{},
      );
}

class NotificationSubject {
  final String type;
  final dynamic id;
  final String? label;
  NotificationSubject({required this.type, required this.id, this.label});

  factory NotificationSubject.fromJson(Map<String, dynamic> j) =>
      NotificationSubject(
        type: j['type']?.toString() ?? '',
        id: j['id'],
        label: j['label']?.toString(),
      );
}

/// `GET /api/notifications/overdue`
class OverdueSnapshot {
  final OverdueCounts counts;
  final List<OverdueItem> items;

  OverdueSnapshot({required this.counts, required this.items});

  factory OverdueSnapshot.empty() =>
      OverdueSnapshot(counts: OverdueCounts.empty(), items: const []);

  factory OverdueSnapshot.fromJson(Map<String, dynamic> j) => OverdueSnapshot(
        counts: OverdueCounts.fromJson(
            Map<String, dynamic>.from(j['counts'] ?? {})),
        items: (j['items'] as List? ?? [])
            .whereType<Map>()
            .map((e) => OverdueItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class OverdueCounts {
  final int properties;
  final int contacts;
  final int deals;
  final int tasks;
  final int events;
  final int total;

  const OverdueCounts({
    required this.properties,
    required this.contacts,
    required this.deals,
    required this.tasks,
    required this.events,
    required this.total,
  });

  factory OverdueCounts.empty() => const OverdueCounts(
      properties: 0, contacts: 0, deals: 0, tasks: 0, events: 0, total: 0);

  factory OverdueCounts.fromJson(Map<String, dynamic> j) => OverdueCounts(
        properties: _int(j['properties']),
        contacts: _int(j['contacts']),
        deals: _int(j['deals']),
        tasks: _int(j['tasks']),
        events: _int(j['events']),
        total: _int(j['total']),
      );
}

class OverdueItem {
  final String eventKey;
  final String pillar;
  final NotificationSubject? subject;
  final double ageHours;
  final String severity;
  final String? actionUrl;
  final String title;
  final String body;
  final DateTime? thresholdHitAt;

  OverdueItem({
    required this.eventKey,
    required this.pillar,
    required this.severity,
    required this.title,
    required this.body,
    required this.ageHours,
    this.subject,
    this.actionUrl,
    this.thresholdHitAt,
  });

  factory OverdueItem.fromJson(Map<String, dynamic> j) => OverdueItem(
        eventKey: j['event_key']?.toString() ?? '',
        pillar: j['pillar']?.toString() ?? '',
        subject: j['subject'] is Map
            ? NotificationSubject.fromJson(
                Map<String, dynamic>.from(j['subject']))
            : null,
        ageHours: (j['age_hours'] is num)
            ? (j['age_hours'] as num).toDouble()
            : double.tryParse(j['age_hours']?.toString() ?? '') ?? 0,
        severity: j['severity']?.toString() ?? 'overdue',
        actionUrl: j['action_url']?.toString(),
        title: j['title']?.toString() ?? '',
        body: j['body']?.toString() ?? '',
        thresholdHitAt: _parseDate(j['threshold_hit_at']),
      );
}

/// `GET /api/v1/notification-preferences`
class NotificationPreferencesData {
  final String mode; // "user" | "agency"
  final bool locked;
  final MasterChannels master;
  final OpenHours openHours;
  int cooldownMinutes;
  final List<PreferenceGroup> groups;

  NotificationPreferencesData({
    required this.mode,
    required this.locked,
    required this.master,
    required this.openHours,
    required this.cooldownMinutes,
    required this.groups,
  });

  /// Back-compat alias used by older call sites.
  bool get agencyControlled => locked;

  factory NotificationPreferencesData.fromJson(Map<String, dynamic> j) =>
      NotificationPreferencesData(
        mode: j['mode']?.toString() ?? 'user',
        locked: j['locked'] == true || j['agency_controlled'] == true,
        master: MasterChannels.fromJson(
            Map<String, dynamic>.from(j['master'] ?? {})),
        openHours: OpenHours.fromJson(
            Map<String, dynamic>.from(j['open_hours'] ?? {})),
        cooldownMinutes: _intOrNull(j['cooldown_minutes']) ?? 360,
        groups: (j['groups'] as List? ?? [])
            .whereType<Map>()
            .map((e) => PreferenceGroup.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'locked': locked,
        'master': master.toJson(),
        'open_hours': openHours.toJson(),
        'cooldown_minutes': cooldownMinutes,
        'groups': groups.map((g) => g.toJson()).toList(),
      };
}

/// A single weekday's notification window. When [enabled] is false, the day is
/// fully quiet (no notifications). [start]/[end] are "HH:MM"; a window where
/// start > end wraps past midnight into the next day.
class DayWindow {
  bool enabled;
  String start; // "HH:MM"
  String end;   // "HH:MM"

  DayWindow({required this.enabled, required this.start, required this.end});

  factory DayWindow.fromJson(Map<String, dynamic> j) => DayWindow(
        enabled: j['enabled'] != false,
        start: j['start']?.toString() ?? '09:00',
        end: j['end']?.toString() ?? '17:00',
      );

  Map<String, dynamic> toJson() =>
      {'enabled': enabled, 'start': start, 'end': end};

  DayWindow copy() => DayWindow(enabled: enabled, start: start, end: end);
}

class OpenHours {
  bool enabled;

  /// Per-weekday windows keyed by ISO weekday: 1 = Monday … 7 = Sunday. Every
  /// key 1–7 is always present. A day whose [DayWindow.enabled] is false is
  /// fully quiet while [enabled] is true.
  final Map<int, DayWindow> days;

  OpenHours({required this.enabled, required this.days});

  factory OpenHours.fromJson(Map<String, dynamic> j) {
    final enabled = j['enabled'] == true;

    // New canonical form: a per-day map.
    final raw = j['day_windows'];
    if (raw is Map && raw.isNotEmpty) {
      final map = <int, DayWindow>{};
      raw.forEach((k, v) {
        final day = int.tryParse(k.toString());
        if (day != null && day >= 1 && day <= 7 && v is Map) {
          map[day] = DayWindow.fromJson(Map<String, dynamic>.from(v));
        }
      });
      return OpenHours(enabled: enabled, days: _fill(map));
    }

    // Legacy form: a single window + optional list of active days. Build a
    // uniform per-day map so older payloads keep working.
    final start = j['start']?.toString() ?? '09:00';
    final end = j['end']?.toString() ?? '17:00';
    final activeDays = _parseDays(j['days']);
    final map = <int, DayWindow>{
      for (var d = 1; d <= 7; d++)
        d: DayWindow(enabled: activeDays.contains(d), start: start, end: end),
    };
    return OpenHours(enabled: enabled, days: map);
  }

  /// Ensures keys 1–7 all exist, defaulting any gaps to a disabled 09:00–17:00.
  static Map<int, DayWindow> _fill(Map<int, DayWindow> partial) {
    return {
      for (var d = 1; d <= 7; d++)
        d: partial[d] ??
            DayWindow(enabled: false, start: '09:00', end: '17:00'),
    };
  }

  static Set<int> _parseDays(dynamic raw) {
    if (raw is List) {
      final out = raw
          .map((e) => int.tryParse(e.toString()))
          .whereType<int>()
          .where((d) => d >= 1 && d <= 7)
          .toSet();
      if (out.isNotEmpty) return out;
    }
    return const {1, 2, 3, 4, 5, 6, 7};
  }

  Map<String, dynamic> toJson() {
    final activeDays = days.entries
        .where((e) => e.value.enabled)
        .map((e) => e.key)
        .toList()
      ..sort();
    final ref = activeDays.isNotEmpty ? days[activeDays.first]! : days[1]!;
    return {
      'enabled': enabled,
      'day_windows': {
        for (final e in days.entries) e.key.toString(): e.value.toJson(),
      },
      // Legacy mirror so a backend that hasn't migrated to `day_windows` still
      // gets a sensible single-window approximation.
      'days': activeDays,
      'start': ref.start,
      'end': ref.end,
    };
  }

  OpenHours copy() => OpenHours(
        enabled: enabled,
        days: {for (final e in days.entries) e.key: e.value.copy()},
      );

  /// Whether notifications are permitted at [now]. Disabled → no restriction.
  /// Otherwise the moment must fall inside that weekday's window (which may
  /// wrap past midnight, in which case the early-morning tail belongs to the
  /// previous day's window).
  bool allowsAt(DateTime now) {
    if (!enabled) return true;
    final nowMin = now.hour * 60 + now.minute;

    final today = days[now.weekday];
    if (today != null && today.enabled) {
      final s = _toMinutes(today.start);
      final e = _toMinutes(today.end);
      if (s != null && e != null) {
        if (s == e) return true; // full-day window
        if (s < e) {
          if (nowMin >= s && nowMin < e) return true;
        } else if (nowMin >= s) {
          return true; // evening portion of an overnight window
        }
      }
    }

    // Early-morning tail of the previous day's overnight window.
    final prevDay = now.weekday == 1 ? 7 : now.weekday - 1;
    final prev = days[prevDay];
    if (prev != null && prev.enabled) {
      final s = _toMinutes(prev.start);
      final e = _toMinutes(prev.end);
      if (s != null && e != null && s > e && nowMin < e) return true;
    }

    return false;
  }

  static int? _toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  /// Short human summary for the settings row. Collapses to a shared label when
  /// every active day uses the same window, otherwise "Custom".
  String summary() {
    if (!enabled) return 'Off';
    final active = days.entries.where((e) => e.value.enabled).toList();
    if (active.isEmpty) return 'No days selected';
    final first = active.first.value;
    final uniform =
        active.every((e) => e.value.start == first.start && e.value.end == first.end);
    final label = _daysLabel(active.map((e) => e.key).toSet());
    return uniform ? '$label · ${first.start}–${first.end}' : '$label · Custom';
  }

  static String _daysLabel(Set<int> s) {
    if (s.length == 7) return 'Every day';
    if (s.length == 5 && s.containsAll(const [1, 2, 3, 4, 5])) return 'Weekdays';
    if (s.length == 2 && s.containsAll(const [6, 7])) return 'Weekends';
    const names = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final ordered = s.toList()..sort();
    return ordered.map((d) => names[d]).join(', ');
  }
}

class MasterChannels {
  bool inApp;
  bool email;
  bool push;

  MasterChannels({required this.inApp, required this.email, required this.push});

  factory MasterChannels.fromJson(Map<String, dynamic> j) => MasterChannels(
        inApp: j['in_app'] != false,
        email: j['email'] != false,
        push: j['push'] != false,
      );

  Map<String, dynamic> toJson() =>
      {'in_app': inApp, 'email': email, 'push': push};

  MasterChannels copy() =>
      MasterChannels(inApp: inApp, email: email, push: push);
}

class PreferenceGroup {
  final String pillar; // property | contact | deal | agent
  final String label;
  final List<NotificationPreference> items;

  PreferenceGroup(
      {required this.pillar, required this.label, required this.items});

  factory PreferenceGroup.fromJson(Map<String, dynamic> j) => PreferenceGroup(
        pillar: j['pillar']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        items: (j['items'] as List? ?? [])
            .whereType<Map>()
            .map((e) =>
                NotificationPreference.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'pillar': pillar,
        'label': label,
        'items': items.map((i) => i.toJson()).toList(),
      };
}

class NotificationPreference {
  final String key;
  final String label;
  final String description;
  final String group;
  final String thresholdUnit; // hours | days | none
  int? threshold;
  final int? thresholdMin;
  final int? thresholdMax;
  bool enabled;
  bool channelInApp;
  bool channelEmail;
  bool channelPush;
  final bool isAdapter;

  NotificationPreference({
    required this.key,
    required this.label,
    required this.description,
    required this.group,
    required this.thresholdUnit,
    required this.enabled,
    required this.channelInApp,
    required this.channelEmail,
    required this.channelPush,
    this.threshold,
    this.thresholdMin,
    this.thresholdMax,
    this.isAdapter = false,
  });

  factory NotificationPreference.fromJson(Map<String, dynamic> j) =>
      NotificationPreference(
        key: j['key']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        description: j['description']?.toString() ?? '',
        group: j['group']?.toString() ?? '',
        thresholdUnit: j['threshold_unit']?.toString() ?? 'none',
        threshold: _intOrNull(j['threshold']),
        thresholdMin: _intOrNull(j['threshold_min']),
        thresholdMax: _intOrNull(j['threshold_max']),
        enabled: j['enabled'] == true,
        channelInApp: j['channel_in_app'] == true,
        channelEmail: j['channel_email'] == true,
        channelPush: j['channel_push'] == true,
        isAdapter: j['is_adapter'] == true,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'enabled': enabled,
        if (thresholdUnit != 'none' && threshold != null) 'threshold': threshold,
        'channel_in_app': channelInApp,
        'channel_email': channelEmail,
        'channel_push': channelPush,
      };
}

Color severityColor(String severity) {
  switch (severity) {
    case 'overdue':
      return const Color(0xFFef4444);
    case 'warning':
      return const Color(0xFFf59e0b);
    default:
      return const Color(0xFF0EA5E9);
  }
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

int _int(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

int? _intOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}
