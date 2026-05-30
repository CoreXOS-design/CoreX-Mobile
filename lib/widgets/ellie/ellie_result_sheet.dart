import 'package:flutter/material.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../services/ai_api.dart';
import '../ai/ai_badge.dart';

/// Modal bottom sheet rendered after an Ellie voice command completes.
///
/// Shows the transcript, an action summary, and (when an event was created
/// within the 30-second undo window) an [Undo] button.
class EllieResultSheet extends StatefulWidget {
  final EllieVoiceResult result;
  final VoidCallback onOpenEvent;
  final Future<void> Function(int eventId) onUndo;

  const EllieResultSheet({
    super.key,
    required this.result,
    required this.onOpenEvent,
    required this.onUndo,
  });

  static Future<void> show(
    BuildContext context, {
    required EllieVoiceResult result,
    required VoidCallback onOpenEvent,
    required Future<void> Function(int eventId) onUndo,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
      ),
      builder: (_) => EllieResultSheet(
        result: result,
        onOpenEvent: onOpenEvent,
        onUndo: onUndo,
      ),
    );
  }

  @override
  State<EllieResultSheet> createState() => _EllieResultSheetState();
}

class _EllieResultSheetState extends State<EllieResultSheet> {
  bool _undoing = false;
  bool _undone = false;

  String _summary() {
    final r = widget.result;
    if (r.created && r.event != null) {
      final ev = r.event!;
      final title = ev['title']?.toString() ?? 'Event';
      final dateStr = ev['event_date']?.toString();
      String when = '';
      if (dateStr != null) {
        try {
          final dt = DateTime.parse(dateStr).toLocal();
          when = _formatWhen(dt);
        } catch (_) {
          when = dateStr;
        }
      }
      return when.isEmpty ? 'Scheduled: $title' : 'Scheduled: $title — $when';
    }
    if (r.failed) return r.message;
    if (r.unknown) return r.message.isEmpty ? "I didn't catch that." : r.message;
    return r.message;
  }

  String _formatWhen(DateTime dt) {
    const dayNames = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dayNames[dt.weekday - 1]} ${dt.day} ${monthNames[dt.month - 1]} $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final created = r.created && r.eventId != null;
    final color = Theme.of(context).colorScheme;
    final pad = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: pad),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const AiBadge(),
                  const SizedBox(width: 8),
                  Text(
                    'Ellie',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: color.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (r.transcript.isNotEmpty) ...[
                Text(
                  '"${r.transcript}"',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: color.onSurface.withValues(alpha: 0.75),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      created
                          ? TablerIcons.calendar_plus
                          : (r.failed
                              ? TablerIcons.alert_triangle
                              : TablerIcons.info_circle),
                      size: 18,
                      color: created
                          ? Colors.green
                          : (r.failed
                              ? Colors.orange
                              : color.onSurfaceVariant),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _summary(),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: color.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (created && !_undone)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _undoing
                            ? null
                            : () async {
                                setState(() => _undoing = true);
                                await widget.onUndo(r.eventId!);
                                if (!mounted) return;
                                setState(() {
                                  _undoing = false;
                                  _undone = true;
                                });
                              },
                        icon: _undoing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(TablerIcons.arrow_back_up, size: 18),
                        label: const Text('Undo'),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onOpenEvent();
                        },
                        icon: const Icon(TablerIcons.calendar_event, size: 18),
                        label: const Text('Open event'),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                )
              else
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
