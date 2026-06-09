import 'package:flutter/material.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../data/ellie_daily_quotes.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import 'corex_card.dart';

/// Home-screen Ellie card: the "Meet Ellie" intro and Ellie's short daily line
/// of inspiration combined into one tappable card. The daily line is chosen
/// deterministically by calendar day, cycling every 100 days.
class CorexEllieCard extends StatelessWidget {
  final VoidCallback onTap;

  /// Overridable for testing; defaults to today.
  final DateTime? date;

  const CorexEllieCard({super.key, required this.onTap, this.date});

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    final quote = EllieDailyQuotes.forDate(date ?? DateTime.now());

    return CorexCard(
      accent: true,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: t.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(TablerIcons.sparkles, color: t.accent, size: 22),
              ),
              const SizedBox(width: 14),
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
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, thickness: 1, color: t.accentSoft),
          const SizedBox(height: 14),
          Text(
            quote,
            style: TextStyle(
              color: CorexTokens.textPrimary(context),
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ELLIE · DAILY',
            style: TextStyle(
              color: t.accent,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
