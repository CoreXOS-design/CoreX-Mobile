import 'package:flutter/material.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';

class CorexEllieTeaser extends StatelessWidget {
  final VoidCallback onTap;
  const CorexEllieTeaser({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    final radius = BorderRadius.circular(CorexTokens.radius);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: CorexTokens.surfaceGradient(context),
            borderRadius: radius,
            border: Border.all(color: t.accentSoft),
            boxShadow: [
              BoxShadow(color: t.accentGlow, blurRadius: 28),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
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
        ),
      ),
    );
  }
}
