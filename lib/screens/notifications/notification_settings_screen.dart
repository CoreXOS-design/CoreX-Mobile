import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/notification_models.dart';
import '../../providers/notifications_provider.dart';
import '../../services/messaging_service.dart';
import '../../theme.dart';
import '../notification_schedule_screen.dart';

/// Dynamic notification preferences screen rendered from
/// `GET /api/v1/notification-preferences`. Nothing on this screen is
/// hard-coded â€” sections, pillars, event types, threshold units and bounds
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
      body: SafeArea(
        top: false,
        child: data == null
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
                const SizedBox(height: 8),
                _scheduleHint(context),
              ],
            ),
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    final provider = context.read<NotificationsProvider>();
    final pushOn = provider.prefs?.master.push ?? true;
    final ok = await provider.savePreferences();
    if (ok) {
      // Make the Push toggle real for *this device*: register or revoke the
      // FCM token so background pushes actually start/stop. The foreground
      // gate alone doesn't affect system-tray pushes.
      await MessagingService.instance.setPushEnabled(pushOn);
    }
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
                  'Test notification sent â€” check your notification bar.'),
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

  Widget _scheduleHint(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radius),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const NotificationScheduleScreen(),
      )),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(Icons.do_not_disturb_on_outlined,
                size: 16, color: AppTheme.textSecondary(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Quiet hours moved to Settings â€” set the days and times you '
                'receive notifications.',
                style: TextStyle(
                    fontSize: 11.5, color: AppTheme.textSecondary(context)),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: AppTheme.textSecondary(context)),
          ],
        ),
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
    // Push remains editable even when locked â€” it's a per-device control.
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
