import 'package:flutter/material.dart';
import '../utils/display_text.dart';
import 'ui/status_chip.dart';

class PriorityBadge extends StatelessWidget {
  final String priority;
  final bool dense;

  const PriorityBadge({super.key, required this.priority, this.dense = true});

  Color get _color {
    switch (priority) {
      case 'critical':
        return const Color(0xFFEF4444);
      case 'high':
        return const Color(0xFFF59E0B);
      case 'normal':
        return const Color(0xFF0EA5E9);
      default:
        return const Color(0xFF6B7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StatusChip(
      label: titleCaseLabel(priority),
      color: _color,
      dense: dense,
    );
  }
}
