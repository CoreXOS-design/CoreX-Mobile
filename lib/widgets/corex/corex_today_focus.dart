import 'package:flutter/material.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import 'corex_card.dart';
import 'corex_chip.dart';

class CorexTodayFocus extends StatelessWidget {
  final String? thumbnailUrl;
  final String address;
  final List<String> chips;
  final VoidCallback? onTap;

  const CorexTodayFocus({
    super.key,
    this.thumbnailUrl,
    required this.address,
    this.chips = const [],
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    return CorexCard(
      accent: true,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: t.accentSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: thumbnailUrl == null
                ? Icon(TablerIcons.home_2, color: t.accent, size: 26)
                : Image.network(
                    thumbnailUrl!,
                    fit: BoxFit.cover,
                    width: 64,
                    height: 64,
                    // Fall back to the placeholder icon if the thumbnail fails
                    // to load, rather than showing a blank accent box.
                    errorBuilder: (_, __, ___) =>
                        Icon(TablerIcons.home_2, color: t.accent, size: 26),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'TODAY’S FOCUS',
                  style: TextStyle(
                    color: CorexTokens.textTertiary(context),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CorexTokens.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in chips) CorexChip(label: c),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
