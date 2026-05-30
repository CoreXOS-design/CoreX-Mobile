import 'package:flutter/material.dart';
import 'package:tabler_icons/tabler_icons.dart';

/// System "AI" marker. Purple regardless of agency branding — it's a
/// system signal, matching the web <x-ai-badge /> aesthetic.
class AiBadge extends StatelessWidget {
  final double scale;
  final String label;
  const AiBadge({super.key, this.scale = 1.0, this.label = 'AI'});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? const Color(0xFF3B1E63).withValues(alpha: 0.85)
        : const Color(0xFFEDE4FB);
    final fg = isDark ? const Color(0xFFC9B6F5) : const Color(0xFF5B2BB5);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 6 * scale,
        vertical: 2 * scale,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.35), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(TablerIcons.robot, size: 11 * scale, color: fg),
          SizedBox(width: 3 * scale),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 10 * scale,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// 0..4 filled dots indicating model confidence (the spec calls these "pips").
class ConfidencePips extends StatelessWidget {
  final double confidence; // 0.0..1.0
  const ConfidencePips({super.key, required this.confidence});

  @override
  Widget build(BuildContext context) {
    final filled = (confidence.clamp(0.0, 1.0) * 4).round();
    final on = Theme.of(context).colorScheme.primary;
    final off = Theme.of(context).dividerColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (i) {
        return Container(
          margin: EdgeInsets.only(right: i == 3 ? 0 : 2),
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: i < filled ? on : off,
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }
}
