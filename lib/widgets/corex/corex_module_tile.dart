import 'package:flutter/material.dart';

import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import 'corex_card.dart';

class CorexModuleTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool dot;
  final VoidCallback onTap;

  const CorexModuleTile({
    super.key,
    required this.icon,
    required this.label,
    this.dot = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    return CorexCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      child: Center(
        child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: t.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: t.accent, size: 22),
              ),
              if (dot)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: t.accentMoney,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: CorexTokens.surfaceBase(context), width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: CorexTokens.textPrimary(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      ),
    );
  }
}
