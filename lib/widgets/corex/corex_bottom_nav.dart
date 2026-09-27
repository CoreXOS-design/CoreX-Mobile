import 'package:flutter/material.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../screens/calendar_screen.dart';
import '../../screens/ellie/ellie_screen.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/profile_screen.dart';
import '../../screens/today/today_screen.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';

enum CorexNavTab { home, today, calendar, ellie, me }

/// Shared bottom-nav navigation. Replaces the current screen with the
/// destination so the nav always sits at the bottom. Tapping the active
/// tab is a no-op.
/// Fade-through route used by the bottom nav so tab switches cross-dissolve
/// instead of the harsh platform default slide.
PageRouteBuilder<T> corexTabRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

void corexNavigateTo(BuildContext context, CorexNavTab tab, CorexNavTab from) {
  if (tab == from) return;
  final nav = Navigator.of(context);
  // Me is pushed on top of the current tab (see below) rather than replacing
  // it, so leaving it pops that overlay first — otherwise the profile route
  // would linger underneath the new tab and Back would land back on it.
  if (from == CorexNavTab.me && nav.canPop()) nav.pop();
  Widget target;
  switch (tab) {
    case CorexNavTab.home:
      nav.pushAndRemoveUntil(
        corexTabRoute(const HomeScreen()),
        (route) => false,
      );
      return;
    case CorexNavTab.today:
      target = const TodayScreen();
      break;
    case CorexNavTab.calendar:
      target = const CalendarScreen();
      break;
    case CorexNavTab.ellie:
      target = const EllieScreen();
      break;
    case CorexNavTab.me:
      // Pushed on top of the current screen instead of replacing it, so
      // sign-out still has a live route underneath to fall back to. It carries
      // the bottom nav itself (showNav) so the bar never disappears.
      nav.push(
        corexTabRoute(const ProfileScreen(showNav: true)),
      );
      return;
  }
  nav.pushReplacement(corexTabRoute(target));
}

class CorexBottomNav extends StatelessWidget {
  final CorexNavTab active;
  final ValueChanged<CorexNavTab> onTap;

  const CorexBottomNav({
    super.key,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    final radius = BorderRadius.circular(CorexTokens.radiusNav);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: DecoratedBox(
          // Shadow sits on its own layer so the Material below can clip the
          // ripples without also clipping the shadow away.
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
                    _item(context, t, CorexNavTab.home, TablerIcons.home_2,
                        'Home'),
                    _item(context, t, CorexNavTab.today,
                        TablerIcons.calendar_event, 'Today'),
                    _item(context, t, CorexNavTab.calendar,
                        TablerIcons.calendar, 'Calendar'),
                    _item(context, t, CorexNavTab.ellie, TablerIcons.sparkles,
                        'Ellie'),
                    _item(context, t, CorexNavTab.me, TablerIcons.user_circle,
                        'Me'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Only the active tab is labelled — it expands into a tinted pill and the
  /// rest collapse to icons. Labelling all five at 10 px was the old
  /// compromise; this way the one that matters is legible.
  Widget _item(BuildContext context, CorexAccentTheme t, CorexNavTab tab,
      IconData icon, String label) {
    final isActive = tab == active;
    final isLight = Theme.of(context).brightness == Brightness.light;

    // The accent is tuned for dark surfaces; on the light card it needs
    // darkening to stay legible. [accentText] does that per agency rather
    // than swapping in a fixed colour, so tenant branding survives.
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

    // The active pill is sized to its label; the others share what's left, so
    // the bar doesn't reflow as you move between tabs with longer names.
    return isActive
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Semantics(selected: true, child: button),
          )
        : Expanded(
            child: Semantics(
              label: label,
              selected: false,
              child: button,
            ),
          );
  }
}
