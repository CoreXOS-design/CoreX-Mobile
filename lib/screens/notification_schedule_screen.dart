import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/ui/content_width.dart';
import '../models/notification_models.dart';
import '../providers/notifications_provider.dart';
import '../theme.dart';

/// Account-level "quiet hours" schedule with a per-weekday window. When
/// enabled, notifications are only delivered inside each day's window (a day
/// switched off is fully quiet); outside it both in-app banners and push are
/// suppressed.
///
/// The schedule is part of the synced notification preferences (`open_hours`),
/// so saving here PUTs the same payload the notifications screen uses. On-device
/// enforcement covers in-app + foreground push; closed-app system pushes rely
/// on the server honouring the same windows.
class NotificationScheduleScreen extends StatefulWidget {
  const NotificationScheduleScreen({super.key});

  @override
  State<NotificationScheduleScreen> createState() =>
      _NotificationScheduleScreenState();
}

class _NotificationScheduleScreenState
    extends State<NotificationScheduleScreen> {
  static const _dayNames = [
    '',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationsProvider>().loadPreferences();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<NotificationsProvider>();
    final data = p.prefs;
    final locked = data?.locked ?? false;
    final oh = data?.openHours;

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: const Text('Quiet hours'),
        actions: [
          if (data != null && !locked)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextButton(
                onPressed: p.saving ? null : () => _save(context),
                child: p.saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
      body: ContentSafeArea(
        top: false,
        child: oh == null
            ? Center(
                child: p.prefsError != null
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(p.prefsError!,
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: AppTheme.textMuted(context))),
                      )
                    : const CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  if (locked) _lockedBanner(context),
                  _enableCard(context, oh, locked),
                  if (oh.enabled) ...[
                    const SizedBox(height: 12),
                    _copyToAllRow(context, oh, locked),
                    const SizedBox(height: 8),
                    for (var d = 1; d <= 7; d++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _dayCard(context, d, oh.days[d]!, locked),
                      ),
                  ],
                ],
              ),
      ),
    );
  }

  // --- cards ---------------------------------------------------------------

  Widget _enableCard(BuildContext context, OpenHours oh, bool locked) {
    return _card(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: _label(context, 'Only notify me during set hours')),
              Switch(
                value: oh.enabled,
                onChanged:
                    locked ? null : (v) => setState(() => oh.enabled = v),
                activeTrackColor: AppTheme.brand,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            oh.enabled
                ? 'Set a window for each day. Outside a day\'s window — or on a '
                    'day you switch off — both in-app and push notifications are '
                    'silenced.'
                : 'Turn on to choose, per day, when you receive notifications.',
            style: TextStyle(
                fontSize: 11.5, color: AppTheme.textSecondary(context)),
          ),
        ],
      ),
    );
  }

  Widget _dayCard(
      BuildContext context, int day, DayWindow dw, bool locked) {
    return _card(
      context,
      Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _dayNames[day],
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: dw.enabled
                        ? AppTheme.textPrimary(context)
                        : AppTheme.textMuted(context),
                  ),
                ),
              ),
              if (!dw.enabled)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('Off',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted(context))),
                ),
              Switch(
                value: dw.enabled,
                onChanged:
                    locked ? null : (v) => setState(() => dw.enabled = v),
                activeTrackColor: AppTheme.brand,
              ),
            ],
          ),
          if (dw.enabled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _timeField(context, 'Start', dw.start, locked,
                      (t) => setState(() => dw.start = t)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _timeField(context, 'End', dw.end, locked,
                      (t) => setState(() => dw.end = t)),
                ),
              ],
            ),
            if (_wraps(dw)) ...[
              const SizedBox(height: 6),
              Text('Crosses midnight (ends ${dw.end} next day).',
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary(context))),
            ],
          ],
        ],
      ),
    );
  }

  /// "Apply Monday's window to every active day" — quick way to fill a uniform
  /// weekday schedule before tweaking the exceptions (e.g. Saturday).
  Widget _copyToAllRow(BuildContext context, OpenHours oh, bool locked) {
    if (locked) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        icon: const Icon(Icons.content_copy_rounded, size: 15),
        label: const Text('Copy Monday to all days',
            style: TextStyle(fontSize: 12)),
        onPressed: () {
          final mon = oh.days[1]!;
          setState(() {
            for (var d = 2; d <= 7; d++) {
              oh.days[d]!
                ..start = mon.start
                ..end = mon.end;
            }
          });
        },
      ),
    );
  }

  bool _wraps(DayWindow dw) {
    final s = _minutes(dw.start);
    final e = _minutes(dw.end);
    return s != null && e != null && s > e;
  }

  int? _minutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  // --- widgets -------------------------------------------------------------

  Widget _timeField(BuildContext context, String label, String value,
      bool locked, ValueChanged<String> onPick) {
    return InkWell(
      onTap: locked
          ? null
          : () async {
              final parts = value.split(':');
              final initial = TimeOfDay(
                hour: int.tryParse(parts.elementAt(0)) ?? 9,
                minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
              );
              final picked =
                  await showTimePicker(context: context, initialTime: initial);
              if (picked != null) {
                final hh = picked.hour.toString().padLeft(2, '0');
                final mm = picked.minute.toString().padLeft(2, '0');
                onPick('$hh:$mm');
              }
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface2(context),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule,
                size: 16, color: AppTheme.textSecondary(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textSecondary(context))),
                  Text(value,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary(context))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, Widget child) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: child,
    );
  }

  Widget _label(BuildContext context, String text) => Text(text,
      style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary(context)));

  Widget _lockedBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFf59e0b).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border:
            Border.all(color: const Color(0xFFf59e0b).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 18, color: Color(0xFFf59e0b)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your agency manages your notification schedule.',
              style:
                  TextStyle(fontSize: 12, color: AppTheme.textPrimary(context)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    final ok = await context.read<NotificationsProvider>().savePreferences();
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Quiet hours saved')),
      );
    } else {
      final p = context.read<NotificationsProvider>();
      messenger.showSnackBar(SnackBar(
        content: Text(p.prefsError ?? 'Failed to save'),
        backgroundColor: const Color(0xFFef4444),
      ));
    }
  }
}
