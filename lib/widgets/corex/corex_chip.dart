import 'package:flutter/material.dart';

import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';

enum CorexChipVariant { accent, money, neutral }

class CorexChip extends StatelessWidget {
  final String label;
  final CorexChipVariant variant;

  const CorexChip({
    super.key,
    required this.label,
    this.variant = CorexChipVariant.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    Color bg;
    Color fg;
    switch (variant) {
      case CorexChipVariant.accent:
        bg = t.accentSoft;
        fg = t.accent;
        break;
      case CorexChipVariant.money:
        bg = t.moneySoft;
        fg = t.accentMoney;
        break;
      case CorexChipVariant.neutral:
        bg = Colors.white.withValues(alpha: 0.06);
        fg = CorexTokens.textSecondary(context);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
