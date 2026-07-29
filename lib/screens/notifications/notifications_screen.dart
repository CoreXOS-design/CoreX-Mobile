import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../widgets/ui/content_width.dart';
import '../../models/notification_models.dart';
import '../../providers/notifications_provider.dart';
import '../../services/deep_link_router.dart';
import '../../theme.dart';
import '../../widgets/ui/list_row.dart';
import '../../widgets/ui/section_header.dart';
import 'notification_settings_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationsProvider>().loadFeed();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<NotificationsProvider>();
    final grouped = _groupByPillar(p.items);

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (p.unread > 0)
            TextButton(
              onPressed: () => context.read<NotificationsProvider>().markAllRead(),
              child: const Text('Mark all read',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const NotificationSettingsScreen(),
              ));
            },
          ),
        ],
      ),
      body: ContentSafeArea(
        top: false,
        child: RefreshIndicator(
        color: Theme.of(context).colorScheme.primary,
        onRefresh: () => context.read<NotificationsProvider>().loadFeed(),
        child: p.loadingFeed && p.items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : (p.feedError != null && p.items.isEmpty)
                ? _error(context)
                : p.items.isEmpty
                ? _empty(context)
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      for (final entry in grouped.entries) ...[
                        _PillarHeader(label: _pillarLabel(entry.key)),
                        ...entry.value.map((n) => _NotificationRow(item: n)),
                      ],
                      const SizedBox(height: 32),
                    ],
                  ),
      ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 80),
        EmptyState(
          icon: Icons.notifications_off_outlined,
          title: "You're all caught up",
          subtitle: 'Nothing new to look at right now.',
        ),
      ],
    );
  }

  Widget _error(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        const EmptyState(
          icon: Icons.cloud_off_rounded,
          title: "Couldn't load notifications",
          subtitle: 'Check your connection and try again.',
        ),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton.icon(
            onPressed: () =>
                context.read<NotificationsProvider>().loadFeed(manual: true),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ),
      ],
    );
  }

  /// Group by pillar; within each pillar, overdue first.
  Map<String, List<NotificationItem>> _groupByPillar(List<NotificationItem> items) {
    const pillarOrder = ['property', 'contact', 'deal', 'agent', ''];
    const sevOrder = {'overdue': 0, 'warning': 1, 'info': 2};

    final out = <String, List<NotificationItem>>{};
    for (final n in items) {
      out.putIfAbsent(n.pillar, () => []).add(n);
    }
    for (final list in out.values) {
      list.sort((a, b) {
        final s = (sevOrder[a.severity] ?? 99).compareTo(sevOrder[b.severity] ?? 99);
        if (s != 0) return s;
        return b.createdAt.compareTo(a.createdAt);
      });
    }

    final ordered = <String, List<NotificationItem>>{};
    for (final p in pillarOrder) {
      if (out.containsKey(p)) ordered[p] = out[p]!;
    }
    for (final k in out.keys) {
      ordered.putIfAbsent(k, () => out[k]!);
    }
    return ordered;
  }

  String _pillarLabel(String pillar) {
    switch (pillar) {
      case 'property':
        return 'Properties';
      case 'contact':
        return 'Contacts';
      case 'deal':
        return 'Deals';
      case 'agent':
        return 'My activity';
      default:
        return 'Other';
    }
  }
}

class _PillarHeader extends StatelessWidget {
  final String label;
  const _PillarHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: SectionHeader(label: label),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  final NotificationItem item;
  const _NotificationRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final colour = severityColor(item.severity);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.cardGradient(context),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          boxShadow: AppTheme.softShadow(context),
          border: item.isRead
              ? null
              : Border.all(
                  color: colour.withValues(alpha: 0.5), width: 1.2),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            onTap: () async {
              final p = context.read<NotificationsProvider>();
              await p.markRead(item.id);
              if (!context.mounted) return;
              await DeepLinkRouter.open(context, item.actionUrl);
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colour,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                            color: colour.withValues(alpha: 0.6),
                            blurRadius: 6,
                            spreadRadius: -1),
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
                            Expanded(
                              child: Text(
                                item.title,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: item.isRead
                                      ? FontWeight.w600
                                      : FontWeight.w700,
                                  letterSpacing: -0.1,
                                  color: AppTheme.textPrimary(context),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!item.isRead)
                              Container(
                                margin: const EdgeInsets.only(left: 6, top: 4),
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: colour,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                        color: colour.withValues(alpha: 0.6),
                                        blurRadius: 6,
                                        spreadRadius: -1),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        if (item.body.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            item.body,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: AppTheme.textSecondary(context)),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          _relTime(item.createdAt),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textMuted(context)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _relTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
