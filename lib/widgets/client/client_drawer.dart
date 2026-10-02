import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../providers/client_session_provider.dart';
import '../../providers/client_matches_provider.dart';
import '../../providers/seller_listings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../screens/auth/client/client_agency_picker_screen.dart';
import '../../screens/client/client_consent_screen.dart';
import '../../screens/client/client_matches_list_screen.dart';
import '../../screens/client/client_profile_screen.dart';
import '../../screens/client/client_testimonials_screen.dart';
import '../../screens/client/client_seller_listings_screen.dart';
import '../../screens/client/client_settings_screen.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';

class ClientDrawer extends StatelessWidget {
  const ClientDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    final session = context.watch<ClientSessionProvider>();
    final sellerListings = context.watch<SellerListingsProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDark;

    final name = session.contact?.fullName.isNotEmpty == true
        ? session.contact!.fullName
        : (session.client?.email ?? 'Client');
    final email = session.client?.email ?? '';
    final canSwitch =
        session.agencies.length > 1 && session.client?.lockedToAgencyId == null;

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
                      _initials(name),
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
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: CorexTokens.textPrimary(context),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          email,
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
            // Every destination, grouped like the staff drawer — not just
            // the account items — so nothing is reachable only from the Home
            // grid. A ListView, not a Column + Spacer: with the theme row,
            // My Listings and Switch agency all present this overran a
            // 640 dp phone.
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                children: [
                  const _SectionLabel('Explore'),
                  _Item(
                    icon: TablerIcons.heart_handshake,
                    label: 'Core Matches',
                    onTap: () =>
                        _push(context, const ClientMatchesListScreen()),
                  ),
                  _Item(
                    icon: TablerIcons.star,
                    label: 'Review Agent',
                    onTap: () =>
                        _push(context, const ClientTestimonialsScreen()),
                  ),
                  _Item(
                    icon: TablerIcons.shield_lock,
                    label: 'Privacy & Consent',
                    onTap: () => _push(context, const ClientConsentScreen()),
                  ),
                  const _SectionLabel('Account'),
                  _Item(
                    icon: TablerIcons.user,
                    label: 'Profile',
                    onTap: () => _push(context, const ClientProfileScreen()),
                  ),
                  if (sellerListings.hasListings)
                    _Item(
                      icon: TablerIcons.building_estate,
                      label: 'My Listings',
                      onTap: () {
                        Navigator.of(context).pop();
                        openSellerDashboard(context, sellerListings.properties);
                      },
                    ),
                  _Item(
                    icon: TablerIcons.settings,
                    label: 'Settings',
                    onTap: () => _push(context, const ClientSettingsScreen()),
                  ),
                  if (canSwitch)
                    _Item(
                      icon: TablerIcons.arrows_left_right,
                      label: 'Switch agency',
                      onTap: () => _push(
                        context,
                        const ClientAgencyPickerScreen(initialPick: false),
                      ),
                    ),
                  ListTile(
                    leading: Icon(
                      isDark ? TablerIcons.moon : TablerIcons.sun,
                      color: t.accent,
                      size: 22,
                    ),
                    title: Text(
                      isDark ? 'Dark Mode' : 'Light Mode',
                      style: TextStyle(
                        color: CorexTokens.textPrimary(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: Switch(
                      value: isDark,
                      activeTrackColor: t.accent,
                      onChanged: (_) => themeProvider.toggle(),
                    ),
                    minVerticalPadding: 14,
                    onTap: () => themeProvider.toggle(),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0x14FFFFFF), height: 1),
            _Item(
              icon: TablerIcons.logout,
              label: 'Sign out',
              destructive: true,
              onTap: () {
                Navigator.of(context).pop();
                context.read<SellerListingsProvider>().reset();
                context.read<ClientMatchesProvider>().reset();
                session.signOut();
              },
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

/// Group heading between runs of [_Item]s — same treatment as the staff
/// drawer so both sides of the app read as one product.
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
