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
  Widget target;
  switch (tab) {
    case CorexNavTab.home:
      Navigator.of(context).pushAndRemoveUntil(
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
      // Profile has no bottom nav of its own, so open it as a pushed page
      // on top of the current screen — same behaviour as the home-screen
      // avatar — instead of replacing the tab and stranding the user.
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      );
      return;
  }
  Navigator.of(context).pushReplacement(corexTabRoute(target));
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
                  _item(context, t, CorexNavTab.home, TablerIcons.home_2, 'Home'),
                  _item(context, t, CorexNavTab.today, TablerIcons.calendar_event,
                      'Today'),
                  _item(context, t, CorexNavTab.calendar, TablerIcons.calendar,
                      'Calendar'),
                  _item(context, t, CorexNavTab.ellie, TablerIcons.sparkles,
                      'Ellie'),
                  _item(context, t, CorexNavTab.me, TablerIcons.user_circle, 'Me'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, CorexAccentTheme t, CorexNavTab tab,
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
