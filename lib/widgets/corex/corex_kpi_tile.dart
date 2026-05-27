import 'package:flutter/material.dart';

import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import 'corex_card.dart';

class CorexKpiTile extends StatelessWidget {
  final String label;
  final String value;
  final String? delta;
  final bool money;

  const CorexKpiTile({
    super.key,
    required this.label,
    required this.value,
    this.delta,
    this.money = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    final valueStyle = TextStyle(
      color: money ? t.accentMoney : CorexTokens.textPrimary(context),
      fontWeight: FontWeight.w700,
      fontSize: 20,
      letterSpacing: -0.3,
      shadows: money ? [Shadow(color: t.moneyGlow, blurRadius: 10)] : null,
    );

    return CorexCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: CorexTokens.textTertiary(context),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: valueStyle),
          ),
          if (delta != null) ...[
            const SizedBox(height: 4),
            Text(
              delta!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: CorexTokens.successDelta,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
