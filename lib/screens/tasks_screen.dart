import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/dashboard_provider.dart';
import '../models/dashboard_data.dart';
import '../services/api_service.dart';
import '../widgets/task_card.dart';
import 'shared/quick_add_sheet.dart';
import 'tasks/task_detail_screen.dart';

/// Tasks screen — spec-compliant kanban grouped by status (To Do →
/// In Progress → Done). Drag a card to another column to fire
/// `PATCH /command-center/tasks/{id}/status` with optimistic update.
/// Secondary tab swaps Active / Archived. Long-press on a card still
/// surfaces a "Move to" sheet for users who can't drag (accessibility).
class TasksScreen extends StatefulWidget {
  final bool embedded;
  const TasksScreen({super.key, this.embedded = false});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

enum _TasksTab { active, archived }

class _TasksScreenState extends State<TasksScreen> with WidgetsBindingObserver {
  _TasksTab _tab = _TasksTab.active;

  // Spec columns: To Do → In Progress → Done.
  static const List<({String key, String label, int color})> _columns = [
    (key: 'todo', label: 'To Do', color: 0xFF6B7280),
    (key: 'in_progress', label: 'In Progress', color: 0xFF0EA5E9),
    (key: 'done', label: 'Done', color: 0xFF22C55E),
  ];

