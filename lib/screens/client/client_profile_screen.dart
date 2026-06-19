import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../providers/client_session_provider.dart';
import '../../providers/client_matches_provider.dart';
import '../../providers/seller_listings_provider.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../widgets/client/client_bottom_nav.dart';
import '../../widgets/corex/corex_card.dart';
import '../../widgets/corex/corex_scaffold.dart';
import 'client_consent_screen.dart';
import 'client_settings_screen.dart';
import 'client_testimonials_screen.dart';

const Color _kDanger = Color(0xFFEF4444);

class ClientProfileScreen extends StatelessWidget {
  const ClientProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<ClientSessionProvider>();
    final t = CorexAccentTheme.of(context);

    final name = session.contact?.fullName.isNotEmpty == true
        ? session.contact!.fullName
        : (session.client?.email.split('@').first ?? 'Client');
    final email = session.client?.email ?? session.contact?.email ?? '';
    final agency = session.currentAgency?.name;

    return CorexScaffold(
      title: 'Profile',
      showBack: false,
      bottomBar: ClientBottomNav(
        active: ClientNavTab.profile,
        onTap: (tab) =>
            clientNavigateTo(context, tab, ClientNavTab.profile),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: t.accentSoft,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: t.accentBorder),
              ),
              alignment: Alignment.center,
              child: Text(
                _initials(name),
                style: TextStyle(
                  color: t.accent,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CorexTokens.textPrimary(context),
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              email,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CorexTokens.textSecondary(context),
                fontSize: 14,
              ),
            ),
          ],
          const SizedBox(height: 28),
          _InfoCard(
            rows: [
              ('Name', name),
              ('Email', email.isEmpty ? '—' : email),
              if (agency != null && agency.isNotEmpty) ('Agency', agency),
            ],
          ),
          const SizedBox(height: 16),
          _ActionRow(
            icon: TablerIcons.star,
            label: 'Review your agent',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ClientTestimonialsScreen(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _ActionRow(
            icon: TablerIcons.shield_lock,
            label: 'Privacy & consent',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ClientConsentScreen(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _ActionRow(
            icon: TablerIcons.settings,
            label: 'Account settings',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ClientSettingsScreen(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _ActionRow(
            icon: TablerIcons.logout,
            label: 'Sign out',
            tint: _kDanger,
            onTap: () {
              // Profile is a pushed route above AuthGate. Pop back to the root
              // first so that when signOut() flips isLoggedIn, AuthGate's
              // LoginScreen is actually visible — otherwise this route stays on
              // top showing an empty (signed-out) profile. Mirrors the drawer.
              context.read<SellerListingsProvider>().reset();
              context.read<ClientMatchesProvider>().reset();
              Navigator.of(context).popUntil((route) => route.isFirst);
              session.signOut();
            },
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _InfoCard extends StatelessWidget {
  final List<(String, String)> rows;
  const _InfoCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    return CorexCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Divider(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            Row(
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    rows[i].$1,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: CorexTokens.textTertiary(context),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    rows[i].$2,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: CorexTokens.textPrimary(context),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? tint;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    final color = tint ?? t.accent;
    return CorexCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: tint ?? CorexTokens.textPrimary(context),
              ),
            ),
          ),
          Icon(TablerIcons.chevron_right,
              size: 18, color: CorexTokens.textTertiary(context)),
        ],
      ),
    );
  }
}
