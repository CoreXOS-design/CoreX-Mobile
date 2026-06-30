import 'package:flutter/material.dart';
import '../models/dashboard_data.dart';
import '../theme.dart';
import 'priority_badge.dart';

class TaskCard extends StatelessWidget {
  final CommandTask task;
  final VoidCallback? onComplete;
  final VoidCallback? onDismiss;
  final VoidCallback? onTap;

  const TaskCard({
    super.key,
    required this.task,
    this.onComplete,
    this.onDismiss,
    this.onTap,
  });

  static const _done = Color(0xFF22C55E);
  static const _skip = Color(0xFF6B7280);
  static const _overdue = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key('task-${task.id}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onComplete?.call();
        } else {
          onDismiss?.call();
        }
        return false;
      },
      background: _swipeBg(
        align: Alignment.centerLeft,
        color: _done,
        icon: Icons.check_rounded,
        label: 'Complete',
        padding: const EdgeInsets.only(left: 20),
      ),
      secondaryBackground: _swipeBg(
        align: Alignment.centerRight,
        color: _skip,
        icon: Icons.block_rounded,
        label: "Didn't happen",
        padding: const EdgeInsets.only(right: 20),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.cardGradient(context),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          boxShadow: AppTheme.softShadow(context),
          border: task.isOverdue
              ? Border.all(color: _overdue.withValues(alpha: 0.45), width: 1)
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Opaque, ~44dp hit target so a tap on/near the circle
                  // completes the task instead of falling through to the
                  // card's open-task InkWell. The visual stays 24dp.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onComplete,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: task.status == 'done'
                                ? _done.withValues(alpha: 0.16)
                                : Colors.transparent,
                            border: Border.all(
                              color: task.isOverdue
                                  ? _overdue
                                  : task.status == 'done'
                                      ? _done
                                      : AppTheme.textMuted(context),
                              width: 2,
                            ),
                          ),
                          child: task.status == 'done'
                              ? const Icon(Icons.check_rounded,
                                  size: 14, color: _done)
                              : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
                            color: AppTheme.textPrimary(context),
                            decoration: task.status == 'done'
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (task.propertyAddress != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            task.propertyAddress!,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      PriorityBadge(priority: task.priority),
                      if (task.dueDate != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _formatDate(task.dueDate!),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: task.isOverdue
                                ? _overdue
                                : AppTheme.textMuted(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _swipeBg({
    required Alignment align,
    required Color color,
    required IconData icon,
    required String label,
    required EdgeInsets padding,
  }) {
    return Container(
      alignment: align,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: align == Alignment.centerLeft
              ? Alignment.centerLeft
              : Alignment.centerRight,
          end: align == Alignment.centerLeft
              ? Alignment.centerRight
              : Alignment.centerLeft,
          colors: [color, color.withValues(alpha: 0.7)],
        ),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]}';
  }
}
