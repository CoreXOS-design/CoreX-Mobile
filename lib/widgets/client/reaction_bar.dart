import 'package:flutter/material.dart';

import '../../screens/core_matches/core_matches_common.dart';
import '../../theme/corex_tokens.dart';

typedef ReactionPicked = void Function(String reaction);

class ReactionBar extends StatelessWidget {
  final String? current;
  final ReactionPicked onInterested;
  final ReactionPicked onSaved;
  final ReactionPicked onNotForMe;
  final EdgeInsetsGeometry padding;
  final bool dense;

  const ReactionBar({
    super.key,
    required this.current,
    required this.onInterested,
    required this.onSaved,
    required this.onNotForMe,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _btn(context,
              icon: Icons.favorite_rounded,
              color: kReactionInterested,
              label: 'Interested',
              active: current == 'interested',
              onTap: () => onInterested('interested')),
          _btn(context,
              icon: Icons.star_rounded,
              color: kReactionSaved,
              label: 'Saved',
              active: current == 'saved',
              onTap: () => onSaved('saved')),
          _btn(context,
              icon: Icons.close_rounded,
              color: kReactionNotInterested,
              label: 'Not for me',
              active: current == 'not_interested',
              onTap: () => onNotForMe('not_interested')),
        ],
      ),
    );
  }

  Widget _btn(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final bg = active ? color.withValues(alpha: 0.12) : Colors.transparent;
    final fg = active ? color : CorexTokens.textSecondary(context);
    return Expanded(
      child: SizedBox(
        height: dense ? 44 : 56,
        child: InkWell(
          borderRadius: BorderRadius.circular(CorexTokens.radius),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: 6, vertical: dense ? 6 : 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(CorexTokens.radius),
              border: Border.all(
                color: active
                    ? color
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: dense ? 18 : 20, color: fg),
                if (!dense) const SizedBox(height: 2),
                if (!dense)
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget reactionPill(BuildContext context, String? reaction) {
  if (reaction == null) return const SizedBox.shrink();
  late IconData icon;
  late Color color;
  switch (reaction) {
    case 'interested':
      icon = Icons.favorite_rounded;
      color = kReactionInterested;
      break;
    case 'saved':
      icon = Icons.star_rounded;
      color = kReactionSaved;
      break;
    case 'not_interested':
      icon = Icons.close_rounded;
      color = kReactionNotInterested;
      break;
    default:
      return const SizedBox.shrink();
  }
  return Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.18),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, size: 14, color: color),
  );
}