  // Archived state.
  ArchivedTasksData? _archived;
  bool _archivedLoading = false;
  String? _archivedError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().loadTasks();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      if (_tab == _TasksTab.active) {
        context.read<DashboardProvider>().loadTasks();
      } else {
        _loadArchived();
      }
    }
  }

  Future<void> _loadArchived() async {
    setState(() {
      _archivedLoading = true;
      _archivedError = null;
    });
    try {
      final data = await ApiService().getArchivedTasks();
      if (!mounted) return;
      setState(() {
        _archived = data;
        _archivedLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _archivedError = 'Failed to load archived tasks';
        _archivedLoading = false;
      });
    }
  }

  void _switchTab(_TasksTab t) {
    if (t == _tab) return;
    setState(() => _tab = t);
    if (t == _TasksTab.archived && _archived == null) {
      _loadArchived();
    }
  }

  void _openTask(CommandTask task) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TaskDetailScreen(task: task)),
    );
  }

  Future<void> _onArchiveAllDone() async {
    final messenger = ScaffoldMessenger.of(context);
    final n = await context.read<DashboardProvider>().archiveAllDone();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('$n task${n == 1 ? '' : 's'} archived')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dash = context.watch<DashboardProvider>();
    final tasks = dash.tasks.where((t) => !t.isArchived).toList();

    final body = Column(
      children: [
        _header(context, tasks),
        Expanded(
          child: _tab == _TasksTab.active
              ? _ActiveBoard(
                  tasks: tasks,
                  columns: _columns,
                  onMove: (task, status) async {
                    final messenger = ScaffoldMessenger.of(context);
                    final ok = await context
                        .read<DashboardProvider>()
                        .updateTaskStatus(task.id, status);
                    if (!ok && mounted) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Move failed')),
                      );
                    }
                  },
                  onTap: _openTask,
                  onComplete: (t) =>
                      context.read<DashboardProvider>().completeTask(t.id),
                  onDismiss: (t) => context
                      .read<DashboardProvider>()
                      .resolveTask(t.id, resolution: 'did_not_happen'),
                  onRefresh: () =>
                      context.read<DashboardProvider>().loadTasks(),
                )
              : _ArchivedTab(
                  loading: _archivedLoading,
                  error: _archivedError,
                  data: _archived,
                  onRefresh: _loadArchived,
                  onRestore: (taskId) async {
                    final messenger = ScaffoldMessenger.of(context);
                    final dash = context.read<DashboardProvider>();
                    try {
                      await ApiService().restoreTask(taskId);
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Task restored')),
                      );
                      await _loadArchived();
                      // Restored tasks come back into the Active list.
                      await dash.loadTasks();
                    } catch (_) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Restore failed')),
                      );
                    }
                  },
                ),
        ),
      ],
    );

    final fab = FloatingActionButton(
      heroTag: 'tasks_fab',
      onPressed: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const QuickAddSheet(initialMode: 'task'),
      ),
      backgroundColor: AppTheme.brand,
      child: const Icon(Icons.add, color: Colors.white),
    );

    if (widget.embedded) {
      return Stack(
        children: [
          body,
          if (_tab == _TasksTab.active)
            Positioned(right: 16, bottom: 16, child: fab),
        ],
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      body: SafeArea(child: body),
      floatingActionButton: _tab == _TasksTab.active ? fab : null,
    );
  }

  Widget _header(BuildContext context, List<CommandTask> tasks) {
    final open = tasks.where((t) => t.status != 'done').length;
    final overdue = tasks.where((t) => t.isOverdue).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tasks',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary(context))),
                  const SizedBox(height: 2),
                  Text(
                    '$open open · $overdue overdue',
                    style: TextStyle(
                      fontSize: 12,
                      color: overdue > 0
                          ? const Color(0xFFEF4444)
                          : AppTheme.textMuted(context),
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: Icon(Icons.more_vert,
                  color: AppTheme.textSecondary(context)),
              onSelected: (v) {
                if (v == 'archive_done') _onArchiveAllDone();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'archive_done', child: Text('Archive all Done')),
              ],
            ),
          ]),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: AppTheme.borderColor(context)),
            ),
            child: Row(children: [
              _tabBtn('Active', _tab == _TasksTab.active,
                  () => _switchTab(_TasksTab.active)),
              _tabBtn('Archived', _tab == _TasksTab.archived,
                  () => _switchTab(_TasksTab.archived)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _tabBtn(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppTheme.brand : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radius - 1),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : AppTheme.textSecondary(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// Active = status-grouped kanban with drag-between-columns. Each column is
/// a `DragTarget<CommandTask>` so cards dropped on it fire `onMove`. Cards
/// are wrapped in `LongPressDraggable` so the gesture is unambiguous on a
/// vertically-scrolling list.
class _ActiveBoard extends StatelessWidget {
  final List<CommandTask> tasks;
  final List<({String key, String label, int color})> columns;
  final void Function(CommandTask task, String status) onMove;
  final void Function(CommandTask) onTap;
  final void Function(CommandTask) onComplete;
  final void Function(CommandTask) onDismiss;
  final Future<void> Function() onRefresh;

  const _ActiveBoard({
    required this.tasks,
    required this.columns,
    required this.onMove,
    required this.onTap,
    required this.onComplete,
    required this.onDismiss,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        children: [
          for (final col in columns)
            _Column(
              col: col,
              tasks: tasks.where((t) => t.status == col.key).toList(),
              onAccept: (task) {
                if (task.status != col.key) onMove(task, col.key);
              },
              onTap: onTap,
              onComplete: onComplete,
              onDismiss: onDismiss,
              onLongPressMove: (task) =>
                  _showMoveSheet(context, task, columns, onMove),
            ),
        ],
      ),
    );
  }
}

class _Column extends StatelessWidget {
  final ({String key, String label, int color}) col;
  final List<CommandTask> tasks;
  final void Function(CommandTask) onAccept;
  final void Function(CommandTask) onTap;
  final void Function(CommandTask) onComplete;
  final void Function(CommandTask) onDismiss;
  final void Function(CommandTask) onLongPressMove;

  const _Column({
    required this.col,
    required this.tasks,
    required this.onAccept,
    required this.onTap,
    required this.onComplete,
    required this.onDismiss,
    required this.onLongPressMove,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(col.color);
    return DragTarget<CommandTask>(
      onWillAcceptWithDetails: (d) => d.data.status != col.key,
      onAcceptWithDetails: (d) => onAccept(d.data),
      builder: (ctx, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          decoration: BoxDecoration(
            color: hovering
                ? color.withValues(alpha: 0.08)
                : AppTheme.surface(context),
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(
                color: hovering
                    ? color.withValues(alpha: 0.6)
                    : AppTheme.borderColor(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(
                  width: 10, height: 10,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(col.label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary(context))),
                const SizedBox(width: 6),
                Text('${tasks.length}',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted(context))),
              ]),
              const SizedBox(height: 8),
              if (tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: Text(
                      hovering ? 'Drop to move here' : 'Nothing here.',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textMuted(context)),
                    ),
                  ),
                )
              else
                ...tasks.map((t) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: LongPressDraggable<CommandTask>(
                        data: t,
                        feedback: _DragFeedback(task: t, accent: color),
                        childWhenDragging: Opacity(
                          opacity: 0.35,
                          child: TaskCard(task: t, onTap: () {}),
                        ),
                        child: GestureDetector(
                          onLongPress: () => onLongPressMove(t),
                          child: TaskCard(
                            task: t,
                            onComplete: () => onComplete(t),
                            onDismiss: () => onDismiss(t),
                            onTap: () => onTap(t),
                          ),
                        ),
                      ),
                    )),
            ],
          ),
        );
      },
    );
  }
}

