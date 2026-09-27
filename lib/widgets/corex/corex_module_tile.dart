import 'package:flutter/material.dart';

import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import 'corex_card.dart';

/// Workspace tile: icon chip over a label, with an optional count line.
///
/// Laid out left-aligned for a 2-across grid — the old centred icon+label
/// was built for a 3-across strip and leaves too much dead space once the
/// tiles get wider.
class CorexModuleTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool dot;
  final VoidCallback onTap;

  /// Count line under the label ("4 unread"). Omitted when the screen has no
  /// real number to show — never filled with a placeholder.
  final String? subtitle;

  /// Tints the chip and subtitle with the money accent instead of the primary
  /// one, so a grid of four tiles doesn't read as one flat block of colour.
  final bool useMoneyAccent;

  const CorexModuleTile({
    super.key,
    required this.icon,
    required this.label,
    this.dot = false,
    required this.onTap,
    this.subtitle,
    this.useMoneyAccent = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    final isLight = Theme.of(context).brightness == Brightness.light;
    final chipTint = useMoneyAccent ? t.moneySoft : t.accentSoft;

    // Both accents are tuned for dark surfaces — the money gold in
    // particular drops to ~1.7:1 on a light one. The *Text variants darken
    // per agency so the tint still reads without losing the brand hue.
    final Color iconColor = useMoneyAccent
        ? (isLight ? t.moneyText : t.accentMoney)
        : (isLight ? t.accentText : t.accent);
    final Color subtitleColor = dot
        ? (isLight ? t.moneyText : t.accentMoney)
        : CorexTokens.textSecondary(context);

    return CorexCard(
      onTap: onTap,
      radius: CorexTokens.radiusTile,
      padding: const EdgeInsets.all(14),
      // Home sizes these tiles to whatever height is left on the page, so the
      // tile has to survive being squeezed. It sheds in order: the count line
      // first, then the gap, then a couple of px off the chip — rather than
      // overflowing or forcing the grid to scroll.
      child: LayoutBuilder(
        builder: (context, box) {
          // NB: this is the height inside the card's 14 px padding, not the
          // tile's own height — the thresholds are ~28 px below what the grid
          // is told to make each tile.
          final h = box.maxHeight;
          final showSubtitle = subtitle != null && h >= 92;
          final chip = h >= 80 ? 34.0 : 30.0;
          final gap = h >= 80 ? 12.0 : 8.0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: chip,
                    height: chip,
                    decoration: BoxDecoration(
                      color: chipTint,
                      borderRadius:
                          BorderRadius.circular(CorexTokens.radiusChip),
                    ),
                    child: Icon(icon, color: iconColor, size: chip * 0.53),
                  ),
                  const Spacer(),
                  if (dot)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: t.accentMoney,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              SizedBox(height: gap),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CorexTokens.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (showSubtitle) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: subtitleColor,
                    fontSize: 12,
                    fontWeight: dot ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
