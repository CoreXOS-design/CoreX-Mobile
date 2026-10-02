import 'package:flutter/material.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';

/// Home header shared by the agent and client Home screens: a row of boxed
/// icon buttons (menu on the left, [actions] on the right), then the agency
/// eyebrow and the greeting on their own row.
///
/// Two rows, not one. Sharing a row with three 42 px buttons left the
/// greeting about 170 px, so `Good afternoon, <name>` ellipsised mid-name —
/// the one word on the screen that has to survive. On its own row it has the
/// full width, and a long name still gets FittedBox as a backstop.
class CorexHomeHeader extends StatelessWidget {
  final String? agencyName;
  final String greeting;
  final VoidCallback onMenuTap;

  /// Right-aligned [CorexHeaderButton]s, left to right.
  final List<Widget> actions;

  const CorexHomeHeader({
    super.key,
    required this.agencyName,
    required this.greeting,
    required this.onMenuTap,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CorexHeaderButton(
              icon: TablerIcons.menu_2,
              tooltip: 'Menu',
              onTap: onMenuTap,
            ),
            const Spacer(),
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              actions[i],
            ],
          ],
        ),
        const SizedBox(height: 14),
        if (agencyName != null && agencyName!.isNotEmpty) ...[
          Text(
            agencyName!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: CorexTokens.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
        ],
        // Scales down instead of clipping when the name is long or the user
        // has a large text scale; it never grows past the set size.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            greeting,
            maxLines: 1,
            style: TextStyle(
              color: CorexTokens.textPrimary(context),
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// 42 px boxed icon button — the header's answer to Studio's card language.
/// [label] (e.g. initials) replaces the icon for an identity button.
class CorexHeaderButton extends StatelessWidget {
  final IconData? icon;
  final String? label;
  final String tooltip;
  final int badge;
  final VoidCallback onTap;

  const CorexHeaderButton({
    super.key,
    this.icon,
    this.label,
    required this.tooltip,
    required this.onTap,
    this.badge = 0,
  }) : assert(icon != null || label != null, 'icon or label required');

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    final isLight = Theme.of(context).brightness == Brightness.light;
    final radius = BorderRadius.circular(13);

    return Semantics(
      button: true,
      label: badge > 0 ? '$tooltip, $badge unread' : tooltip,
      child: Tooltip(
        message: tooltip,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: CorexTokens.surfaceGradient(context),
                borderRadius: radius,
                border: Border.all(color: CorexTokens.surfaceBorder(context)),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: radius,
                child: InkWell(
                  borderRadius: radius,
                  onTap: onTap,
                  child: SizedBox(
                    width: 42,
                    height: 42,
                    child: icon != null
                        ? Icon(
                            icon,
                            size: 19,
                            color: CorexTokens.textPrimary(context),
                          )
                        : Center(
                            child: Text(
                              label!,
                              style: TextStyle(
                                color: isLight ? t.accentText : t.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
            if (badge > 0)
              Positioned(
                top: -5,
                right: -5,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: t.accentMoney,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      // Deliberately not capped at "9+" — the cockpit rules
                      // ban that badge; a real number or nothing.
                      '$badge',
                      style: TextStyle(
                        // Picked from the fill's luminance, so a dark agency
                        // "money" colour still gets legible digits.
                        color: t.onMoney,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
