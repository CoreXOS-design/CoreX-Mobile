import 'package:flutter/material.dart';
import '../models/branding.dart';
import '../models/dashboard_data.dart';
import '../theme.dart';
import '../utils/app_time.dart';
import 'priority_badge.dart';

class EventCard extends StatelessWidget {
  final CalendarEvent event;
  final VoidCallback? onComplete;
  final VoidCallback? onTap;

  const EventCard({super.key, required this.event, this.onComplete, this.onTap});

  Color get _colour {
    try {
      return Color(int.parse(event.colour.replaceFirst('#', '0xFF')));
    } catch (_) {
      return const Color(0xFF6B7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    return Dismissible(
      key: Key('event-${event.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onComplete?.call();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [Color(0xFF22C55E), Color(0xCC22C55E)],
          ),
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_rounded, color: Colors.white, size: 22),
            SizedBox(height: 2),
            Text('Complete',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                )),
          ],
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.cardGradient(context),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          boxShadow: AppTheme.softShadow(context),
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
                  Container(
                    width: 3,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _colour,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: _colour.withValues(alpha: 0.6),
                          blurRadius: 6,
                          spreadRadius: -1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              event.allDay
                                  ? 'All day'
                                  : _formatTime(jhb(event.eventDate)),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: brand.button,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: _colour.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                event.eventType[0].toUpperCase() +
                                    event.eventType.substring(1),
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: _colour),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          event.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
                            color: AppTheme.textPrimary(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (event.propertyAddress != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            event.propertyAddress!,
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
                  if (event.priority == 'high' ||
                      event.priority == 'critical') ...[
                    const SizedBox(width: 8),
                    PriorityBadge(priority: event.priority),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    // Stored times are UTC; show them in the device's local timezone.
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