class _DragFeedback extends StatelessWidget {
  final CommandTask task;
  final Color accent;
  const _DragFeedback({required this.task, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width - 48,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface(context),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: accent.withValues(alpha: 0.7), width: 1.5),
          boxShadow: AppTheme.softShadow(context),
        ),
        child: Row(children: [
          Container(
            width: 4, height: 32,
            decoration:
                BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(task.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

Future<void> _showMoveSheet(
  BuildContext context,
  CommandTask task,
  List<({String key, String label, int color})> columns,
  void Function(CommandTask, String) onMove,
) async {
  final target = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppTheme.surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Move "${task.title}"',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 8),
          for (final c in columns)
            ListTile(
              leading: Container(
                width: 12, height: 12,
                decoration:
                    BoxDecoration(color: Color(c.color), shape: BoxShape.circle),
              ),
              title: Text(c.label),
              trailing: task.status == c.key ? const Icon(Icons.check) : null,
              enabled: task.status != c.key,
              onTap: () => Navigator.of(ctx).pop(c.key),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (target != null && target != task.status) onMove(task, target);
}

/// Inline archived list — fetched lazily on tab switch via `getArchivedTasks`.
/// Each row has a Restore action that calls `POST /tasks/{id}/restore`.
class _ArchivedTab extends StatelessWidget {
  final bool loading;
  final String? error;
  final ArchivedTasksData? data;
  final Future<void> Function() onRefresh;
  final Future<void> Function(int taskId) onRestore;

  const _ArchivedTab({
    required this.loading,
    required this.error,
    required this.data,
    required this.onRefresh,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && data == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!,
                style: TextStyle(color: AppTheme.textSecondary(context))),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRefresh, child: const Text('Retry')),
          ],
        ),
      );
    }
    final groups = data?.groups ?? const [];
    if (groups.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            Center(
              child: Text('No archived tasks.',
                  style: TextStyle(
                      fontSize: 13, color: AppTheme.textMuted(context))),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        itemCount: groups.length,
        itemBuilder: (_, i) {
          final g = groups[i];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                child: Text(
                  _groupHeader(g.date),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary(context),
                      letterSpacing: 0.4),
                ),
              ),
              ...g.tasks.map((t) => _ArchivedRow(
                    task: t,
                    onRestore: () => onRestore(t.id),
                  )),
            ],
          );
        },
      ),
    );
  }

  static String _groupHeader(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

class _ArchivedRow extends StatelessWidget {
  final CommandTask task;
  final VoidCallback onRestore;
  const _ArchivedRow({required this.task, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface(context),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary(context))),
                if (task.description != null &&
                    task.description!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(task.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context))),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: onRestore,
            icon: const Icon(Icons.restore, size: 16),
            label: const Text('Restore'),
          ),
        ]),
      ),
    );
  }
}
