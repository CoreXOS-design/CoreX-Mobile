import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/notification_models.dart';
import '../providers/notifications_provider.dart';
import '../screens/notifications/overdue_screen.dart';
import '../theme.dart';

/// Compact "Overdue" strip for the Today screen — four pill buttons that
/// drill into a pillar-filtered overdue list. Hides itself entirely when
/// there's nothing overdue.
class OverdueWidget extends StatefulWidget {
  const OverdueWidget({super.key});

  @override
  State<OverdueWidget> createState() => _OverdueWidgetState();
}

class _OverdueWidgetState extends State<OverdueWidget> {
  static const _red = Color(0xFFEF4444);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NotificationsProvider>().loadOverdue();
    });
  }

  @override
  Widget build(BuildContext context) {
    final counts = context
        .select<NotificationsProvider, OverdueCounts>((p) => p.overdue.counts);

    if (counts.total == 0) return const SizedBox.shrink();

    final dark = AppTheme.isDark(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [
                  Color.lerp(AppTheme.darkSurface, _red, 0.18)!,
                  AppTheme.darkSurface,
                ]
              : [
                  _red.withValues(alpha: 0.08),
                  AppTheme.lightSurface,
                ],
        ),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: AppTheme.softShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: _red.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(Icons.error_outline_rounded,
                    size: 14, color: _red),
              ),
              const SizedBox(width: 8),
              Text('${counts.total} overdue',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                      color: _red)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pill(context, 'Properties', counts.properties, 'property'),
              _pill(context, 'Contacts', counts.contacts, 'contact'),
              _pill(context, 'Deals', counts.deals, 'deal'),
              _pill(context, 'Tasks', counts.tasks, 'task'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, String label, int count, String filter) {
    if (count == 0) return const SizedBox.shrink();
    return Material(
      color: AppTheme.surface(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) =>
                OverdueScreen(title: '$label overdue', pillarFilter: filter),
          ));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _red.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary(context))),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: _red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$count',
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
