import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../theme/corex_tokens.dart';

/// Standard CoreX redesign page shell: a radial-backlit gradient page with a
/// lightweight transparent header (back button + title + optional actions).
///
/// Mirrors the inline pattern used by [HomeScreen]/[RealEstateHubScreen] so
/// pushed detail screens share the exact same look without re-implementing the
/// gradient + SafeArea + header scaffolding each time.
class CorexScaffold extends StatelessWidget {
  final String title;

  /// Optional pieces shown to the right of the title in the header row.
  final List<Widget> actions;

  /// Whether to show the leading back button. Defaults to true.
  final bool showBack;

  /// The scrollable / primary content. Sits in an [Expanded] below the header.
  final Widget body;

  final Widget? floatingActionButton;

  /// Pinned bar below the body (e.g. a reaction bar). Rendered inside the
  /// SafeArea so it never collides with the system gesture inset.
  final Widget? bottomBar;

  const CorexScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.showBack = true,
    this.floatingActionButton,
    this.bottomBar,
  });

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: CorexTokens.pageBase(context),
        floatingActionButton: floatingActionButton,
        body: Container(
          decoration:
              BoxDecoration(gradient: CorexTokens.pageBacklight(context)),
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(title: title, showBack: showBack, actions: actions),
                Expanded(child: body),
                if (bottomBar != null) bottomBar!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final bool showBack;
  final List<Widget> actions;

  const _Header({
    required this.title,
    required this.showBack,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            if (showBack)
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(TablerIcons.arrow_left,
                    color: CorexTokens.textPrimary(context)),
              )
            else
              const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CorexTokens.textPrimary(context),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            ...actions,
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
