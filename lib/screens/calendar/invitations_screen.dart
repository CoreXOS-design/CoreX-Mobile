import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/dashboard_data.dart';
import '../../providers/dashboard_provider.dart';
import '../../utils/app_time.dart';

/// Pending calendar invitations from other users. Surfaced from the Today
/// "Pending Invitations" card and from the Calendar screen's overflow menu.
///
/// Per spec: each pending invite shows Accept / Tentative / Decline. If the
/// invitation has `live_conflicts`, an amber chip warns the user. Declined
/// invitations show an "Acknowledge" button to the organizer.
class InvitationsScreen extends StatefulWidget {
  const InvitationsScreen({super.key});

  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DashboardProvider>().loadInvitations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dash = context.watch<DashboardProvider>();
    final invites = dash.invitations;

    return Scaffold(
      appBar: AppBar(title: const Text('Invitations')),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () => dash.loadInvitations(),
          child: invites.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 120),
                  Center(child: Text('No invitations')),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: invites.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _InvitationCard(invitation: invites[i]),
                ),
        ),
      ),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  final CalendarInvitation invitation;
  const _InvitationCard({required this.invitation});

  @override
  Widget build(BuildContext context) {
    final event = invitation.event;
    final isPending = invitation.status == 'pending';
    final isDeclined = invitation.status == 'declined';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(event?.title ?? 'Invitation #${invitation.id}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            if (event != null)
              Text(_formatWhen(event), style: Theme.of(context).textTheme.bodySmall),
            if (invitation.inviterName != null) ...[
              const SizedBox(height: 4),
              Text('From ${invitation.inviterName}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            if (invitation.hasConflicts) ...[
              const SizedBox(height: 8),
              Chip(
                avatar: const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber),
                label: Text('Conflicts with ${invitation.liveConflicts.length} other event${invitation.liveConflicts.length == 1 ? '' : 's'}'),
                backgroundColor: Colors.amber.withValues(alpha: 0.15),
              ),
            ],
            if (!isPending) ...[
              const SizedBox(height: 8),
              Text('Status: ${invitation.status}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            if (isPending)
              Row(children: [
                Expanded(child: _respondBtn(context, 'accepted', 'Accept', Colors.green)),
                const SizedBox(width: 8),
                Expanded(child: _respondBtn(context, 'tentative', 'Tentative', Colors.amber)),
                const SizedBox(width: 8),
                Expanded(child: _respondBtn(context, 'declined', 'Decline', Colors.red)),
              ])
            else if (isDeclined && invitation.acknowledgedAt == null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context
                      .read<DashboardProvider>()
                      .acknowledgeInvitation(invitation.id),
                  child: const Text('Acknowledge'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _respondBtn(BuildContext context, String action, String label, Color color) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color)),
      onPressed: () async {
        final ok = await context
            .read<DashboardProvider>()
            .respondToInvitation(invitation.id, action);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? 'Response recorded' : 'Failed to respond')),
        );
      },
      child: Text(label),
    );
  }

  String _formatWhen(CalendarEvent e) {
    final d = jhb(e.eventDate);
    final dt = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return e.allDay ? '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} (all day)' : dt;
  }
}
