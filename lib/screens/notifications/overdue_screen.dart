import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/notification_models.dart';
import '../../providers/notifications_provider.dart';
import '../../services/deep_link_router.dart';
import '../../theme.dart';

/// Pillar-filtered overdue list. Reached from the home overdue widget pills.
class OverdueScreen extends StatelessWidget {
  /// One of `property`, `contact`, `deal`, `task`, or `null` for everything.
  final String? pillarFilter;
  final String title;

  const OverdueScreen({super.key, required this.title, this.pillarFilter});

  @override
  Widget build(BuildContext context) {
    final snap = context.watch<NotificationsProvider>().overdue;
    final items = pillarFilter == null
        ? snap.items
        : snap.items.where((i) => _matches(i, pillarFilter!)).toList()
      ..sort((a, b) => b.ageHours.compareTo(a.ageHours));

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
        color: AppTheme.brand,
        onRefresh: () =>
            context.read<NotificationsProvider>().loadOverdue(),
        child: items.isEmpty
            ? ListView(children: [
                const SizedBox(height: 100),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text(
                      'Nothing overdue here. ✓',
                      style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textSecondary(context)),
                    ),
                  ),
                )
              ])
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _OverdueRow(item: items[i]),
              ),
      ),
      ),
    );
  }

  bool _matches(OverdueItem item, String filter) {
    if (filter == 'task') return item.eventKey.contains('task');
    return item.pillar == filter;
  }
}

class _OverdueRow extends StatelessWidget {
  final OverdueItem item;
  const _OverdueRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final colour = severityColor(item.severity);
    return Material(
      color: AppTheme.surface(context),
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: () => DeepLinkRouter.open(context, item.actionUrl),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: colour.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 36,
                decoration: BoxDecoration(
                    color: colour, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary(context))),
                    if (item.body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(item.body,
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary(context))),
                    ],
                    const SizedBox(height: 5),
                    Text(_age(item.ageHours),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colour)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _age(double hours) {
    if (hours < 1) return 'just now';
    if (hours < 24) return '${hours.toStringAsFixed(0)}h overdue';
    final days = (hours / 24).floor();
    return '$days day${days == 1 ? '' : 's'} overdue';
  }
}
