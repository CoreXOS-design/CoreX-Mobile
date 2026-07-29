import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../widgets/ui/content_width.dart';
import '../../theme.dart';
import '../../models/dashboard_data.dart';
import '../../models/task_extras.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/api_service.dart';
import 'task_edit_sheet.dart';

class TaskDetailScreen extends StatefulWidget {
  final CommandTask task;
  const TaskDetailScreen({super.key, required this.task});

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  final _api = ApiService();
  final _noteCtrl = TextEditingController();
  final _checklistCtrl = TextEditingController();

  List<TaskNote> _notes = [];
  List<ChecklistItem> _items = [];
  bool _loading = true;
  String? _error;
  bool _sendingNote = false;
  bool _addingItem = false;

  int get _taskId => widget.task.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _checklistCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.getTaskNotes(_taskId),
        _api.getTaskChecklist(_taskId),
      ]);
      if (!mounted) return;
      setState(() {
        _notes = results[0] as List<TaskNote>;
        _items = results[1] as List<ChecklistItem>;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 403) {
        _toast(e.message);
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load';
        _loading = false;
      });
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _sendNote() async {
    final text = _noteCtrl.text.trim();
    if (text.isEmpty || _sendingNote) return;
    setState(() => _sendingNote = true);
    try {
      final note = await _api.createTaskNote(_taskId, text);
      if (!mounted) return;
      setState(() {
        _notes = [note, ..._notes];
        _noteCtrl.clear();
        _sendingNote = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sendingNote = false);
      _toast('Could not send note');
    }
  }

  Future<void> _deleteNote(TaskNote note) async {
    final prev = _notes;
    setState(() => _notes = _notes.where((n) => n.id != note.id).toList());
    try {
      await _api.deleteTaskNote(_taskId, note.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _notes = prev);
      _toast('Could not delete note');
    }
  }

  Future<void> _addItem() async {
    final text = _checklistCtrl.text.trim();
    if (text.isEmpty || _addingItem) return;
    setState(() => _addingItem = true);
    try {
      final item = await _api.createChecklistItem(_taskId, text);
      if (!mounted) return;
      setState(() {
        _items = [..._items, item];
        _checklistCtrl.clear();
        _addingItem = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _addingItem = false);
      _toast('Could not add item');
    }
  }

  Future<void> _toggleItem(ChecklistItem item) async {
    final newDone = !item.done;
    setState(() => _items = _items
        .map((i) => i.id == item.id ? i.copyWith(done: newDone) : i)
        .toList());
    try {
      await _api.updateChecklistItem(_taskId, item.id, done: newDone);
    } catch (_) {
      if (!mounted) return;
      setState(() => _items = _items
          .map((i) => i.id == item.id ? i.copyWith(done: !newDone) : i)
          .toList());
      _toast('Could not update item');
    }
  }

  Future<void> _deleteItem(ChecklistItem item) async {
    final prev = _items;
    setState(() => _items = _items.where((i) => i.id != item.id).toList());
    try {
      await _api.deleteChecklistItem(_taskId, item.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _items = prev);
      _toast('Could not delete item');
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final currentUserId = (context.read<AuthProvider>().user?['id'] as num?)?.toInt();
    final doneCount = _items.where((i) => i.done).length;

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        backgroundColor: AppTheme.background(context),
        elevation: 0,
        title: Text('Task', style: TextStyle(color: AppTheme.textPrimary(context), fontSize: 16)),
        iconTheme: IconThemeData(color: AppTheme.textPrimary(context)),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showTaskEditSheet(context, widget.task),
          ),
        ],
      ),
      body: ContentSafeArea(
        child: RefreshIndicator(
          color: AppTheme.brand,
          backgroundColor: AppTheme.surface(context),
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              _Header(task: task),
              const SizedBox(height: 24),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(children: [
                    Text(_error!, style: TextStyle(color: AppTheme.textSecondary(context))),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ]),
                )
              else ...[
                _SectionTitle(title: 'Checklist', trailing: '$doneCount / ${_items.length}'),
                const SizedBox(height: 8),
                ..._items.map((i) => _ChecklistRow(
                      item: i,
                      onToggle: () => _toggleItem(i),
                      onDelete: () => _deleteItem(i),
                    )),
                _AddInput(
                  controller: _checklistCtrl,
                  hint: 'Add item',
                  busy: _addingItem,
                  onSubmit: _addItem,
                  icon: Icons.add,
                ),
                const SizedBox(height: 24),
                const _SectionTitle(title: 'Notes'),
                const SizedBox(height: 8),
                _NoteInput(
                  controller: _noteCtrl,
                  busy: _sendingNote,
                  onSend: _sendNote,
                ),
                const SizedBox(height: 12),
                if (_notes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text('No notes yet.',
                        style: TextStyle(fontSize: 13, color: AppTheme.textMuted(context))),
                  )
                else
                  ..._notes.map((n) => _NoteRow(
                        note: n,
                        canDelete: currentUserId != null && currentUserId == n.userId,
                        onDelete: () => _deleteNote(n),
                      )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final CommandTask task;
  const _Header({required this.task});

  @override
  Widget build(BuildContext context) {
    final due = task.dueDate;
    final dueStr = due == null
        ? null
        : '${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(task.title,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary(context))),
          if (task.propertyAddress != null) ...[
            const SizedBox(height: 4),
            Text(task.propertyAddress!,
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary(context))),
          ],
          const SizedBox(height: 10),
          Row(children: [
            _StatusBadge(status: task.status, isOverdue: task.isOverdue),
            if (dueStr != null) ...[
              const SizedBox(width: 8),
              Icon(Icons.event, size: 14, color: AppTheme.textMuted(context)),
              const SizedBox(width: 4),
              Text(dueStr, style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context))),
            ],
          ]),
          if (task.description != null && task.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(task.description!,
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary(context))),
          ],
          const SizedBox(height: 12),
          Row(children: [
            if (task.status != 'done')
              Expanded(
                child: _SmallBtn(
                  label: 'Complete',
                  color: const Color(0xFF22c55e),
                  onTap: () {
                    context.read<DashboardProvider>().completeTask(task.id);
                    Navigator.of(context).pop();
                  },
                ),
              ),
          ]),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final bool isOverdue;
  const _StatusBadge({required this.status, required this.isOverdue});

  @override
  Widget build(BuildContext context) {
    final (label, color) = isOverdue
        ? ('Overdue', const Color(0xFFef4444))
        : switch (status) {
            'done' => ('Done', const Color(0xFF22c55e)),
            'in_progress' => ('In Progress', const Color(0xFF0ea5e9)),
            'awaiting' => ('Awaiting', const Color(0xFFf59e0b)),
            _ => ('To Do', const Color(0xFF6b7280)),
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SmallBtn({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color)),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? trailing;
  const _SectionTitle({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(title,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary(context))),
          const Spacer(),
          if (trailing != null)
            Text(trailing!, style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context))),
        ],
      );
}

