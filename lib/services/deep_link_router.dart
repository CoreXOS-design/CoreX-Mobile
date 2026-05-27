import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/calendar_screen.dart';
import '../screens/contacts/contact_show_screen.dart';
import '../screens/deals/deal_show_screen.dart';
import '../screens/portal_leads/portal_lead_detail_screen.dart';
import '../screens/properties/property_list_screen.dart';
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
          builder: (_) => const PropertyListScreen(),
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

    // /corex/command-center/calendar?event=:id
    if (segments.length >= 3 &&
        segments[0] == 'corex' &&
        segments[1] == 'command-center' &&
        segments[2] == 'calendar') {
      navigator.push(MaterialPageRoute(
        builder: (_) => const CalendarScreen(),
      ));
      return;
    }

    // /corex#task-:id
    if (segments.isNotEmpty && segments[0] == 'corex') {
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
