import 'package:flutter/material.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../screens/client/client_profile_screen.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../corex/corex_bottom_nav.dart' show corexTabRoute;

enum ClientNavTab { home, profile }

/// Switches between the client's top-level tabs. Mirrors the staff
/// `corexNavigateTo` behaviour: Home is always the stack root, Profile is
/// pushed on top so the route AuthGate reacts to stays alive underneath.
void clientNavigateTo(BuildContext context, ClientNavTab tab, ClientNavTab from) {
  if (tab == from) return;
  switch (tab) {
    case ClientNavTab.home:
      // Home is the AuthGate-rooted route (the first route). Pop back down to
      // it rather than pushing a fresh ClientHomeScreen with pushAndRemoveUntil:
      // removing every route (including the AuthGate root) tears down the only
      // widget watching the session, so a later sign-out flips isLoggedIn with
      // nothing left to swap in the login screen — stranding the user on Home.
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    case ClientNavTab.profile:
      // Profile is pushed on top of Home (the AuthGate-rooted route) rather
      // than replacing it — same as the staff "Me" tab. Replacing would tear
      // down the route AuthGate reacts to, so signing out from Profile would
      // strand the user on an empty, signed-out screen instead of returning
      // them to the login screen.
      Navigator.of(context).push(
        corexTabRoute(const ClientProfileScreen()),
      );
      return;
  }
}

class ClientBottomNav extends StatelessWidget {
  final ClientNavTab active;
  final ValueChanged<ClientNavTab> onTap;

  const ClientBottomNav({
    super.key,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    final radius = BorderRadius.circular(CorexTokens.radiusNav);

    // Same floating pill as the staff nav (CorexBottomNav): shadow on its own
    // layer, hairline border, only the active tab labelled.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: CorexTokens.cardShadow(context, strong: true),
          ),
          child: Material(
            type: MaterialType.transparency,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: CorexTokens.surfaceGradient(context),
                borderRadius: radius,
                border: Border.all(color: CorexTokens.surfaceBorder(context)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    _item(context, t, ClientNavTab.home, TablerIcons.home_2,
                        'Home'),
                    _item(context, t, ClientNavTab.profile,
                        TablerIcons.user_circle, 'Profile'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, CorexAccentTheme t, ClientNavTab tab,
      IconData icon, String label) {
    final isActive = tab == active;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final Color activeColor = isLight ? t.accentText : t.accent;
    final Color color =
        isActive ? activeColor : CorexTokens.textTertiary(context);

    final button = InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onTap(tab),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: 42,
        padding: EdgeInsets.symmetric(horizontal: isActive ? 13 : 0),
        decoration: BoxDecoration(
          color: isActive ? t.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            if (isActive) ...[
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    // With only two tabs, both share the width so the pill doesn't sit hard
    // against one edge of the bar.
    return Expanded(
      child: Semantics(
        label: label,
        selected: isActive,
        child: button,
      ),
    );
  }
}
