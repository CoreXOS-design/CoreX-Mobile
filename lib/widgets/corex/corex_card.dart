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

  /// Corner radius. Defaults to the card radius; tiles pass the smaller
  /// [CorexTokens.radiusTile] so a grid of them doesn't read as over-rounded.
  final double? radius;

  /// Deepens the soft shadow. For the one hero card on a screen, not for
  /// everything — the depth only reads if most cards sit lower.
  final bool elevated;

  const CorexCard({
    super.key,
    required this.child,
    this.accent = false,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.radius,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = CorexAccentTheme.of(context);
    final r = radius ?? CorexTokens.radiusCard;
    final borderRadius = BorderRadius.circular(r);

    // The hairline is what actually defines the card edge in dark mode, so
    // it's no longer light-mode-only the way it was.
    final Border edge = accent
        ? Border(left: BorderSide(color: theme.accent, width: 2))
        : Border.all(color: CorexTokens.surfaceBorder(context));

    final surface = BoxDecoration(
      gradient: CorexTokens.surfaceGradient(context),
      borderRadius: borderRadius,
      border: edge,
    );

    // Shadows have to live OUTSIDE the ClipRRect. Painted on the clipped box
    // they fall entirely outside its bounds and get cut away — which is why
    // this card has never actually cast one.
    final shadow = BoxDecoration(
      borderRadius: borderRadius,
      boxShadow: [
        if (accent)
          BoxShadow(
            color: theme.accentGlow,
            offset: const Offset(-10, 0),
            blurRadius: 24,
            spreadRadius: -10,
          ),
        ...CorexTokens.cardShadow(context, strong: elevated),
      ],
    );

    // The 1 px inner top highlight that used to sit here is gone: the card
    // now carries a hairline border on all four sides, and the two together
    // read as a double line along the top edge.
    Widget body = Padding(padding: padding, child: child);

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

    return DecoratedBox(
      decoration: shadow,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: DecoratedBox(decoration: surface, child: body),
      ),
    );
  }
}
