import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/calendar_screen.dart';
import '../screens/contacts/contact_show_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/portal_leads/portal_lead_detail_screen.dart';
import '../screens/properties/property_overview_screen.dart';
import '../screens/rentals/client/client_inspection_screens.dart';
import '../screens/rentals/client/client_rentals_shared.dart';
import '../screens/rentals/client/owner_rentals_screens.dart';
import '../screens/rentals/client/tenant_rentals_screens.dart';
import '../screens/rentals/staff/staff_faults_screens.dart';
import '../screens/rentals/staff/staff_inspections_screens.dart';
import '../screens/rentals/staff/staff_leases_screens.dart';
import '../screens/rentals/staff/staff_maintenance_actions.dart';
import '../screens/rentals/staff/staff_rentals_home_screen.dart';
import '../screens/rentals/staff/staff_work_orders_screens.dart';
import '../screens/tasks_screen.dart';
import '../providers/rentals_access_provider.dart';
import 'rentals/client_rentals_api.dart';
import 'rentals/rentals_http.dart';
import 'rentals/staff_rentals_api.dart';

/// Translates a server-issued `action_url` into a native route.
///
/// Supported paths (web cockpit equivalents):
///   /properties/:id                              → PropertyDetail
///   /contacts/:id                                → ContactDetail
///   /corex/command-center/calendar?event=:id     → Calendar (focused on event)
///   /corex#task-:id                              → Tasks (focused on task)
/// Anything else falls back to opening in an external browser — or, for a
/// push tap ([fromPush]), the notifications list.
class DeepLinkRouter {
  /// App-internal link to the notifications list: an agent push with no
  /// `target` (see MessagingService.resolveAction).
  static const notificationsLink = 'corex-app://notifications';

  static Future<void> open(BuildContext context, String? actionUrl,
      {bool fromPush = false}) async {
    if (actionUrl == null || actionUrl.isEmpty) return;

    final uri = Uri.tryParse(actionUrl);
    if (uri == null) return;

    final navigator = Navigator.of(context);
    final segments = uri.pathSegments;

    if (actionUrl == notificationsLink) {
      navigator
          .push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
      return;
    }

    // corex-rental://<audience>/<subject_type>/<subject_id> — a rentals push
    // (see MessagingService.resolveAction). Opened by someone who may not see
    // that side, or a record that answers 403/404: back to Home, no error.
    if (uri.scheme == 'corex-rental') {
      final access = await RentalsAccess.settled(context);
      final screen = segments.length >= 2
          ? rentalScreen(
              access, uri.host, segments[0], int.tryParse(segments[1]))
          : null;
      if (screen != null && await _reachable(screen)) {
        navigator.push(MaterialPageRoute(builder: (_) => screen));
      } else {
        navigator.popUntil((r) => r.isFirst);
      }
      return;
    }

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

    // /deals/:id — no native deal screen yet; fall through to the external
    // browser (handled below) so the user lands on the real web deal page.

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

    // A push with no app screen: the notifications list, not the browser.
    if (fromPush) {
      navigator
          .push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
      return;
    }

    // Fallback — external browser.
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// False only when the record a push names answers 403 / 404 — gone, or
  /// not this person's. Offline, slow or any other failure opens the screen,
  /// which has its own cache and error state.
  static Future<bool> _reachable(Widget screen) async {
    final probe = rentalProbe(screen);
    if (probe == null) return true;
    try {
      await probe().timeout(const Duration(seconds: 10));
      return true;
    } on RentalsApiException catch (e) {
      return e.statusCode != 403 && e.statusCode != 404;
    } catch (_) {
      return true;
    }
  }

  /// The GET a record screen loads with, so a push can check the record
  /// before opening it. Null for list screens.
  @visibleForTesting
  static Future<Object?> Function()? rentalProbe(Widget screen) {
    final staff = StaffRentalsApi.instance;
    return switch (screen) {
      StaffFaultDetailScreen s => () => staff.faultReport(s.faultId),
      StaffWorkOrderDetailScreen s => () => staff.workOrder(s.workOrderId),
      StaffLeaseFileScreen s => () => staff.lease(s.leaseId),
      StaffJobCardScreen s => () => staff.jobCard(s.jobCardId),
      StaffInspectionScreen(inspectionId: final int id) => () =>
          staff.inspection(id),
      TenantFaultDetailScreen s => () =>
          ClientRentalsApi.tenant.faultReport(s.faultId),
      OwnerFaultDetailScreen s => () =>
          ClientRentalsApi.owner.faultReport(s.faultId),
      TenantWorkOrderScreen s => () =>
          ClientRentalsApi.tenant.workOrder(s.workOrderId),
      OwnerWorkOrderScreen s => () =>
          ClientRentalsApi.owner.workOrder(s.workOrderId),
      ClientInspectionDetailScreen s => () => s.api.inspection(s.inspectionId),
      _ => null,
    };
  }

  /// Client subject_type: fault | fault_report | work_order | lease_notice |
  /// inspection. Agent target: fault | work_order | job_card | lease_notice |
  /// lease | inspection | application. Null — stay put — when [access] does
  /// not allow the side the link is for.
  @visibleForTesting
  static Widget? rentalScreen(
      RentalsAccess access, String audience, String type, int? id) {
    if (audience == 'staff' || audience == 'agent') {
      if (!access.staff) return null;
      final s = access.staffScreens;
      final visible = switch (type) {
        'fault' || 'fault_report' => s.faultReports.canView,
        // Job cards have no visibility key of their own; they sit with work orders.
        'work_order' || 'job_card' => s.workOrders.canView,
        'lease' => s.leases.canView,
        'lease_notice' => s.notices.canView,
        'inspection' => s.inspections.canView,
        _ => true,
      };
      // A screen this agent may not open: Home, never a 403 page.
      if (!visible) return null;
      // application has no app screen: the notifications list.
      return staffSubjectScreen(type, id) ?? const NotificationsScreen();
    }
    final bool owner;
    switch (audience) {
      case 'owner':
      case 'landlord':
      case 'lessor':
        owner = true;
      case 'tenant':
      case 'lessee':
        owner = false;
      default:
        // No side named: the only side this person has, if just one.
        if (access.tenant == access.owner) {
          if (!access.tenant) return null;
          owner = false;
        } else {
          owner = access.owner;
        }
    }
    if (owner ? !access.owner : !access.tenant) return null;
    switch (type) {
      case 'fault':
      case 'fault_report':
        if (id == null) return null;
        return owner
            ? OwnerFaultDetailScreen(faultId: id)
            : TenantFaultDetailScreen(faultId: id);
      case 'work_order':
        if (id == null) return null;
        return owner
            ? OwnerWorkOrderScreen(workOrderId: id)
            : TenantWorkOrderScreen(workOrderId: id);
      case 'lease_notice':
        return ClientNoticesScreen(
            api: owner ? ClientRentalsApi.owner : ClientRentalsApi.tenant);
      case 'inspection':
        final api = owner ? ClientRentalsApi.owner : ClientRentalsApi.tenant;
        return id == null
            ? ClientInspectionsScreen(api: api)
            : ClientInspectionDetailScreen(api: api, inspectionId: id);
      default:
        return owner
            ? const OwnerRentalsHomeScreen()
            : const TenantRentalsHomeScreen();
    }
  }
}
