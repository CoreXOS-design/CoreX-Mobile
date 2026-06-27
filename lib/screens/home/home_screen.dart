import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../providers/auth_provider.dart';
import '../../providers/feature_flags_provider.dart';
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
import '../coming_soon_screen.dart';
import '../contacts/contacts_list_screen.dart';
import '../ellie/ellie_screen.dart';
import '../notifications/notifications_screen.dart';
import '../core_matches/core_matches_list_screen.dart';
import '../my_agent_qr_screen.dart';
import '../portal_leads/portal_leads_screen.dart';
import '../profile_screen.dart';
import '../properties/property_list_screen.dart';
import '../real_estate_hub_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final firstName = _firstName(auth.userName);
    final initials = _initials(auth.userName);
    final agencyName = _agencyName(auth.user);
    final unread = context.watch<NotificationsProvider>().unread;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: CorexTokens.pageBase(context),
        drawer: const CorexDrawer(),
        body: Container(
          decoration: BoxDecoration(gradient: CorexTokens.pageBacklight(context)),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Builder(
                  builder: (ctx) => CorexAppBar(
                    userInitials: initials,
                    unreadBadge: unread,
                    onMenuTap: () => Scaffold.of(ctx).openDrawer(),
                    onBellTap: () => _push(ctx, const NotificationsScreen()),
                    onAvatarTap: () => _push(ctx, const ProfileScreen()),
                    onQrTap: () => _push(ctx, const MyAgentQrScreen()),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
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
                          const SizedBox(height: 6),
                        ],
                        Text(
                          'Good ${_timeOfDay()}, $firstName.',
                          style: TextStyle(
                            color: CorexTokens.textPrimary(context),
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 18),
                        CorexEllieCard(
                          aiEnabled:
                              context.watch<FeatureFlagsProvider>().aiEnabled,
                          onTap: () => _push(context, const EllieScreen()),
                        ),
                        const SizedBox(height: 16),
                        const CorexNextAppointment(),
                        const SizedBox(height: 22),
                        _sectionHeader(
                          'Workspace',
                          onAll: () =>
                              _push(context, const RealEstateHubScreen()),
                        ),
                        const SizedBox(height: 12),
                        _moduleGrid(context),
                        const SizedBox(height: 12),
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
      _ModuleSpec(
        icon: TablerIcons.hourglass_high,
        label: 'Coming Soon',
        builder: () => const ComingSoonScreen(feature: 'Coming Soon'),
      ),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.0,
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

  static String _initials(String full) {
    final parts = full.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '·';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
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
