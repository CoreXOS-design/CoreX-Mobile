import 'package:flutter/material.dart';

import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';

/// Surface card with the CoreX gradient + 1 px inner top highlight + seat
/// shadow. When [accent] is true, adds a left accent border and a leftward
/// accent halo.
class CorexCard extends StatelessWidget {
  final Widget child;
  final bool accent;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const CorexCard({
    super.key,
    required this.child,
    this.accent = false,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = CorexAccentTheme.of(context);
    final borderRadius = BorderRadius.circular(CorexTokens.radius);
    final isLight = Theme.of(context).brightness == Brightness.light;

    final Border? edge = accent
        ? Border(left: BorderSide(color: theme.accent, width: 2))
        : (isLight
            ? Border.all(color: Colors.black.withValues(alpha: 0.08))
            : null);

    final decoration = BoxDecoration(
      gradient: CorexTokens.surfaceGradient(context),
      borderRadius: borderRadius,
      border: edge,
      boxShadow: [
        if (accent)
          BoxShadow(
            color: theme.accentGlow,
            offset: const Offset(-10, 0),
            blurRadius: 24,
            spreadRadius: -10,
          ),
        BoxShadow(
          color: Colors.black
              .withValues(alpha: isLight ? 0.06 : 0.30),
          offset: Offset(0, isLight ? 2 : 1),
          blurRadius: isLight ? 6 : 0,
        ),
      ],
    );

    Widget body = Stack(
      children: [
        Padding(padding: padding, child: child),
        Positioned(
          top: 0,
          left: accent ? 2 : 0,
          right: 0,
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              color: (isLight ? Colors.white : Colors.white)
                  .withValues(alpha: isLight ? 0.0 : 0.05),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(accent ? 0 : CorexTokens.radius),
                topRight: const Radius.circular(CorexTokens.radius),
              ),
            ),
          ),
        ),
      ],
    );

    if (onTap != null) {
      body = Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          child: body,
        ),
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: DecoratedBox(decoration: decoration, child: body),
    );
  }
}
