import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/calendar_screen.dart';
import '../screens/contacts/contact_show_screen.dart';
import '../screens/deals/deal_show_screen.dart';
import '../screens/portal_leads/portal_lead_detail_screen.dart';
import '../screens/properties/property_overview_screen.dart';
import '../screens/tasks_screen.dart';

/// Translates a server-issued `action_url` into a native route.
///
/// Supported paths (web cockpit equivalents):
///   /properties/:id                              → PropertyDetail
///   /contacts/:id                                → ContactDetail
///   /deals/:id                                   → DealDetail
///   /corex/command-center/calendar?event=:id     → Calendar (focused on event)
///   /corex#task-:id                              → Tasks (focused on task)
/// Anything else falls back to opening in an external browser.
class DeepLinkRouter {
  static Future<void> open(BuildContext context, String? actionUrl) async {
    if (actionUrl == null || actionUrl.isEmpty) return;

    final uri = Uri.tryParse(actionUrl);
    if (uri == null) return;

    final navigator = Navigator.of(context);
    final segments = uri.pathSegments;

    // /portal-leads/:id
    if (segments.length >= 2 && segments[0] == 'portal-leads') {
      final id = int.tryParse(segments[1]);
      if (id != null) {
        navigator.push(MaterialPageRoute(
          builder: (_) => PortalLeadDetailScreen(leadId: id),
        ));
        return;
      }
    }

    // /properties/:id
    if (segments.length >= 2 && segments[0] == 'properties') {
      final id = int.tryParse(segments[1]);
      if (id != null) {
        navigator.push(MaterialPageRoute(
          builder: (_) => PropertyOverviewScreen(propertyId: id),
        ));
        return;
      }
    }

    // /contacts/:id
    if (segments.length >= 2 && segments[0] == 'contacts') {
      final id = int.tryParse(segments[1]);
      if (id != null) {
        navigator.push(MaterialPageRoute(
          builder: (_) => ContactShowScreen(contactId: id),
        ));
        return;
      }
    }

    // /deals/:id
    if (segments.length >= 2 && segments[0] == 'deals') {
      final id = int.tryParse(segments[1]);
      if (id != null) {
        navigator.push(MaterialPageRoute(
          builder: (_) => DealShowScreen(dealId: id),
        ));
        return;
      }
    }

    // /calendar/events/:id  (event-reminder push `deep_link`)
    if (segments.length >= 3 &&
        segments[0] == 'calendar' &&
        segments[1] == 'events') {
      final eventId = int.tryParse(segments[2]);
      navigator.push(MaterialPageRoute(
        builder: (_) => CalendarScreen(openEventId: eventId),
      ));
      return;
    }

    // /corex/command-center/calendar?event=:id
    if (segments.length >= 3 &&
        segments[0] == 'corex' &&
        segments[1] == 'command-center' &&
        segments[2] == 'calendar') {
      final eventId = int.tryParse(uri.queryParameters['event'] ?? '');
      navigator.push(MaterialPageRoute(
        builder: (_) => CalendarScreen(openEventId: eventId),
      ));
      return;
    }

    // /corex#task-:id
    // The task id lives in the URI fragment (`#task-123`), not in the path
    // segments. Parse it so callers can deep-link to a specific task.
    if (segments.isNotEmpty && segments[0] == 'corex') {
      final match = RegExp(r'task-(\d+)').firstMatch(uri.fragment);
      final taskId = match == null ? null : int.tryParse(match.group(1)!);
      // TODO: TasksScreen does not yet accept an open/focus task id, so the
      // parsed `taskId` cannot be forwarded. Wire it through once TasksScreen
      // exposes a focus parameter.
      assert(taskId == null || taskId > 0);
      navigator.push(MaterialPageRoute(
        builder: (_) => const TasksScreen(),
      ));
      return;
    }

    // Fallback — external browser.
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
