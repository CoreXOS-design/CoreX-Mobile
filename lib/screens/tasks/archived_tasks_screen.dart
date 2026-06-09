import 'package:flutter/material.dart';
import '../../models/dashboard_data.dart';
import '../../services/api_service.dart';
import '../../theme.dart';

/// Soft-deleted tasks, pre-grouped server-side by the day they were archived
/// (`deleted_at`). Each row has a Restore action that calls
/// `POST /command-center/tasks/{id}/restore` — the task is then returned to
/// the Done column on the main board.
///
/// Loaded lazily when the user opens the screen; not held in any provider.
/// Re-fetched after every restore so the grouping stays accurate.
class ArchivedTasksScreen extends StatefulWidget {
  const ArchivedTasksScreen({super.key});

  @override
  State<ArchivedTasksScreen> createState() => _ArchivedTasksScreenState();
}

class _ArchivedTasksScreenState extends State<ArchivedTasksScreen> {
  final _api = ApiService();
  ArchivedTasksData? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.getArchivedTasks();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load archived tasks';
        _loading = false;
      });
    }
  }

  Future<void> _restore(int taskId) async {
    try {
      await _api.restoreTask(taskId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task restored')),
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restore failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: Text('Archived${data != null ? ' · ${data.total}' : ''}'),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: AppTheme.brand,
          onRefresh: _load,
          child: _body(data),
        ),
      ),
    );
  }

  Widget _body(ArchivedTasksData? data) {
    if (_loading && data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && data == null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(child: Text(_error!)),
        ],
      );
    }
    if (data == null || data.groups.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Text(
              'Nothing archived.',
              style: TextStyle(color: AppTheme.textMuted(context)),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: data.groups.length,
      itemBuilder: (context, gi) {
        final group = data.groups[gi];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
              child: Text(
                _formatGroupDate(group.date),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            ),
            ...group.tasks.map((t) => _TaskRow(task: t, onRestore: () => _restore(t.id))),
          ],
        );
      },
    );
  }

  String _formatGroupDate(DateTime dt) {
    final today = DateTime.now();
    final isToday =
        dt.year == today.year && dt.month == today.month && dt.day == today.day;
    final y = today.subtract(const Duration(days: 1));
    final isYesterday = dt.year == y.year && dt.month == y.month && dt.day == y.day;
    if (isToday) return 'Today';
    if (isYesterday) return 'Yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

class _TaskRow extends StatelessWidget {
  final CommandTask task;
  final VoidCallback onRestore;
  const _TaskRow({required this.task, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                if ((task.contactName ?? task.propertyAddress) != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    task.contactName ?? task.propertyAddress!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context)),
                  ),
                ],
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onRestore,
            icon: const Icon(Icons.restore, size: 18),
            label: const Text('Restore'),
          ),
        ],
      ),
    );
  }
}
