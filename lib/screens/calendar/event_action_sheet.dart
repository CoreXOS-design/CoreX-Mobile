import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/dashboard_data.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/api_service.dart';
import '../../theme.dart';
import '../../utils/app_time.dart';
import 'event_form_sheet.dart';

/// Bottom sheet shown when tapping a calendar event. Surfaces the four spec
/// quick-actions (Complete / Dismiss / Edit / Delete) plus the Resolve
/// bottom-sheet entry for overdue events.
Future<void> showEventActionsSheet(BuildContext context, CalendarEvent event) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _EventDetailSheet(event: event),
  );
}

class _EventDetailSheet extends StatelessWidget {
  final CalendarEvent event;
  const _EventDetailSheet({required this.event});

  Color get _accent {
    var s = event.colour.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 6) s = 'FF$s';
    final n = int.tryParse(s, radix: 16);
    return n == null ? const Color(0xFF6B7280) : Color(n);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textMuted(context).withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(color: _accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(event.title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 12),
              _kv(context, Icons.schedule, _fullTimeLabel(event)),
              if (event.allDay)
                _kv(context, Icons.brightness_5_outlined, 'All day'),
              if (event.location != null && event.location!.isNotEmpty)
                _kv(context, Icons.place_outlined, event.location!),
              if (event.propertyAddress != null &&
                  event.propertyAddress!.isNotEmpty)
                _kv(context, Icons.home_outlined, event.propertyAddress!),
              if (event.eventClassName != null &&
                  event.eventClassName!.isNotEmpty)
                _kv(context, Icons.label_outline, event.eventClassName!),
              if (event.createdByName != null &&
                  event.createdByName!.isNotEmpty)
                _kv(context, Icons.person_outline,
                    'Created by ${event.createdByName}'),
              if (event.attendees.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Attendees (${event.attendees.length})',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary(context),
                        letterSpacing: 0.4)),
                const SizedBox(height: 6),
                ...event.attendees.map((a) => _attendeeRow(context, a)),
              ],
              if (event.description != null &&
                  event.description!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Description',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary(context),
                        letterSpacing: 0.4)),
                const SizedBox(height: 4),
                Text(event.description!,
                    style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textPrimary(context))),
              ],
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await context
                          .read<DashboardProvider>()
                          .completeEvent(event.id);
                    },
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Complete'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      try {
                        await ApiService().dismissEvent(event.id);
                        if (!context.mounted) return;
                        await context
                            .read<DashboardProvider>()
                            .loadToday();
                      } catch (_) {}
                    },
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Dismiss'),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final dash = context.read<DashboardProvider>();
                      // Capture a context that survives this sheet being
                      // popped — the edit flow awaits a fetch before opening,
                      // by which point this sheet's own context is defunct.
                      final navState = Navigator.of(context);
                      final stableCtx = navState.context;
                      navState.pop();
                      // Full edit flow: fetches detail (honours is_editable),
                      // pre-fills properties + attendees, PUTs on save.
                      final updated =
                          await openEventForEdit(stableCtx, event.id);
                      if (updated) {
                        await dash.loadToday();
                        final now = DateTime.now();
                        await dash.loadEventsRange(
                          start: now.subtract(const Duration(days: 30)),
                          end: now.add(const Duration(days: 60)),
                        );
                      }
                    },
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final dash = context.read<DashboardProvider>();
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          title: const Text('Delete event?'),
                          content: const Text(
                              'This will cancel any pending invitations and notify attendees.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.of(dCtx).pop(false),
                                child: const Text('Cancel')),
                            TextButton(
                                onPressed: () => Navigator.of(dCtx).pop(true),
                                style: TextButton.styleFrom(
                                    foregroundColor: Colors.red),
                                child: const Text('Delete')),
                          ],
                        ),
                      );
                      if (confirm != true) return;
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                      try {
                        await ApiService().deleteEvent(event.id);
                        await dash.loadToday();
                        final now = DateTime.now();
                        await dash.loadEventsRange(
                          start: now.subtract(const Duration(days: 30)),
                          end: now.add(const Duration(days: 60)),
                        );
                      } catch (e) {
                        messenger.showSnackBar(
                            SnackBar(content: Text('Delete failed: $e')));
                      }
                    },
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Delete'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: AppTheme.textMuted(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textPrimary(context))),
        ),
      ]),
    );
  }

  Widget _attendeeRow(BuildContext context, EventAttendee a) {
    Color c;
    IconData ico;
    switch (a.response) {
      case 'accepted':
        c = const Color(0xFF10B981);
        ico = Icons.check_circle;
        break;
      case 'declined':
        c = const Color(0xFFEF4444);
        ico = Icons.cancel;
        break;
      case 'tentative':
        c = const Color(0xFFF59E0B);
        ico = Icons.help_outline;
        break;
      default:
        c = AppTheme.textMuted(context);
        ico = Icons.schedule;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(ico, size: 14, color: c),
        const SizedBox(width: 8),
        Expanded(
          child: Text(a.name.isEmpty ? '(unnamed)' : a.name,
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textPrimary(context))),
        ),
        Text(a.response,
            style: TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary(context),
                fontWeight: FontWeight.w500)),
      ]),
    );
  }

  String _fullTimeLabel(CalendarEvent e) {
    final s = jhb(e.eventDate);
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    if (e.endDate != null) return '${fmt(s)} â€“ ${fmt(jhb(e.endDate!))}';
    return fmt(s);
  }
}
