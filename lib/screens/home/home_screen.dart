import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';
import '../../widgets/ui/content_width.dart';

import '../../providers/auth_provider.dart';
import '../../providers/notifications_provider.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../widgets/corex/corex_bottom_nav.dart';
import '../../widgets/corex/corex_drawer.dart';
import '../../widgets/corex/corex_ellie_card.dart';
import '../../widgets/corex/corex_home_header.dart';
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

/// Bounds for a Workspace tile's height. The grid flexes between them so Home
/// fills the screen exactly and never scrolls; exported so the layout test
/// pins the same numbers the screen uses instead of re-deriving them.
///
/// The floor is what a tile needs once it has dropped its count line and
/// tightened its chip — padding (28) + chip (30) + gap (10) + label (~19).
/// [CorexModuleTile] sheds those itself as it gets shorter, so the grid can
/// go this low without overflowing and never needs a scroll of its own.
const double kHomeModuleTileMinHeight = 92;
const double kHomeModuleTileMaxHeight = 132;

/// Hard floor, below [kHomeModuleTileMinHeight]: on a short phone with the
/// Next-appointment hero in its tall (event) state there isn't room for two
/// rows of 92 px tiles, and the grid can't scroll, so the bottom row was
/// simply cut off. Under the comfortable floor the tile switches to a
/// one-line icon+label layout that fits in 60 px.
const double kHomeModuleTileCompactHeight = 60;

/// Content-column heights (what's left after the safe area, the page padding
/// and the nav) at which Home steps down a density level. Measured from the
/// pieces: header ~103, hero (event state) ~150, Ellie card 135 with the
/// daily line / 68 without, gaps 58, section header 24, grid 196 at the
/// comfortable tile floor / 132 at the compact one.
///
/// At or above [kHomeFullContentHeight] everything shows. Below it Ellie's
/// daily line goes; below [kHomeEllieContentHeight] the Ellie card goes too
/// (she stays one tap away in the nav and the drawer) and the grid is left
/// with enough for compact tiles — the alternative on a 640 dp phone was the
/// bottom tile row disappearing under the nav.
const double kHomeFullContentHeight = 670;
const double kHomeEllieContentHeight = 545;

