import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';
import '../../widgets/ui/content_width.dart';

import '../../providers/auth_provider.dart';
import '../../providers/notifications_provider.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../widgets/corex/corex_app_bar.dart';
import '../../widgets/corex/corex_bottom_nav.dart';
import '../../widgets/corex/corex_drawer.dart';
import '../../widgets/corex/corex_ellie_card.dart';
import '../../widgets/corex/corex_module_tile.dart';
import '../../widgets/corex/corex_next_appointment.dart';
import '../../providers/portal_leads_provider.dart';
import '../contacts/contacts_list_screen.dart';
import '../ellie/ellie_screen.dart';
import '../notifications/notifications_screen.dart';
import '../core_matches/core_matches_list_screen.dart';
import '../my_agent_qr_screen.dart';
import '../portal_leads/portal_leads_screen.dart';
import '../properties/property_list_screen.dart';
import '../real_estate_hub_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final firstName = _firstName(auth.userName);
    final agencyName = _agencyName(auth.user);
    final unread = context.watch<NotificationsProvider>().unread;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: CorexTokens.pageBase(context),
        drawer: const CorexDrawer(),
        body: Container(
          decoration: BoxDecoration(gradient: CorexTokens.pageBacklight(context)),
          child: ContentSafeArea(
            bottom: false,
            child: Column(
              children: [
                Builder(
                  builder: (ctx) => CorexAppBar(
                    // No avatar badge — the account lives on the "Me" tab.
                    unreadBadge: unread,
                    onMenuTap: () => Scaffold.of(ctx).openDrawer(),
                    onBellTap: () => _push(ctx, const NotificationsScreen()),
                    onQrTap: () => _push(ctx, const MyAgentQrScreen()),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      // The page is sized to fit rather than scrolled: gaps
                      // tighten on shorter devices and the module grid absorbs
                      // whatever slack is left. 640 is roughly the body height
                      // of a 6.1" phone once the app bar and bottom nav are
                      // taken out, so anything at or above that keeps the full
                      // spacing.
                      final density = (box.maxHeight / 640).clamp(0.65, 1.0);
                      double gap(double v) => v * density;

                      return Padding(
                        padding: EdgeInsets.fromLTRB(16, gap(4), 16, gap(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (agencyName != null) ...[
                              Text(
                                agencyName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: CorexTokens.textTertiary(context),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              SizedBox(height: gap(6)),
                            ],
                            Text(
                              'Good ${_timeOfDay()}, $firstName.',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: CorexTokens.textPrimary(context),
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                              ),
                            ),
                            SizedBox(height: gap(18)),
                            CorexEllieCard(
                              onTap: () => _push(context, const EllieScreen()),
                            ),
                            SizedBox(height: gap(16)),
                            const CorexNextAppointment(),
                            SizedBox(height: gap(22)),
                            _sectionHeader(
                              'Workspace',
                              onAll: () =>
                                  _push(context, const RealEstateHubScreen()),
                            ),
                            SizedBox(height: gap(12)),
                            Expanded(child: _moduleGrid(context)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                CorexBottomNav(
                  active: CorexNavTab.home,
                  onTap: (tab) => _onNavTap(context, tab),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String label, {required VoidCallback onAll}) {
    return Builder(
      builder: (context) {
        final t = CorexAccentTheme.of(context);
        return Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: CorexTokens.textPrimary(context),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            InkWell(
              onTap: onAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    Text(
                      'All',
                      style: TextStyle(
                        color: t.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(TablerIcons.arrow_right, size: 14, color: t.accent),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _moduleGrid(BuildContext context) {
    final modules = <_ModuleSpec>[
      _ModuleSpec(
        icon: TablerIcons.building_skyscraper,
        label: 'Properties',
        builder: () => const PropertyListScreen(),
      ),
      _ModuleSpec(
        icon: TablerIcons.users,
        label: 'Contacts',
        builder: () => const ContactsListScreen(),
      ),
      _ModuleSpec(
        icon: TablerIcons.heart_handshake,
        label: 'Core Matches',
        builder: () => const CoreMatchesListScreen(),
      ),
      _ModuleSpec(
        icon: TablerIcons.target_arrow,
        label: 'Portal Leads',
        dot: context.watch<PortalLeadsProvider>().totalUnread > 0,
        builder: () => const PortalLeadsScreen(),
      ),
    ];

    const spacing = 10.0;
    const columns = 3;
    // Tallest a tile may get (square) and the shortest it can be before the
    // icon + label stack stops fitting.
    const idealTileHeight = 94.0;

    return LayoutBuilder(
      builder: (context, box) {
        final rows = (modules.length / columns).ceil();
        final tileWidth = (box.maxWidth - spacing * (columns - 1)) / columns;
        final maxTileHeight = tileWidth;
        final minTileHeight = math.min(idealTileHeight, maxTileHeight);
        final free = box.maxHeight - spacing * (rows - 1);
        final tileHeight =
            (free / rows).clamp(minTileHeight, maxTileHeight);

        return GridView.count(
          padding: EdgeInsets.zero,
          // Squeezed below the floor only on unusually short screens — the
          // grid scrolls on its own there rather than overflowing the page.
          physics: const ClampingScrollPhysics(),
          crossAxisCount: columns,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          childAspectRatio: tileWidth / tileHeight,
          children: [
            for (final m in modules)
              CorexModuleTile(
                icon: m.icon,
                label: m.label,
                dot: m.dot,
                onTap: () => _push(context, m.builder()),
              ),
          ],
        );
      },
    );
  }

  void _onNavTap(BuildContext context, CorexNavTab tab) {
    corexNavigateTo(context, tab, CorexNavTab.home);
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  static String _firstName(String full) {
    final s = full.trim();
    if (s.isEmpty) return 'there';
    return s.split(RegExp(r'\s+')).first;
  }

  static String? _agencyName(Map<String, dynamic>? user) {
    if (user == null) return null;
    final candidates = <dynamic>[
      user['agency_name'],
      (user['agency'] is Map) ? (user['agency'] as Map)['name'] : null,
      (user['user'] is Map && (user['user'] as Map)['agency'] is Map)
          ? ((user['user'] as Map)['agency'] as Map)['name']
          : null,
    ];
    for (final c in candidates) {
      if (c is String && c.trim().isNotEmpty) return c.trim();
    }
    return null;
  }

  static String _timeOfDay() {
    final h = DateTime.now().hour;
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    return 'evening';
  }
}

class _ModuleSpec {
  final IconData icon;
  final String label;
  final bool dot;
  final Widget Function() builder;
  _ModuleSpec({
    required this.icon,
    required this.label,
    required this.builder,
    this.dot = false,
  });
}
