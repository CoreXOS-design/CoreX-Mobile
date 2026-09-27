import 'package:flutter/material.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../data/ellie_daily_quotes.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import 'corex_card.dart';

/// Home-screen Ellie card: the "Meet Ellie" intro and Ellie's short daily line
/// of inspiration combined into one tappable card. The daily line is chosen
/// deterministically by calendar day, cycling every 100 days.
///
/// AI is available to every agency, so the "Meet Ellie" intro and tap-through
/// are always shown.
class CorexEllieCard extends StatelessWidget {
  final VoidCallback onTap;

  /// Overridable for testing; defaults to today.
  final DateTime? date;

  const CorexEllieCard({
    super.key,
    required this.onTap,
    this.date,
  });

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    final quote = EllieDailyQuotes.forDate(date ?? DateTime.now());

    final isLight = Theme.of(context).brightness == Brightness.light;
    // Pale gold reads as a glyph on the dark surface but collapses to ~1.7:1
    // on the light one, so light mode uses the darkened per-agency variant.
    final onGold = isLight ? t.moneyText : t.accentMoney;

    return CorexCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: t.moneySoft,
                  borderRadius: BorderRadius.circular(CorexTokens.radiusChip),
                ),
                child: Icon(TablerIcons.sparkles, color: onGold, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Meet Ellie',
                      style: TextStyle(
                        color: CorexTokens.textPrimary(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your AI assistant for CoreX',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: CorexTokens.textSecondary(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                TablerIcons.chevron_right,
                size: 17,
                color: CorexTokens.textTertiary(context),
              ),
            ],
          ),
          const SizedBox(height: 13),
          // The quote sits in its own well rather than running on under a
          // divider — it's Ellie speaking, not more card copy.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isLight
                  ? CorexTokens.surfaceBase(context)
                  : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(13),
              border: isLight
                  ? Border.all(color: CorexTokens.surfaceBorder(context))
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ELLIE · DAILY',
                  style: TextStyle(
                    color: onGold,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  quote,
                  style: TextStyle(
                    color: CorexTokens.textPrimary(context),
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
