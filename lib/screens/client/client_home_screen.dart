import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';
import '../../widgets/ui/content_width.dart';
import '../../utils/external_launch.dart';

import '../../models/client_models.dart';
import '../../models/seller_models.dart';
import '../../providers/client_matches_provider.dart';
import '../../providers/client_session_provider.dart';
import '../../providers/seller_listings_provider.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../widgets/client/client_bottom_nav.dart';
import '../../widgets/client/client_drawer.dart';
import '../../widgets/corex/corex_card.dart';
import '../../widgets/corex/corex_home_header.dart';
import '../../widgets/corex/corex_module_tile.dart';
import '../home/home_screen.dart'
    show kHomeModuleTileCompactHeight, kHomeModuleTileMaxHeight;
import 'client_consent_screen.dart';
import 'client_matches_list_screen.dart';
import 'client_profile_screen.dart';
import 'client_property_screen.dart';
import 'client_seller_listings_screen.dart';
import 'client_settings_screen.dart';
import 'client_testimonials_screen.dart';
import '../../widgets/corex_photo.dart';

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
      // Load Core Match results for the "Matched for you" carousel.
      context.read<ClientMatchesProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<ClientSessionProvider>();
    final sellerListings = context.watch<SellerListingsProvider>();
    final matches = context.watch<ClientMatchesProvider>();
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
          child: ContentSafeArea(
            bottom: false,
            child: Column(
              children: [
                // Like the staff Home, this is one fixed screen — it never
                // scrolls. Everything above the grid takes its natural height
                // and the grid absorbs what's left, stepping down in density
                // (see the flags below) rather than overflowing.
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                    child: LayoutBuilder(builder: (context, box) {
                      final h = box.maxHeight;
                      final hasListing = sellerListings.hasListings;
                      final hasMatches = matches.listings.isNotEmpty;
                      // Measured pieces (dp): header 103 + gap 16, agent card
                      // 166 (80 compact), listing card 93 + gap 16, carousel
                      // block 284, compact matches card 72 + gap 16, Explore
                      // heading 24 + gap 12, grid 196 at the comfortable tile
                      // floor / 132 compact. Fixed cost before the matches
                      // surface, with the full agent card:
                      final base = 103 + 16 + 166 + 22 + (hasListing ? 109 : 0);
                      final showCarousel =
                          hasMatches && h >= base + 284 + 36 + 196;
                      final showMatchesCard = hasMatches &&
                          !showCarousel &&
                          h >= base + 88 + 36 + 132;
                      final matchesCost =
                          showCarousel ? 284 : (showMatchesCard ? 88 : 0);
                      // Steps below that: the agent card folds its three
                      // labelled buttons into inline icons, then the Explore
                      // heading goes, and as a last resort the listing card
                      // (still in the drawer under My Listings) — a 640 dp
                      // phone with a button nav bar lands exactly there.
                      final compactAgent = h < base + matchesCost + 36 + 132;
                      final baseNow = compactAgent ? base - 86 : base;
                      final showListing =
                          hasListing && h >= baseNow + matchesCost + 132;
                      final baseFinal = (hasListing && !showListing)
                          ? baseNow - 109
                          : baseNow;
                      final showSectionHeader =
                          h >= baseFinal + matchesCost + 36 + 132;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Same header as the staff Home: boxed menu button,
                          // identity button on the right, agency eyebrow and
                          // greeting on their own row.
                          Builder(
                            builder: (ctx) => CorexHomeHeader(
                              agencyName: agencyName,
                              greeting: 'Good ${_timeOfDay()}, $firstName',
                              onMenuTap: () => Scaffold.of(ctx).openDrawer(),
                              actions: [
                                CorexHeaderButton(
                                  label: initials,
                                  tooltip: 'Profile',
                                  onTap: () =>
                                      _push(ctx, const ClientProfileScreen()),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _AgentContactCard(
                            agent: session.agent,
                            compact: compactAgent,
                            agencyName: agencyName,
                          ),
                          if (showListing) ...[
                            const SizedBox(height: 16),
                            _MyListingsCard(
                              properties: sellerListings.properties,
                              onTap: () => openSellerDashboard(
                                  context, sellerListings.properties),
                            ),
                          ],
                          // Matched listings — the full carousel only when the
                          // page has room for it without scrolling; otherwise a
                          // one-line card into the same list, so the surface is
                          // never silently gone.
                          if (showCarousel) ...[
                            const SizedBox(height: 22),
                            _MatchedCarousel(
                              listings: matches.listings,
                              onSeeAll: () => _push(
                                  context, const ClientMatchesListScreen()),
                              onTapListing: _openListing,
                            ),
                          ] else if (showMatchesCard) ...[
                            const SizedBox(height: 16),
                            _MatchedCompactCard(
                              count: matches.listings.length,
                              onTap: () => _push(
                                  context, const ClientMatchesListScreen()),
                            ),
                          ],
                          const SizedBox(height: 22),
                          if (showSectionHeader) ...[
                            Text(
                              'Explore',
                              style: TextStyle(
                                color: CorexTokens.textPrimary(context),
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          Expanded(child: _moduleGrid(context)),
                        ],
                      );
                    }),
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

  Widget _moduleGrid(BuildContext context) {
    const spacing = 12.0;
    const rows = 2;
    // 2-up like the staff Workspace grid, and sized the same way: the grid
    // is the page's shock absorber, taking whatever height is left so Home
    // ends exactly at the nav. Tiles flex between the staff grid's compact
    // floor and ceiling (CorexModuleTile sheds its own content on the way
    // down), so the grid never needs a scroll of its own.
    return LayoutBuilder(builder: (context, box) {
      final free = box.maxHeight - spacing * (rows - 1);
      final tileHeight = (free / rows).clamp(
        kHomeModuleTileCompactHeight,
        kHomeModuleTileMaxHeight,
      );
      return GridView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          mainAxisExtent: tileHeight,
        ),
        children: [
          // Live entry — the client's saved searches and matched listings.
          // Money accent on alternate tiles, as on the staff grid, so the
          // four don't read as one flat block of colour.
          CorexModuleTile(
            icon: TablerIcons.heart_handshake,
            label: 'Core Matches',
            useMoneyAccent: true,
            onTap: () => _push(context, const ClientMatchesListScreen()),
          ),
          // Review your agent — write a testimonial and see ones you've sent.
          CorexModuleTile(
            icon: TablerIcons.star,
            label: 'Review Agent',
            onTap: () => _push(context, const ClientTestimonialsScreen()),
          ),
          // Privacy & consent — view/set the client's own POPIA/CPA consent.
          CorexModuleTile(
            icon: TablerIcons.shield_lock,
            label: 'Privacy & Consent',
            onTap: () => _push(context, const ClientConsentScreen()),
          ),
          // Fourth tile so the 2-up grid has no orphan; Settings is otherwise
          // only reachable via the drawer and Profile.
          CorexModuleTile(
            icon: TablerIcons.settings,
            label: 'Settings',
            useMoneyAccent: true,
            onTap: () => _push(context, const ClientSettingsScreen()),
          ),
        ],
      );
    });
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _openListing(MatchedListing item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientPropertyScreen(
          propertyId: item.result.id,
          matchId: item.matchId,
          initialReaction: item.result.reaction,
          initialReactionNote: item.result.reactionNote,
        ),
      ),
    );
    // A reaction (e.g. "not for me") may have changed what should appear in the
    // carousel — refresh so a rejected listing drops out.
    if (mounted) context.read<ClientMatchesProvider>().load();
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

/// Horizontal "Matched for you" strip of the client's top matched listings,
/// drawn from their Core Match searches.
class _MatchedCarousel extends StatelessWidget {
  final List<MatchedListing> listings;
  final VoidCallback onSeeAll;
  final void Function(MatchedListing item) onTapListing;

  const _MatchedCarousel({
    required this.listings,
    required this.onSeeAll,
    required this.onTapListing,
  });

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Matched for you',
                style: TextStyle(
                  color: CorexTokens.textPrimary(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            GestureDetector(
              onTap: onSeeAll,
              child: Text(
                'See all',
                style: TextStyle(
                  color: t.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 232,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: listings.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _MatchedCard(
              item: listings[i],
              onTap: () => onTapListing(listings[i]),
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact property card for the [_MatchedCarousel].
class _MatchedCard extends StatelessWidget {
  final MatchedListing item;
  final VoidCallback onTap;
  const _MatchedCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    final r = item.result;
    final price =
        r.priceDisplay ?? (r.price != null ? 'R ${_money(r.price!)}' : null);

    return SizedBox(
      width: 190,
      child: CorexCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 118,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (r.thumbnail != null && r.thumbnail!.isNotEmpty)
                    CoreXPhoto.thumb(
                      url: r.thumbnail!,
                      logicalWidth: 190,
                      placeholder: (_) => Container(
                        color: CorexTokens.surfaceTop(context),
                      ),
                      errorWidget: (_) => Container(
                        color: CorexTokens.surfaceTop(context),
                        child: Icon(TablerIcons.photo_off,
                            color: CorexTokens.textTertiary(context)),
                      ),
                    )
                  else
                    Container(
                      color: CorexTokens.surfaceTop(context),
                      child: Icon(TablerIcons.home,
                          color: CorexTokens.textTertiary(context), size: 32),
                    ),
                  if (r.matchScore != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${r.matchScore}% match',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (price != null)
                    Text(
                      price,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: t.accentMoney,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    r.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: CorexTokens.textPrimary(context),
                    ),
                  ),
                  if (r.suburb != null && r.suburb!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        r.suburb!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: CorexTokens.textSecondary(context),
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (r.beds != null) ...[
                        Icon(TablerIcons.bed,
                            size: 13,
                            color: CorexTokens.textSecondary(context)),
                        const SizedBox(width: 2),
                        Text('${r.beds}',
                            style: TextStyle(
                                fontSize: 12,
                                color: CorexTokens.textPrimary(context))),
                        const SizedBox(width: 10),
                      ],
                      if (r.baths != null) ...[
                        Icon(TablerIcons.bath,
                            size: 13,
                            color: CorexTokens.textSecondary(context)),
                        const SizedBox(width: 2),
                        Text('${r.baths}',
                            style: TextStyle(
                                fontSize: 12,
                                color: CorexTokens.textPrimary(context))),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _money(num n) {
    final s = n.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      buf.write(s[i]);
      if (fromEnd > 1 && (fromEnd - 1) % 3 == 0) buf.write(' ');
    }
    return buf.toString();
  }
}

/// Hero card surfacing the client's seller listing(s). Mirrors the agent card:
/// a single listing shows its thumbnail + headline stats and deep-links to the
/// dashboard; multiple listings show a count and open the list.
class _MyListingsCard extends StatelessWidget {
  final List<SellerProperty> properties;
  final VoidCallback onTap;
  const _MyListingsCard({required this.properties, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    final single = properties.length == 1;
    final p = properties.first;
    final title = single
        ? ((p.title != null && p.title!.trim().isNotEmpty)
            ? p.title!
            : (p.address ?? 'Your listing'))
        : '${properties.length} listings';

    return CorexCard(
      onTap: onTap,
      child: Row(
        children: [
          _leading(context, t, single ? p.thumbnail : null),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'MY LISTING${single ? '' : 'S'}',
                  style: TextStyle(
                    color: CorexTokens.textTertiary(context),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CorexTokens.textPrimary(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  single ? _statsLine(p) : 'View live marketing stats',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CorexTokens.textSecondary(context),
                    fontSize: 12,
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

  Widget _leading(BuildContext context, CorexAccentTheme t, String? thumb) {
    if (thumb != null && thumb.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CoreXPhoto.thumb(
          url: thumb,
          logicalWidth: 60,
          width: 60,
          height: 60,
          placeholder: (_) => Container(
            width: 60,
            height: 60,
            color: CorexTokens.surfaceTop(context),
          ),
          errorWidget: (_) => _iconBox(context, t),
        ),
      );
    }
    return _iconBox(context, t);
  }

  Widget _iconBox(BuildContext context, CorexAccentTheme t) => Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: t.accentSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(TablerIcons.building_estate, color: t.accent, size: 26),
      );

  String _statsLine(SellerProperty p) {
    final parts = <String>[];
    if (p.headline.viewings != null) {
      parts.add('${p.headline.viewings} viewing'
          '${p.headline.viewings == 1 ? '' : 's'}');
    }
    if (p.headline.daysOnMarket != null) {
      parts.add('${p.headline.daysOnMarket} days listed');
    }
    return parts.isEmpty ? 'View live marketing stats' : parts.join(' · ');
  }
}

/// Hero card surfacing the client's assigned agent for the current agency,
/// with one-tap call / WhatsApp / email. Falls back to an agency-only prompt
/// while the backend has no agent linked (or hasn't started returning one).
class _AgentContactCard extends StatelessWidget {
  final ClientAgent? agent;
  final String? agencyName;

  /// Short-page variant: one row, with Call / WhatsApp / Email as inline
  /// icon buttons instead of the labelled row beneath — about half the
  /// height, nothing lost.
  final bool compact;

  const _AgentContactCard({
    required this.agent,
    required this.agencyName,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final a = agent;

    if (a == null) {
      // No agent linked yet — keep the slot meaningful, not empty.
      return CorexCard(
        child: Row(
          children: [
            _avatar(context, null),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _eyebrow(context, 'YOUR AGENT'),
                  const SizedBox(height: 4),
                  Text(
                    agencyName != null && agencyName!.isNotEmpty
                        ? 'Your $agencyName agent will appear here'
                        : 'Your agent will appear here',
                    style: TextStyle(
                      color: CorexTokens.textPrimary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final subtitle = (a.title != null && a.title!.isNotEmpty)
        ? a.title!
        : (a.agencyName ?? agencyName ?? 'Your agent');

    if (compact) return _compact(context, a, subtitle);

    return CorexCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _avatar(context, a),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _eyebrow(context, 'YOUR AGENT'),
                    const SizedBox(height: 4),
                    Text(
                      a.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: CorexTokens.textPrimary(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: CorexTokens.textSecondary(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (a.hasContact) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (a.phone != null && a.phone!.isNotEmpty)
                  Expanded(
                    child: _action(
                      context,
                      icon: TablerIcons.phone,
                      label: 'Call',
                      onTap: () => _launch(context, 'tel:${a.phone}'),
                    ),
                  ),
                if (a.whatsapp != null && a.whatsapp!.isNotEmpty) ...[
                  if (a.phone != null && a.phone!.isNotEmpty)
                    const SizedBox(width: 10),
                  Expanded(
                    child: _action(
                      context,
                      icon: TablerIcons.brand_whatsapp,
                      label: 'WhatsApp',
                      onTap: () => _launch(context, _waUrl(a.whatsapp!)),
                    ),
                  ),
                ],
                if (a.email != null && a.email!.isNotEmpty) ...[
                  if ((a.phone != null && a.phone!.isNotEmpty) ||
                      (a.whatsapp != null && a.whatsapp!.isNotEmpty))
                    const SizedBox(width: 10),
                  Expanded(
                    child: _action(
                      context,
                      icon: TablerIcons.mail,
                      label: 'Email',
                      onTap: () => _launch(context, 'mailto:${a.email}'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// One-row layout for short pages: avatar, name/subtitle, then the contact
  /// actions as 36 px icon buttons on the right. Same card, same accents —
  /// only the labelled button row is folded away.
  Widget _compact(BuildContext context, ClientAgent a, String subtitle) {
    return CorexCard(
      elevated: true,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        children: [
          _avatar(context, a, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _eyebrow(context, 'YOUR AGENT'),
                const SizedBox(height: 2),
                Text(
                  a.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CorexTokens.textPrimary(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CorexTokens.textSecondary(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (a.hasContact) ...[
            const SizedBox(width: 8),
            if (a.phone != null && a.phone!.isNotEmpty)
              _iconAction(
                context,
                icon: TablerIcons.phone,
                tooltip: 'Call',
                onTap: () => _launch(context, 'tel:${a.phone}'),
              ),
            if (a.whatsapp != null && a.whatsapp!.isNotEmpty)
              _iconAction(
                context,
                icon: TablerIcons.brand_whatsapp,
                tooltip: 'WhatsApp',
                onTap: () => _launch(context, _waUrl(a.whatsapp!)),
              ),
            if (a.email != null && a.email!.isNotEmpty)
              _iconAction(
                context,
                icon: TablerIcons.mail,
                tooltip: 'Email',
                onTap: () => _launch(context, 'mailto:${a.email}'),
              ),
          ],
        ],
      ),
    );
  }

  Widget _iconAction(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final t = CorexAccentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: t.accentSoft,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(icon, color: t.accent, size: 18),
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(BuildContext context, ClientAgent? a, {double size = 60}) {
    final t = CorexAccentTheme.of(context);
    final photo = a?.photoUrl;
    if (photo != null && photo.isNotEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: t.accentSoft,
        backgroundImage: NetworkImage(photo),
        // Swallow load failures gracefully — fall back to the accent circle
        // instead of throwing and logging an image exception.
        onBackgroundImageError: (_, __) {},
      );
    }
    final initials = a != null ? _initialsOf(a.fullName) : null;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: t.accentSoft,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: initials != null
          ? Text(
              initials,
              style: TextStyle(
                color: t.accent,
                fontSize: size / 3,
                fontWeight: FontWeight.w700,
              ),
            )
          : Icon(TablerIcons.user, color: t.accent, size: 26),
    );
  }

  Widget _eyebrow(BuildContext context, String text) => Text(
        text,
        style: TextStyle(
          color: CorexTokens.textTertiary(context),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      );

  Widget _action(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final t = CorexAccentTheme.of(context);
    return Material(
      color: t.accentSoft,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: t.accent, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: t.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _waUrl(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return 'https://wa.me/$digits';
  }

  Future<void> _launch(BuildContext context, String url) =>
      launchExternal(context, url);

  static String _initialsOf(String full) {
    final parts = full.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

/// One-line stand-in for [_MatchedCarousel] when the page hasn't the height
/// for the strip: the count and a tap-through to the same list.
class _MatchedCompactCard extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _MatchedCompactCard({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    final isLight = Theme.of(context).brightness == Brightness.light;
    return CorexCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: t.moneySoft,
              borderRadius: BorderRadius.circular(CorexTokens.radiusChip),
            ),
            child: Icon(
              TablerIcons.heart_handshake,
              color: isLight ? t.moneyText : t.accentMoney,
              size: 19,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Matched for you',
                  style: TextStyle(
                    color: CorexTokens.textPrimary(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$count listing${count == 1 ? '' : 's'} match your searches',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CorexTokens.textSecondary(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            TablerIcons.chevron_right,
            size: 17,
            color: CorexTokens.textTertiary(context),
          ),
        ],
      ),
    );
  }
}
