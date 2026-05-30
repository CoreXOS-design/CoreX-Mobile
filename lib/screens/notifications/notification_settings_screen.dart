import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/notification_models.dart';
import '../../providers/notifications_provider.dart';
import '../../services/messaging_service.dart';
import '../../theme.dart';

/// Dynamic notification preferences screen rendered from
/// `GET /api/v1/notification-preferences`. Nothing on this screen is
/// hard-coded — sections, pillars, event types, threshold units and bounds
/// all come from the server payload.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
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

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (data != null)
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
      body: data == null
          ? Center(
              child: p.prefsError != null
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(p.prefsError!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textMuted(context))),
                    )
                  : const CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                if (locked) _agencyBanner(context),
                _testButton(context),
                const SizedBox(height: 12),
                _MasterSwitches(
                  master: data.master,
                  locked: locked,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 12),
                _OpenHoursCard(
                  openHours: data.openHours,
                  locked: locked,
                  onChanged: () => setState(() {}),
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
        const SnackBar(content: Text('Notification preferences saved')),
      );
    } else {
      final p = context.read<NotificationsProvider>();
      messenger.showSnackBar(
        SnackBar(
          content: Text(p.prefsError ?? 'Failed to save'),
          backgroundColor: const Color(0xFFef4444),
        ),
      );
    }
  }

  Widget _testButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.notifications_active_outlined, size: 18),
        label: const Text('Send test notification'),
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            await MessagingService.instance.sendTestNotification();
            messenger.showSnackBar(const SnackBar(
              content: Text(
                  'Test notification sent — check your notification bar.'),
            ));
          } catch (e) {
            messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
          }
        },
      ),
    );
  }

  Widget _agencyBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFf59e0b).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
            color: const Color(0xFFf59e0b).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 18, color: Color(0xFFf59e0b)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your agency has locked these settings. You can still control '
              'mobile push for your own device.',
              style: TextStyle(
                  fontSize: 12, color: AppTheme.textPrimary(context)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
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
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary(context)));
  }
}

// ---------------------------------------------------------------------------

class _MasterSwitches extends StatelessWidget {
  final MasterChannels master;
  final bool locked;
  final VoidCallback onChanged;

  const _MasterSwitches(
      {required this.master, required this.locked, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // Push remains editable even when locked — it's a per-device control.
    return _Card(
      child: Column(
        children: [
          const _SectionLabel('Channels'),
          const SizedBox(height: 8),
          _row(context, 'In-app', master.inApp, locked, (v) {
            master.inApp = v;
            onChanged();
          }),
          _divider(context),
          _row(context, 'Email', master.email, locked, (v) {
            master.email = v;
            onChanged();
          }),
          _divider(context),
          _row(context, 'Push (this device)', master.push, false, (v) {
            master.push = v;
            onChanged();
          }),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, bool value, bool disabled,
      ValueChanged<bool> onTap) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary(context))),
        ),
        Switch(
          value: value,
          onChanged: disabled ? null : onTap,
          activeTrackColor: AppTheme.brand,
        ),
      ],
    );
  }

  Widget _divider(BuildContext context) =>
      Divider(height: 1, color: AppTheme.borderColor(context));
}

// ---------------------------------------------------------------------------

class _OpenHoursCard extends StatelessWidget {
  final OpenHours openHours;
  final bool locked;
  final VoidCallback onChanged;

  const _OpenHoursCard(
      {required this.openHours,
      required this.locked,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _SectionLabel('Open hours')),
              Switch(
                value: openHours.enabled,
                onChanged: locked
                    ? null
                    : (v) {
                        openHours.enabled = v;
                        onChanged();
                      },
                activeTrackColor: AppTheme.brand,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Outside this window, email notifications are suppressed. '
            'Push and in-app still arrive.',
            style: TextStyle(
                fontSize: 11, color: AppTheme.textSecondary(context)),
          ),
          if (openHours.enabled) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _timeField(context, 'Start', openHours.start, (t) {
                    openHours.start = t;
                    onChanged();
                  }),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _timeField(context, 'End', openHours.end, (t) {
                    openHours.end = t;
                    onChanged();
                  }),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _timeField(BuildContext context, String label, String value,
      ValueChanged<String> onPick) {
    return InkWell(
      onTap: locked
          ? null
          : () async {
              final parts = value.split(':');
              final initial = TimeOfDay(
                hour: int.tryParse(parts.elementAt(0)) ?? 9,
                minute:
                    int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
              );
              final picked = await showTimePicker(
                context: context,
                initialTime: initial,
              );
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
            Icon(Icons.schedule, size: 16,
                color: AppTheme.textSecondary(context)),
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
}
