import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/ui/content_width.dart';
import '../models/branding.dart';
import '../models/notification_models.dart';
import '../theme.dart';
import '../providers/auth_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/theme_provider.dart';
import '../services/security_service.dart';
import '../widgets/event_reminder_picker.dart';
import '../widgets/ui/icon_badge.dart';
import '../widgets/ui/section_header.dart';
import 'notification_schedule_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _biometricSupported = false;

  @override
  void initState() {
    super.initState();
    SecurityService.instance.canUseBiometrics().then((v) {
      if (mounted) setState(() => _biometricSupported = v);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NotificationsProvider>().loadPreferences();
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final auth = context.watch<AuthProvider>();
    final brand = BrandColors.of(context);
    final isDark = themeProvider.isDark;
    final prefsData = context.watch<NotificationsProvider>().prefs;
    final openHours = prefsData?.openHours;
    final notifLocked = prefsData?.locked ?? false;
    final reminderPref =
        prefsData != null ? ensureEventReminder(prefsData) : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ContentSafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            const SectionHeader(label: 'Appearance'),
            const SizedBox(height: 12),
            _SettingsCard(children: [
              _SettingsTile(
                icon: isDark
                    ? Icons.dark_mode_rounded
                    : Icons.light_mode_rounded,
                tint: brand.button,
                label: 'Dark mode',
                trailing: Switch.adaptive(
                  value: isDark,
                  activeTrackColor: brand.button,
                  activeThumbColor: Colors.white,
                  onChanged: (_) => themeProvider.toggle(),
                ),
              ),
            ]),
            const SizedBox(height: 24),
            const SectionHeader(label: 'Notifications'),
            const SizedBox(height: 12),
            _SettingsCard(children: [
              _SettingsTile(
                icon: Icons.do_not_disturb_on_outlined,
                tint: brand.icon,
                label: 'Quiet hours',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        openHours?.summary() ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textMuted(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded,
                        size: 20, color: AppTheme.textMuted(context)),
                  ],
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const NotificationScheduleScreen(),
                )),
              ),
              if (reminderPref != null) ...[
                Divider(
                    height: 1,
                    indent: 14,
                    endIndent: 14,
                    color: AppTheme.borderColor(context)),
                _SettingsTile(
                  icon: Icons.alarm_outlined,
                  tint: brand.icon,
                  label: 'Event reminder',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          formatLeadTime(reminderPref.threshold ??
                              reminderPref.thresholdMin ??
                              60),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMuted(context),
                          ),
                        ),
                      ),
                      if (!notifLocked) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded,
                            size: 20, color: AppTheme.textMuted(context)),
                      ],
                    ],
                  ),
                  onTap: notifLocked
                      ? null
                      : () => _editReminder(reminderPref),
                ),
              ],
            ]),
            const SizedBox(height: 24),
            const SectionHeader(label: 'Security'),
            const SizedBox(height: 12),
            _SettingsCard(children: [
              _SettingsTile(
                icon: Icons.fingerprint_rounded,
                tint: brand.icon,
                label: _biometricSupported
                    ? 'Biometric sign-in'
                    : 'Biometrics not available',
                trailing: Switch.adaptive(
                  value: auth.biometricEnabled,
                  activeTrackColor: brand.button,
                  activeThumbColor: Colors.white,
                  onChanged: _biometricSupported
                      ? (v) => context
                          .read<AuthProvider>()
                          .setBiometricEnabled(v)
                      : null,
                ),
              ),
            ]),
            const SizedBox(height: 24),
            const SectionHeader(label: 'About'),
            const SizedBox(height: 12),
            _SettingsCard(children: [
              _SettingsTile(
                icon: Icons.info_outline_rounded,
                tint: brand.icon,
                label: 'Version',
                trailing: Text(
                  '1.0.0',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted(context),
                  ),
                ),
              ),
            ]),
          ],
          ),
        ),
      ),
    );
  }

  /// Opens the hours+minutes lead-time picker and persists the choice. The
  /// preference is part of the shared notification-preferences snapshot, so we
  /// save the whole thing (master, quiet hours, all items) via the provider.
  /// On failure we reconcile back to the server's state so the row never shows
  /// a value that wasn't saved.
  Future<void> _editReminder(NotificationPreference pref) async {
    final min = pref.thresholdMin ?? 5;
    final max = pref.thresholdMax ?? 10080;
    final current = (pref.threshold ?? min).clamp(min, max);

    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppTheme.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) =>
          LeadTimePickerSheet(initialMinutes: current, min: min, max: max),
    );
    if (!mounted || picked == null || picked == pref.threshold) return;

    final provider = context.read<NotificationsProvider>();
    pref.threshold = picked;
    setState(() {}); // reflect the new value on the tile immediately

    final ok = await provider.savePreferences();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Event reminder updated')),
      );
    } else {
      await provider.loadPreferences(force: true);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(provider.prefsError ?? 'Failed to save'),
        backgroundColor: const Color(0xFFef4444),
      ));
    }
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: AppTheme.softShadow(context),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String label;
  final Widget trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.tint,
    required this.label,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          IconBadge(icon: icon, tint: tint, size: 36, iconSize: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(child: trailing),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: row,
    );
  }
}
