import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/branding.dart';
import '../theme.dart';
import '../providers/auth_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/theme_provider.dart';
import '../services/security_service.dart';
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
    final openHours = context.watch<NotificationsProvider>().prefs?.openHours;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
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
                    Text(
                      openHours?.summary() ?? '—',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMuted(context),
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
          trailing,
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
