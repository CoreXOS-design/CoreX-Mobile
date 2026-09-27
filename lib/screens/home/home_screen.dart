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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Builder(
                          builder: (ctx) => _Header(
                            agencyName: agencyName,
                            greeting: 'Good ${_timeOfDay()}, $firstName',
                            unread: unread,
                            onMenuTap: () => Scaffold.of(ctx).openDrawer(),
                            onBellTap: () =>
                                _push(ctx, const NotificationsScreen()),
                            onQrTap: () => _push(ctx, const MyAgentQrScreen()),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const CorexNextAppointment(),
                        const SizedBox(height: 12),
                        CorexEllieCard(
                          onTap: () => _push(context, const EllieScreen()),
                        ),
                        const SizedBox(height: 18),
                        _sectionHeader(
                          'Workspace',
                          onAll: () =>
                              _push(context, const RealEstateHubScreen()),
                        ),
                        const SizedBox(height: 12),
                        Expanded(child: _moduleGrid(context)),
                      ],
                    ),
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
        final tileHeight = (free / rows).clamp(
          kHomeModuleTileMinHeight,
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

/// Home header: menu, greeting block, QR and notifications.
///
/// Replaces [CorexAppBar] on this screen only — the greeting moves up onto
/// the same row as the actions instead of sitting in a band beneath them,
/// which buys back a card's worth of vertical space.
class _Header extends StatelessWidget {
  final String? agencyName;
  final String greeting;
  final int unread;
  final VoidCallback onMenuTap;
  final VoidCallback onBellTap;
  final VoidCallback onQrTap;

  const _Header({
    required this.agencyName,
    required this.greeting,
    required this.unread,
    required this.onMenuTap,
    required this.onBellTap,
    required this.onQrTap,
  });

  @override
  Widget build(BuildContext context) {
    // Two rows, not one. Sharing a row with three 42 px buttons left the
    // greeting about 170 px, so "Good afternoon, <name>" ellipsised mid-name
    // — the one word on the screen that has to survive. On its own row it has
    // the full width, and a long name still gets FittedBox as a backstop.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _IconButton(
              icon: TablerIcons.menu_2,
              tooltip: 'Menu',
              onTap: onMenuTap,
            ),
            const Spacer(),
            _IconButton(
              icon: TablerIcons.qrcode,
              tooltip: 'My QR code',
              onTap: onQrTap,
            ),
            const SizedBox(width: 8),
            _IconButton(
              icon: TablerIcons.bell,
              tooltip: 'Notifications',
              badge: unread,
              onTap: onBellTap,
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (agencyName != null) ...[
          Text(
            agencyName!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: CorexTokens.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
        ],
        // Scales down instead of clipping when the name is long or the user
        // has a large text scale; it never grows past the set size.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            greeting,
            maxLines: 1,
            style: TextStyle(
              color: CorexTokens.textPrimary(context),
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// 42 px boxed icon button — the header's answer to Studio's card language.
class _IconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final int badge;
  final VoidCallback onTap;

  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    final radius = BorderRadius.circular(13);

    return Semantics(
      button: true,
      label: badge > 0 ? '$tooltip, $badge unread' : tooltip,
      child: Tooltip(
        message: tooltip,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: CorexTokens.surfaceGradient(context),
                borderRadius: radius,
                border: Border.all(color: CorexTokens.surfaceBorder(context)),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: radius,
                child: InkWell(
                  borderRadius: radius,
                  onTap: onTap,
                  child: SizedBox(
                    width: 42,
                    height: 42,
                    child: Icon(
                      icon,
                      size: 19,
                      color: CorexTokens.textPrimary(context),
                    ),
                  ),
                ),
              ),
            ),
            if (badge > 0)
              Positioned(
                top: -5,
                right: -5,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: t.accentMoney,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    // Deliberately not capped at "9+" — the cockpit rules ban
                    // that badge; a real number or nothing.
                    '$badge',
                    style: TextStyle(
                      // Picked from the fill's luminance, so a dark agency
                      // "money" colour still gets legible digits.
                      color: t.onMoney,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
