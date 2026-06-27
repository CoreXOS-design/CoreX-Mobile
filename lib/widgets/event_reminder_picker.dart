import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/notification_models.dart';
import '../theme.dart';

/// Shared pieces for the calendar event-reminder lead-time setting
/// (`agent.event_due`). The backend stores a single value —
/// [NotificationPreference.threshold] in *total minutes*. Hours + minutes in
/// the picker are purely a presentation convenience over that one number.

/// "1 hour 30 minutes before", "30 minutes before", "2 hours before".
String formatLeadTime(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final parts = <String>[];
  if (h > 0) parts.add('$h ${h == 1 ? 'hour' : 'hours'}');
  if (m > 0) parts.add('$m ${m == 1 ? 'minute' : 'minutes'}');
  if (parts.isEmpty) return '0 minutes before';
  return '${parts.join(' ')} before';
}

/// Returns the calendar event-reminder preference (`agent.event_due`),
/// synthesizing a default and injecting it into the payload when the backend
/// hasn't shipped it yet. The lead-time is a standing user preference — it must
/// be settable even with no appointments coming up — so callers can always rely
/// on a non-null pref. Injecting the synthetic item into the `agent` group
/// ensures it's included in the next save (PUT) and cached. Idempotent: once
/// present (synthetic or server-sent) it's returned as-is, never duplicated.
NotificationPreference ensureEventReminder(NotificationPreferencesData d) {
  for (final g in d.groups) {
    for (final it in g.items) {
      if (it.key == 'agent.event_due') return it;
    }
  }

  // Mirror the server's default item so this fallback (used only when the
  // backend omits the item) round-trips identically once persisted.
  final pref = NotificationPreference(
    key: 'agent.event_due',
    label: 'Calendar event reminder',
    description: 'Reminds you when a calendar event is approaching.',
    group: 'My activity',
    thresholdUnit: 'minutes',
    threshold: 60, // sensible default: 1 hour before
    thresholdMin: 5,
    thresholdMax: 10080, // 7 days
    enabled: true,
    channelInApp: true,
    channelEmail: true,
    channelPush: true,
    isAdapter: true,
  );

  PreferenceGroup? agentGroup;
  for (final g in d.groups) {
    if (g.pillar == 'agent') {
      agentGroup = g;
      break;
    }
  }
  if (agentGroup != null) {
    agentGroup.items.add(pref);
  } else {
    d.groups.add(PreferenceGroup(
      pillar: 'agent',
      label: 'Calendar',
      items: [pref],
    ));
  }
  return pref;
}

/// Two-wheel (hours + minutes) sheet. Minutes step by 5 to match the backend's
/// 5-minute precision floor. Done is disabled while the combined total falls
/// outside [min]..[max] (e.g. 0h 0m). Pops the chosen total minutes, or null on
/// dismiss.
class LeadTimePickerSheet extends StatefulWidget {
  final int initialMinutes;
  final int min;
  final int max;

  const LeadTimePickerSheet({
    super.key,
    required this.initialMinutes,
    required this.min,
    required this.max,
  });

  @override
  State<LeadTimePickerSheet> createState() => _LeadTimePickerSheetState();
}

class _LeadTimePickerSheetState extends State<LeadTimePickerSheet> {
  static const _maxHours = 168; // 7 days, matching the 10080-minute ceiling.
  static const _minuteStep = 5;

  late int _hours;
  late int _minuteIndex; // index into 0,5,10,…,55
  late final FixedExtentScrollController _hoursCtrl;
  late final FixedExtentScrollController _minutesCtrl;

  static const List<int> _minutes = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55];

  @override
  void initState() {
    super.initState();
    final init = widget.initialMinutes.clamp(0, _maxHours * 60 + 55);
    _hours = (init ~/ 60).clamp(0, _maxHours);
    _minuteIndex = ((init % 60) ~/ _minuteStep).clamp(0, _minutes.length - 1);
    _hoursCtrl = FixedExtentScrollController(initialItem: _hours);
    _minutesCtrl = FixedExtentScrollController(initialItem: _minuteIndex);
  }

  @override
  void dispose() {
    _hoursCtrl.dispose();
    _minutesCtrl.dispose();
    super.dispose();
  }

  int get _total => _hours * 60 + _minutes[_minuteIndex];
  bool get _valid => _total >= widget.min && _total <= widget.max;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Remind me before the event',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary(context))),
                ),
                TextButton(
                  onPressed: _valid ? () => Navigator.of(context).pop(_total) : null,
                  child: const Text('Done',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            Text(
              _valid
                  ? formatLeadTime(_total)
                  : 'Choose between ${formatLeadTime(widget.min)} and ${formatLeadTime(widget.max)}',
              style: TextStyle(
                  fontSize: 12.5,
                  color: _valid
                      ? AppTheme.textSecondary(context)
                      : const Color(0xFFef4444)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: Row(
                children: [
                  Expanded(child: _wheel(context, _hoursLabel, _maxHours + 1,
                      _hoursCtrl, (i) => setState(() => _hours = i))),
                  Expanded(child: _wheel(context, _minutesLabel, _minutes.length,
                      _minutesCtrl, (i) => setState(() => _minuteIndex = i))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _hoursLabel(int i) => '$i ${i == 1 ? 'hour' : 'hours'}';
  String _minutesLabel(int i) =>
      '${_minutes[i]} ${_minutes[i] == 1 ? 'min' : 'mins'}';

  Widget _wheel(BuildContext context, String Function(int) label, int count,
      FixedExtentScrollController ctrl, ValueChanged<int> onSelected) {
    return CupertinoPicker(
      scrollController: ctrl,
      itemExtent: 36,
      onSelectedItemChanged: onSelected,
      children: [
        for (var i = 0; i < count; i++)
          Center(
            child: Text(label(i),
                style: TextStyle(
                    fontSize: 16, color: AppTheme.textPrimary(context))),
          ),
      ],
    );
  }
}
