import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../main.dart';
import '../../providers/auth_provider.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../screens/profile_screen.dart';
import '../../screens/settings_screen.dart';
import '../../screens/notifications/notifications_screen.dart';

class CorexDrawer extends StatelessWidget {
  const CorexDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    final auth = context.watch<AuthProvider>();

    return Drawer(
      backgroundColor: CorexTokens.pageBase(context),
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.horizontal(right: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: t.accentSoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: t.accentBorder),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _initials(auth.userName),
                      style: TextStyle(
                        color: t.accent,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: CorexTokens.textPrimary(context),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          auth.user?['email']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: CorexTokens.textTertiary(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0x14FFFFFF), height: 1),
            const SizedBox(height: 8),
            _Item(
              icon: TablerIcons.user,
              label: 'Profile',
              onTap: () => _push(context, const ProfileScreen()),
            ),
            _Item(
              icon: TablerIcons.bell,
              label: 'Notifications',
              onTap: () => _push(context, const NotificationsScreen()),
            ),
            _Item(
              icon: TablerIcons.settings,
              label: 'Settings',
              onTap: () => _push(context, const SettingsScreen()),
            ),
            const Spacer(),
            const Divider(color: Color(0x14FFFFFF), height: 1),
            _Item(
              icon: TablerIcons.logout,
              label: 'Sign out',
              destructive: true,
              onTap: () => logoutAndReset(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '·';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  static void _push(BuildContext context, Widget screen) {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _Item extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const _Item({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? const Color(0xFFEF4444)
        : CorexTokens.textPrimary(context);
    return ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      minVerticalPadding: 14,
      onTap: onTap,
    );
  }
}
