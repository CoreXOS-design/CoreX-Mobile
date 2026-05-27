import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/notification_models.dart';
import '../../providers/notifications_provider.dart';
import '../../services/messaging_service.dart';
import '../../theme.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final Set<String> _expanded = {'property'};

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
    final locked = data?.agencyControlled ?? false;

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: const Text('Notifications'),
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
                _MasterSwitches(master: data.master, locked: locked, onChanged: () {
                  setState(() {});
                }),
                const SizedBox(height: 8),
                for (final group in data.groups)
                  _PillarGroup(
                    group: group,
                    expanded: _expanded.contains(group.pillar),
                    locked: locked,
                    onToggleExpand: () => setState(() {
                      if (!_expanded.add(group.pillar)) {
                        _expanded.remove(group.pillar);
                      }
                    }),
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
          content: Text(p.prefs?.agencyControlled == true
              ? 'Locked by agency — settings frozen.'
              : (p.prefsError ?? 'Failed to save')),
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
              content: Text('Test notification sent — check your notification bar.'),
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
              'Your agency manages notification settings centrally.',
              style: TextStyle(
                  fontSize: 12, color: AppTheme.textPrimary(context)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MasterSwitches extends StatelessWidget {
  final MasterChannels master;
  final bool locked;
  final VoidCallback onChanged;

  const _MasterSwitches(
      {required this.master, required this.locked, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        children: [
          _row(context, 'In-app', master.inApp, (v) {
            master.inApp = v;
            onChanged();
          }),
          _divider(context),
          _row(context, 'Email', master.email, (v) {
            master.email = v;
            onChanged();
          }),
          _divider(context),
          _row(context, 'Push', master.push, (v) {
            master.push = v;
            onChanged();
          }),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, bool value,
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
          onChanged: locked ? null : onTap,
          activeTrackColor: AppTheme.brand,
        ),
      ],
    );
  }

  Widget _divider(BuildContext context) =>
      Divider(height: 1, color: AppTheme.borderColor(context));
}

class _PillarGroup extends StatelessWidget {
  final PreferenceGroup group;
  final bool expanded;
  final bool locked;
  final VoidCallback onToggleExpand;
  final VoidCallback onChanged;

  const _PillarGroup({
    required this.group,
    required this.expanded,
    required this.locked,
    required this.onToggleExpand,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggleExpand,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(group.label,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary(context))),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.textSecondary(context),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            Divider(height: 1, color: AppTheme.borderColor(context)),
            for (var i = 0; i < group.items.length; i++) ...[
              if (i > 0) Divider(height: 1, color: AppTheme.borderColor(context)),
              _PrefRow(
                pref: group.items[i],
                locked: locked,
                onChanged: onChanged,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PrefRow extends StatelessWidget {
  final NotificationPreference pref;
  final bool locked;
  final VoidCallback onChanged;

  const _PrefRow({
    required this.pref,
    required this.locked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pref.label,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textPrimary(context))),
                    if (pref.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(pref.description,
                          style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary(context))),
                    ],
                  ],
                ),
              ),
              Switch(
                value: pref.enabled,
                onChanged: locked
                    ? null
                    : (v) {
                        pref.enabled = v;
                        onChanged();
                      },
                activeTrackColor: AppTheme.brand,
              ),
            ],
          ),
          if (pref.enabled && pref.thresholdUnit != 'none')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _ThresholdStepper(pref: pref, locked: locked, onChanged: onChanged),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              _channelChip(context, 'In-app', pref.channelInApp, (v) {
                pref.channelInApp = v;
                onChanged();
              }),
              const SizedBox(width: 6),
              _channelChip(context, 'Email', pref.channelEmail, (v) {
                pref.channelEmail = v;
                onChanged();
              }),
              const SizedBox(width: 6),
              _channelChip(context, 'Push', pref.channelPush, (v) {
                pref.channelPush = v;
                onChanged();
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _channelChip(BuildContext context, String label, bool active,
      ValueChanged<bool> onTap) {
    final disabled = locked || !pref.enabled;
    return GestureDetector(
      onTap: disabled ? null : () => onTap(!active),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.brand.withValues(alpha: 0.14)
              : AppTheme.surface2(context),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(
            color: active
                ? AppTheme.brand.withValues(alpha: 0.5)
                : AppTheme.borderColor(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? Icons.check_box : Icons.check_box_outline_blank,
              size: 14,
              color: active
                  ? AppTheme.brand
                  : (disabled
                      ? AppTheme.textMuted(context)
                      : AppTheme.textSecondary(context)),
            ),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: active
                        ? AppTheme.brand
                        : (disabled
                            ? AppTheme.textMuted(context)
                            : AppTheme.textSecondary(context)))),
          ],
        ),
      ),
    );
  }
}

class _ThresholdStepper extends StatelessWidget {
  final NotificationPreference pref;
  final bool locked;
  final VoidCallback onChanged;

  const _ThresholdStepper(
      {required this.pref, required this.locked, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final value = pref.threshold ?? pref.thresholdMin ?? 1;
    final min = pref.thresholdMin ?? 1;
    final max = pref.thresholdMax ?? 365;
    final disabled = locked;

    return Row(
      children: [
        Text('Threshold:',
            style: TextStyle(
                fontSize: 11, color: AppTheme.textSecondary(context))),
        const SizedBox(width: 8),
        _stepBtn(context, Icons.remove, disabled || value <= min, () {
          pref.threshold = value - 1;
          onChanged();
        }),
        SizedBox(
          width: 36,
          child: Center(
            child: Text('$value',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context))),
          ),
        ),
        _stepBtn(context, Icons.add, disabled || value >= max, () {
          pref.threshold = value + 1;
          onChanged();
        }),
        const SizedBox(width: 6),
        Text(pref.thresholdUnit,
            style: TextStyle(
                fontSize: 11, color: AppTheme.textSecondary(context))),
      ],
    );
  }

  Widget _stepBtn(
      BuildContext context, IconData icon, bool disabled, VoidCallback onTap) {
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon,
            size: 16,
            color: disabled
                ? AppTheme.textMuted(context)
                : AppTheme.brand),
      ),
    );
  }
}
