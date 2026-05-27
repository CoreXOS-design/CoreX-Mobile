import 'package:flutter/material.dart';

import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';

class CorexPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? leading;
  final bool loading;

  const CorexPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.leading,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = CorexAccentTheme.of(context);
    final radius = BorderRadius.circular(CorexTokens.radiusButton);
    final enabled = onPressed != null && !loading;

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: enabled ? onPressed : null,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(theme.accent, Colors.white, 0.08)!,
                  Color.lerp(theme.accent, Colors.black, 0.08)!,
                ],
              ),
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: theme.accentGlow,
                  offset: const Offset(0, 12),
                  blurRadius: 28,
                  spreadRadius: -10,
                ),
              ],
            ),
            child: Stack(
              children: [
                SizedBox(
                  height: 56,
                  child: Center(
                    child: loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (leading != null) ...[
                                Icon(leading, size: 18, color: Colors.white),
                                const SizedBox(width: 10),
                              ],
                              Text(
                                label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
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