class _ChecklistRow extends StatelessWidget {
  final ChecklistItem item;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  const _ChecklistRow({required this.item, required this.onToggle, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: onToggle,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: item.done ? AppTheme.brand : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: item.done ? AppTheme.brand : AppTheme.borderColor(context), width: 1.5),
              ),
              child: item.done ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.text,
              style: TextStyle(
                fontSize: 14,
                color: item.done ? AppTheme.textMuted(context) : AppTheme.textPrimary(context),
                decoration: item.done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: AppTheme.textMuted(context)),
            onPressed: onDelete,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _AddInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool busy;
  final VoidCallback onSubmit;
  final IconData icon;
  const _AddInput({
    required this.controller,
    required this.hint,
    required this.busy,
    required this.onSubmit,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                onSubmitted: (_) => onSubmit(),
                style: TextStyle(fontSize: 14, color: AppTheme.textPrimary(context)),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(color: AppTheme.textMuted(context), fontSize: 14),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    borderSide: BorderSide(color: AppTheme.borderColor(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    borderSide: BorderSide(color: AppTheme.borderColor(context)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: busy ? null : onSubmit,
              icon: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(icon, color: AppTheme.brand),
            ),
          ],
        ),
      );
}

class _NoteInput extends StatelessWidget {
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;
  const _NoteInput({required this.controller, required this.busy, required this.onSend});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.surface(context),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            TextField(
              controller: controller,
              maxLines: 3,
              minLines: 2,
              style: TextStyle(fontSize: 14, color: AppTheme.textPrimary(context)),
              decoration: InputDecoration(
                hintText: 'Add a note…',
                hintStyle: TextStyle(color: AppTheme.textMuted(context), fontSize: 14),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
            TextButton.icon(
              onPressed: busy ? null : onSend,
              icon: busy
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send, size: 16),
              label: const Text('Send'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.brand),
            ),
          ],
        ),
      );
}

class _NoteRow extends StatelessWidget {
  final TaskNote note;
  final bool canDelete;
  final VoidCallback onDelete;
  const _NoteRow({required this.note, required this.canDelete, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(note.userName,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary(context))),
            ),
            Text(_timeAgo(note.createdAt),
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted(context))),
            if (canDelete)
              GestureDetector(
                onTap: onDelete,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.delete_outline, size: 16, color: AppTheme.textMuted(context)),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          Text(note.body,
              style: TextStyle(fontSize: 14, color: AppTheme.textPrimary(context), height: 1.35)),
        ],
      ),
    );
  }
}

String _timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}
