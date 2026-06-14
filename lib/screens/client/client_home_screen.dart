import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../providers/client_session_provider.dart';
import '../../providers/seller_listings_provider.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../widgets/client/client_bottom_nav.dart';
import '../../widgets/client/client_drawer.dart';
import '../../widgets/corex/corex_app_bar.dart';
import '../../widgets/corex/corex_card.dart';
import '../../widgets/corex/corex_ellie_teaser.dart';
import '../../widgets/corex/corex_kpi_tile.dart';
import '../../widgets/corex/corex_module_tile.dart';
import 'client_coming_soon_screen.dart';
import 'client_profile_screen.dart';
import 'client_seller_listings_screen.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  @override
  void initState() {
    super.initState();
    // Login and agency-selection don't return the contact (only the profile
    // email), so pull /v1/client/me on open to resolve the client's name for
    // the current agency. Falls back to the email only while this is in flight.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ClientSessionProvider>().refreshMe();
      // Probe seller listings so the "My Listings" entry only appears when the
      // client actually owns/sells a property in their current agency.
      context.read<SellerListingsProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<ClientSessionProvider>();
    final sellerListings = context.watch<SellerListingsProvider>();
    final name = session.contact?.fullName.isNotEmpty == true
        ? session.contact!.fullName
        : (session.client?.email.split('@').first ?? 'there');
    final firstName = _firstName(name);
    final initials = _initials(name);
    final agencyName = session.currentAgency?.name;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: CorexTokens.pageBase(context),
        drawer: const ClientDrawer(),
        body: Container(
          decoration:
              BoxDecoration(gradient: CorexTokens.pageBacklight(context)),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Builder(
                  builder: (ctx) => CorexAppBar(
                    userInitials: initials,
                    unreadBadge: 0,
                    onMenuTap: () => Scaffold.of(ctx).openDrawer(),
                    onBellTap: () => _comingSoon(ctx, 'Notifications'),
                    onAvatarTap: () => _push(ctx, const ClientProfileScreen()),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (agencyName != null && agencyName.isNotEmpty) ...[
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
                        CorexEllieTeaser(
                          onTap: () => _comingSoon(context, 'Ellie'),
                        ),
                        const SizedBox(height: 16),
                        _kpiRow(),
                        const SizedBox(height: 16),
                        _NextUpCard(
                          onTap: () => _comingSoon(context, 'Your activity'),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Explore',
                          style: TextStyle(
                            color: CorexTokens.textPrimary(context),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _moduleGrid(context, sellerListings),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                ClientBottomNav(
                  active: ClientNavTab.home,
                  onTap: (tab) =>
                      clientNavigateTo(context, tab, ClientNavTab.home),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kpiRow() {
    return const Row(
      children: [
        Expanded(child: CorexKpiTile(label: 'Coming soon', value: '—')),
        SizedBox(width: 10),
        Expanded(child: CorexKpiTile(label: 'Coming soon', value: '—')),
        SizedBox(width: 10),
        Expanded(
          child: CorexKpiTile(label: 'Coming soon', value: '—', money: true),
        ),
      ],
    );
  }

  Widget _moduleGrid(
      BuildContext context, SellerListingsProvider sellerListings) {
    final modules = <_ModuleSpec>[
      _ModuleSpec(icon: TablerIcons.heart_handshake, label: 'Core Matches'),
      _ModuleSpec(icon: TablerIcons.home_search, label: 'Saved Homes'),
      _ModuleSpec(icon: TablerIcons.calendar_event, label: 'Viewings'),
      _ModuleSpec(icon: TablerIcons.file_text, label: 'Documents'),
      _ModuleSpec(icon: TablerIcons.message_circle, label: 'Messages'),
      _ModuleSpec(icon: TablerIcons.lifebuoy, label: 'Support'),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.0,
      children: [
        // Live entry — only shown when the client owns/sells a listing.
        if (sellerListings.hasListings)
          CorexModuleTile(
            icon: TablerIcons.building_estate,
            label: 'My Listings',
            onTap: () =>
                openSellerDashboard(context, sellerListings.properties),
          ),
        for (final m in modules)
          CorexModuleTile(
            icon: m.icon,
            label: m.label,
            onTap: () => _comingSoon(context, m.label),
          ),
      ],
    );
  }

  void _comingSoon(BuildContext context, String feature) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientComingSoonScreen(feature: feature),
      ),
    );
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
  _ModuleSpec({required this.icon, required this.label});
}

/// Placeholder hero card that mirrors the staff "next appointment" card while
/// the client activity feed is still being built.
class _NextUpCard extends StatelessWidget {
  final VoidCallback onTap;
  const _NextUpCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    return CorexCard(
      accent: true,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: t.accentSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(TablerIcons.sparkles, color: t.accent, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'WHAT\'S NEXT',
                  style: TextStyle(
                    color: CorexTokens.textTertiary(context),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your personalised activity feed is coming soon',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CorexTokens.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Icon(TablerIcons.chevron_right,
              size: 18, color: CorexTokens.textTertiary(context)),
        ],
      ),
    );
  }
}
