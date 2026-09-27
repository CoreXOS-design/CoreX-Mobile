import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../main.dart';
import '../../providers/auth_provider.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../providers/notifications_provider.dart';
import '../../providers/portal_leads_provider.dart';
import '../../screens/calendar_screen.dart';
import '../../screens/contacts/contacts_list_screen.dart';
import '../../screens/core_matches/core_matches_list_screen.dart';
import '../../screens/ellie/ellie_screen.dart';
import '../../screens/my_agent_qr_screen.dart';
import '../../screens/notifications/notifications_screen.dart';
import '../../screens/portal_leads/portal_leads_screen.dart';
import '../../screens/profile_screen.dart';
import '../../screens/properties/property_list_screen.dart';
import '../../screens/real_estate_hub_screen.dart';
import '../../screens/settings_screen.dart';
import '../../screens/today/today_screen.dart';

class CorexDrawer extends StatelessWidget {
  const CorexDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    final auth = context.watch<AuthProvider>();

    return Drawer(
      backgroundColor: CorexTokens.pageBase(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
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
            // The drawer used to hold only Notifications and Settings, so
            // every module was reachable from the home grid alone — and not
            // at all from inside another module. It now lists every
            // destination, grouped the way the bottom nav and home grid are.
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                children: [
                  const _SectionLabel('Workspace'),
                  _Item(
                    icon: TablerIcons.building_skyscraper,
                    label: 'Properties',
                    onTap: () => _push(context, const PropertyListScreen()),
                  ),
                  _Item(
                    icon: TablerIcons.users,
                    label: 'Contacts',
                    onTap: () => _push(context, const ContactsListScreen()),
                  ),
                  _Item(
                    icon: TablerIcons.heart_handshake,
                    label: 'Core Matches',
                    onTap: () => _push(context, const CoreMatchesListScreen()),
                  ),
                  _Item(
                    icon: TablerIcons.target_arrow,
                    label: 'Portal Leads',
                    trailingDot:
                        context.watch<PortalLeadsProvider>().totalUnread > 0,
                    onTap: () => _push(context, const PortalLeadsScreen()),
                  ),
                  _Item(
                    icon: TablerIcons.layout_grid,
                    label: 'Real Estate Hub',
                    onTap: () => _push(context, const RealEstateHubScreen()),
                  ),
                  const _SectionLabel('Your day'),
                  _Item(
                    icon: TablerIcons.calendar_event,
                    label: 'Today',
                    onTap: () => _push(context, const TodayScreen()),
                  ),
                  _Item(
                    icon: TablerIcons.calendar,
                    label: 'Calendar',
                    onTap: () => _push(context, const CalendarScreen()),
                  ),
                  _Item(
                    icon: TablerIcons.sparkles,
                    label: 'Ellie',
                    onTap: () => _push(context, const EllieScreen()),
                  ),
                  const _SectionLabel('Account'),
                  _Item(
                    icon: TablerIcons.bell,
                    label: 'Notifications',
                    badge: context.watch<NotificationsProvider>().unread,
                    onTap: () => _push(context, const NotificationsScreen()),
                  ),
                  _Item(
                    icon: TablerIcons.qrcode,
                    label: 'My QR code',
                    onTap: () => _push(context, const MyAgentQrScreen()),
                  ),
                  _Item(
                    icon: TablerIcons.user_circle,
                    label: 'Profile',
                    onTap: () => _push(context, const ProfileScreen()),
                  ),
                  _Item(
                    icon: TablerIcons.settings,
                    label: 'Settings',
                    onTap: () => _push(context, const SettingsScreen()),
                  ),
                ],
              ),
            ),
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

/// Group heading between runs of [_Item]s.
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: CorexTokens.textTertiary(context),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  /// Exact count, shown as a pill. Never capped at "9+" — the cockpit rules
  /// ban that badge; a real number or nothing.
  final int badge;

  /// A plain dot for "there's something here" where no meaningful count
  /// exists, so the row doesn't have to invent one.
  final bool trailingDot;

  const _Item({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.badge = 0,
    this.trailingDot = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    final color = destructive
        ? const Color(0xFFEF4444)
        : CorexTokens.textPrimary(context);

    Widget? trailing;
    if (badge > 0) {
      trailing = Container(
        constraints: const BoxConstraints(minWidth: 20),
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.accentMoney,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$badge',
          style: TextStyle(
            color: t.onMoney,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
      );
    } else if (trailingDot) {
      trailing = Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: t.accentMoney,
          shape: BoxShape.circle,
        ),
      );
    }

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
      trailing: trailing,
      minVerticalPadding: 12,
      onTap: onTap,
    );
  }
}
