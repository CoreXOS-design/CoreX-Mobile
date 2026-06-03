import 'package:flutter/material.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../models/client_models.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../corex/corex_card.dart';
import 'reaction_bar.dart';

class ClientPropertyCard extends StatelessWidget {
  final ClientMatchResult result;
  final VoidCallback onTap;
  final void Function(String reaction) onReact;

  const ClientPropertyCard({
    super.key,
    required this.result,
    required this.onTap,
    required this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    final price = result.priceDisplay ??
        (result.price != null ? 'R ${_money(result.price!)}' : null);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CorexCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image with overlays.
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (result.thumbnail != null && result.thumbnail!.isNotEmpty)
                    Image.network(
                      result.thumbnail!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: CorexTokens.surfaceTop(context),
                        child: Icon(TablerIcons.photo_off,
                            color: CorexTokens.textTertiary(context)),
                      ),
                    )
                  else
                    Container(
                      color: CorexTokens.surfaceTop(context),
                      child: Icon(TablerIcons.home,
                          color: CorexTokens.textTertiary(context), size: 36),
                    ),
                  if (result.matchScore != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${result.matchScore}% match',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  if (result.reaction != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: reactionPill(context, result.reaction),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (price != null)
                    Text(
                      price,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: t.accentMoney,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    result.address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: CorexTokens.textPrimary(context),
                    ),
                  ),
                  if (result.suburb != null && result.suburb!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        result.suburb!,
                        style: TextStyle(
                          fontSize: 12,
                          color: CorexTokens.textSecondary(context),
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (result.beds != null) ...[
                        Icon(TablerIcons.bed,
                            size: 14,
                            color: CorexTokens.textSecondary(context)),
                        const SizedBox(width: 2),
                        Text('${result.beds}',
                            style: TextStyle(
                                fontSize: 12,
                                color: CorexTokens.textPrimary(context))),
                        const SizedBox(width: 10),
                      ],
                      if (result.baths != null) ...[
                        Icon(TablerIcons.bath,
                            size: 14,
                            color: CorexTokens.textSecondary(context)),
                        const SizedBox(width: 2),
                        Text('${result.baths}',
                            style: TextStyle(
                                fontSize: 12,
                                color: CorexTokens.textPrimary(context))),
                        const SizedBox(width: 10),
                      ],
                      if (result.garages != null) ...[
                        Icon(TablerIcons.car,
                            size: 14,
                            color: CorexTokens.textSecondary(context)),
                        const SizedBox(width: 2),
                        Text('${result.garages}',
                            style: TextStyle(
                                fontSize: 12,
                                color: CorexTokens.textPrimary(context))),
                      ],
                    ],
                  ),
                  if (result.reaction == 'not_interested' &&
                      result.reactionNote != null &&
                      result.reactionNote!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        result.reactionNote!,
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: CorexTokens.textTertiary(context),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            ReactionBar(
              current: result.reaction,
              onInterested: onReact,
              onSaved: onReact,
              onNotForMe: onReact,
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              dense: true,
            ),
          ],
        ),
      ),
    );
  }

  static String _money(num n) {
    final s = n.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      buf.write(s[i]);
      if (fromEnd > 1 && (fromEnd - 1) % 3 == 0) buf.write(' ');
    }
    return buf.toString();
  }
}
