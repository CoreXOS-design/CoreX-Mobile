import 'package:flutter/material.dart';

import '../../theme/corex_tokens.dart';

class CorexSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? leading;

  const CorexSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(CorexTokens.radiusButton);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onPressed,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: radius,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Stack(
            children: [
              SizedBox(
                height: 52,
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (leading != null) ...[
                        Icon(leading,
                            size: 18, color: CorexTokens.textSecondary(context)),
                        const SizedBox(width: 10),
                      ],
                      Text(
                        label,
                        style: TextStyle(
                          color: CorexTokens.textPrimary(context),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
