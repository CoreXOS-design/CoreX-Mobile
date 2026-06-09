import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/today_card.dart';

/// Generic destination for Today cards whose dedicated screen has not been
/// built yet. Shows the card's [items] as a read-only list and offers a
/// "View on web" button that opens [TodayCard.viewAllUrl] in the system
/// browser. Mobile auth is bearer-token based, so the web URL will require
/// a fresh login on the device's browser — acceptable as a stopgap until
/// the dedicated screen ships.
class CardFallbackScreen extends StatelessWidget {
  final TodayCard card;
  const CardFallbackScreen({super.key, required this.card});

  Future<void> _openWeb(BuildContext context) async {
    final url = card.viewAllUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }

  /// Per-card-id item rendering. Each branch knows the item shape from the
  /// cockpit spec; everything else falls back to a generic title+subtitle.
  Widget _itemTile(String cardId, Map<String, dynamic> item) {
    String? s(String k) {
      final v = item[k];
      return (v == null || v.toString().isEmpty) ? null : v.toString();
    }

    switch (cardId) {
      // {label, value, colour?, critical?}
      case 'esign_activity':
      case 'active_buyer_pipeline':
      case 'my_compliance':
      case 'prospecting_activity':
        return ListTile(
          dense: true,
          title: Text(s('label') ?? '(no label)'),
          trailing: Text(
            s('value') ?? '',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: item['critical'] == true ? const Color(0xFFEF4444) : null,
            ),
          ),
        );
      // {id, name|contact, reason|issue|status, days_*}
      case 'buyers_follow_up':
      case 'buyer_portal_activity':
      case 'fica_review':
      case 'my_fica_submissions':
      case 'branch_agent_watch':
        return ListTile(
          dense: true,
          title: Text(s('name') ?? s('contact') ?? '(no name)'),
          subtitle: Text([
            s('reason'), s('issue'), s('status'),
            if (s('days_waiting') != null) '${s('days_waiting')}d waiting',
            if (s('days_overdue') != null) '${s('days_overdue')}d overdue',
            s('urgency_label'),
            s('action'),
            s('property'),
            s('when'),
          ].whereType<String>().join(' • ')),
        );
      // {id, title, time, date_label, category}
      case 'today_appointments':
        return ListTile(
          dense: true,
          title: Text(s('title') ?? '(untitled)'),
          subtitle: Text(
              [s('date_label'), s('time'), s('category')].whereType<String>().join(' · ')),
        );
      // {id, title, inviter, time}
      case 'pending_invitations':
        return ListTile(
          dense: true,
          title: Text(s('title') ?? '(untitled)'),
          subtitle:
              Text([s('inviter'), s('time')].whereType<String>().join(' · ')),
        );
      // {type, id, title, due, days_overdue}
      case 'overdue_items':
        final days = s('days_overdue');
        return ListTile(
          dense: true,
          leading: const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444)),
          title: Text(s('title') ?? '(untitled)'),
          subtitle: Text([
            if (s('type') != null) s('type')!.toUpperCase(),
            if (days != null) '${days}d overdue',
            s('due'),
          ].whereType<String>().join(' • ')),
        );
      // {id, title, days_on_market}
      case 'listings_attention':
        return ListTile(
          dense: true,
          title: Text(s('title') ?? '(no address)'),
          trailing: s('days_on_market') == null
              ? null
              : Text('${s('days_on_market')}d',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
        );
      // {action, summary, when}
      case 'recent_activity':
        return ListTile(
          dense: true,
          title: Text(s('action') ?? s('summary') ?? '(no description)'),
          subtitle: s('when') == null ? null : Text(s('when')!),
        );
      // {id, message, when}
      case 'unread_notifications':
        return ListTile(
          dense: true,
          title: Text(s('message') ?? '(no message)'),
          subtitle: s('when') == null ? null : Text(s('when')!),
        );
      // {agents, listings, active_buyers, lost_value_30d} — single-map card
      case 'agency_health':
        final entries = item.entries
            .where((e) => e.value != null && e.value.toString().isNotEmpty)
            .toList();
        return Column(
          children: entries
              .map((e) => ListTile(
                    dense: true,
                    title: Text(_humanise(e.key)),
                    trailing: Text(e.value.toString(),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ))
              .toList(),
        );
      // {text}
      case 'strategic_insights':
        return ListTile(
          dense: true,
          leading: const Icon(Icons.lightbulb_outline),
          title: Text(s('text') ?? '(no insight)'),
        );
      default:
        // Generic: title + subtitle stitched from common keys.
        final title = s('title') ?? s('name') ?? s('label') ?? s('message') ??
            s('text') ?? s('action') ?? '(no title)';
        final subtitleParts = <String>[
          for (final k in const [
            'subtitle', 'reason', 'status', 'when', 'time',
            'date_label', 'due', 'inviter', 'days_overdue',
            'days_on_market', 'days_waiting', 'urgency_label', 'value',
          ])
            if (s(k) != null) s(k)!,
        ];
        return ListTile(
          dense: true,
          title: Text(title),
          subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' • ')),
        );
    }
  }

  String _humanise(String key) =>
      key.replaceAll('_', ' ').replaceFirstMapped(RegExp(r'^.'), (m) => m[0]!.toUpperCase());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(card.title)),
      body: SafeArea(
        top: false,
        child: card.items.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Nothing to show yet.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              )
            : ListView.separated(
                itemCount: card.items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) => _itemTile(card.cardId, card.items[i]),
              ),
      ),
      bottomNavigationBar: card.viewAllUrl == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () => _openWeb(context),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('View on web'),
                ),
              ),
            ),
    );
  }
}