/// Below this even the compact grid can't share the column with the
/// "Workspace" heading, so the heading goes too (the Hub stays reachable
/// from the drawer). Only ever hit on a very short window or a large text
/// scale — header ~103 + hero ~150 + gaps 34 + compact grid 132.
const double kHomeSectionHeaderContentHeight = 455;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // The bell badge reads NotificationsProvider.unread, which only the
    // Notifications/Today screens used to populate — so Home showed no count
    // until you'd opened one of them. Warm it here; maxAge keeps returning to
    // the Home tab from re-fetching every time.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context
          .read<NotificationsProvider>()
          .loadFeed(maxAge: const Duration(seconds: 60));
    });
  }

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
          decoration:
              BoxDecoration(gradient: CorexTokens.pageBacklight(context)),
          child: ContentSafeArea(
            bottom: false,
            child: Column(
              children: [
                // Home is a single screen — it never scrolls. Everything above
                // the grid takes its natural height and the grid absorbs
                // whatever is left, so the page ends exactly at the nav.
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                    child: LayoutBuilder(builder: (context, box) {
                      // Density cascade, driven by the height this column
                      // actually gets (insets and the nav already taken out)
                      // rather than the window size: first Ellie's daily line
                      // goes, then the whole Ellie card — she stays one tap
                      // away in the nav and the drawer — and the grid squeezes
                      // its tiles to the compact floor on its own.
                      final h = box.maxHeight;
                      final showQuote = h >= kHomeFullContentHeight;
                      final showEllie = h >= kHomeEllieContentHeight;
                      final showSectionHeader =
                          h >= kHomeSectionHeaderContentHeight;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Builder(
                            builder: (ctx) => CorexHomeHeader(
                              agencyName: agencyName,
                              greeting: 'Good ${_timeOfDay()}, $firstName',
                              onMenuTap: () => Scaffold.of(ctx).openDrawer(),
                              actions: [
                                CorexHeaderButton(
                                  icon: TablerIcons.qrcode,
                                  tooltip: 'My QR code',
                                  onTap: () =>
                                      _push(ctx, const MyAgentQrScreen()),
                                ),
                                CorexHeaderButton(
                                  icon: TablerIcons.bell,
                                  tooltip: 'Notifications',
                                  badge: unread,
                                  onTap: () =>
                                      _push(ctx, const NotificationsScreen()),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const CorexNextAppointment(),
                          if (showEllie) ...[
                            const SizedBox(height: 12),
                            CorexEllieCard(
                              onTap: () => _push(context, const EllieScreen()),
                              showQuote: showQuote,
                            ),
                          ],
                          const SizedBox(height: 18),
                          // Last resort on a tiny or large-text window: the
                          // heading goes (the Hub is in the drawer too) so
                          // both compact tile rows stay above the nav.
                          if (showSectionHeader) ...[
                            _sectionHeader(
                              'Workspace',
                              onAll: () =>
                                  _push(context, const RealEstateHubScreen()),
                            ),
                            const SizedBox(height: 12),
                          ],
                          Expanded(child: _moduleGrid(context)),
                        ],
                      );
                    }),
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
        final isLight = Theme.of(context).brightness == Brightness.light;
        // Link text on the page background, so it needs the readable variant
        // in light mode like every other accent-coloured label.
        final linkColour = isLight ? t.accentText : t.accent;
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
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  children: [
                    Text(
                      'All',
                      style: TextStyle(
                        color: linkColour,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(TablerIcons.arrow_right, size: 14, color: linkColour),
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
    final unreadLeads = context.watch<PortalLeadsProvider>().totalUnread;

    // Only Portal Leads has a count the home screen already holds. The other
    // three would need a list fetch each to show one, so they stay label-only
    // rather than showing a stale or invented number.
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
        useMoneyAccent: true,
        builder: () => const CoreMatchesListScreen(),
      ),
      _ModuleSpec(
        icon: TablerIcons.target_arrow,
        label: 'Portal Leads',
        dot: unreadLeads > 0,
        subtitle: unreadLeads > 0 ? '$unreadLeads unread' : null,
        useMoneyAccent: true,
        builder: () => const PortalLeadsScreen(),
      ),
    ];

    const spacing = 12.0;
    const rows = 2;

    // The grid is the page's shock absorber: it takes whatever height is left
    // once the cards above have had theirs, so Home ends exactly at the nav
    // and never scrolls. Height is driven by the space available, not by tile
    // width — deriving it from width overflowed by 2 px at 360 dp.
    return LayoutBuilder(
      builder: (context, box) {
        final free = box.maxHeight - spacing * (rows - 1);
        // Prefer the comfortable floor; fall through to the compact one only
        // when two comfortable rows genuinely don't fit, so the tiles shrink
        // rather than the bottom row disappearing under the nav.
        final tileHeight = (free / rows).clamp(
          kHomeModuleTileCompactHeight,
          kHomeModuleTileMaxHeight,
        );

        return GridView.builder(
          padding: EdgeInsets.zero,
          // Never scrolls — that's the whole point of Home being one screen.
          // The tiles shrink to fit instead.
          physics: const NeverScrollableScrollPhysics(),
          itemCount: modules.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: tileHeight,
          ),
          itemBuilder: (context, i) {
            final m = modules[i];
            return CorexModuleTile(
              icon: m.icon,
              label: m.label,
              dot: m.dot,
              subtitle: m.subtitle,
              useMoneyAccent: m.useMoneyAccent,
              onTap: () => _push(context, m.builder()),
            );
          },
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
  final String? subtitle;
  final bool useMoneyAccent;
  final Widget Function() builder;
  _ModuleSpec({
    required this.icon,
    required this.label,
    required this.builder,
    this.dot = false,
    this.subtitle,
    this.useMoneyAccent = false,
  });
}
