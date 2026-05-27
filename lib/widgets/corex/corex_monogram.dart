import 'package:flutter/material.dart';

import '../../theme/corex_accent_theme.dart';

class CorexMonogram extends StatelessWidget {
  final double size;
  const CorexMonogram({super.key, this.size = 112});

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    final radius = BorderRadius.circular(size * 0.28);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: t.accentGlow,
            blurRadius: 32,
            spreadRadius: -2,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.16),
        child: Image.asset(
          'assets/images/corex_logo.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
