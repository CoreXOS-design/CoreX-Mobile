import 'package:flutter/material.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../screens/client/client_home_screen.dart';
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
      Navigator.of(context).pushAndRemoveUntil(
        corexTabRoute(const ClientHomeScreen()),
        (route) => false,
      );
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
    final radius = BorderRadius.circular(20);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ClipRRect(
          borderRadius: radius,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: CorexTokens.surfaceGradient(context),
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.40),
                  offset: const Offset(0, 10),
                  blurRadius: 24,
                  spreadRadius: -8,
                ),
              ],
            ),
            child: SizedBox(
              height: 64,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
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
    );
  }

  Widget _item(BuildContext context, CorexAccentTheme t, ClientNavTab tab,
      IconData icon, String label) {
    final isActive = tab == active;
    final color = isActive ? t.accent : CorexTokens.textTertiary(context);
    return Expanded(
      child: InkWell(
        onTap: () => onTap(tab),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
