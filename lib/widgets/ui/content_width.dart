import 'package:flutter/material.dart';

/// Caps and centres page content on wide viewports.
///
/// Every CoreX layout was drawn as a phone column. On an iPad — especially
/// landscape at ~1180pt — an unconstrained column stretches body text and form
/// fields the full width of the screen, which reads as broken rather than
/// adaptive. This keeps the measure readable and leaves the gradient page
/// background running edge to edge behind it.
///
/// It must centre via [Center]/[Align]. A bare [ConstrainedBox] is a no-op
/// here: scroll views hand down a *tight* cross-axis width, and
/// `BoxConstraints.enforce` refuses to shrink below the incoming minWidth, so
/// the cap is silently discarded.
class ContentWidth extends StatelessWidget {
  /// Comfortable measure for a single column of content.
  static const double page = 720;

  /// Narrower cap for forms and auth flows, where full-width inputs look wrong
  /// well before 720pt.
  static const double formWidth = 480;

  final Widget child;
  final double maxWidth;

  const ContentWidth({super.key, required this.child, this.maxWidth = page});

  const ContentWidth.form({super.key, required this.child})
      : maxWidth = formWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// [SafeArea] + [ContentWidth]: the standard CoreX page inset.
///
/// Drop-in replacement for the `SafeArea` inside a gradient page shell, so the
/// backlight still bleeds to the screen edges while the content keeps a
/// phone-width measure on a tablet.
class ContentSafeArea extends StatelessWidget {
  final Widget child;
  final bool top;
  final bool bottom;
  final double maxWidth;

  const ContentSafeArea({
    super.key,
    required this.child,
    this.top = true,
    this.bottom = true,
    this.maxWidth = ContentWidth.page,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: top,
      bottom: bottom,
      child: ContentWidth(maxWidth: maxWidth, child: child),
    );
  }
}
