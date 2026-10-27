import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../../models/visibility.dart';
import '../../../providers/rentals_access_provider.dart';
import '../../../services/rentals/rental_write_queue.dart';
import '../../../services/rentals/staff_rentals_api.dart';
import '../../../theme.dart';
import '../widgets/rentals_actions.dart';
import '../widgets/rentals_ui.dart';
import 'staff_faults_screens.dart';
import 'staff_application_screen.dart';
import 'staff_inspections_screens.dart';
import 'staff_inventories_screens.dart';
import 'staff_leases_screens.dart';
import 'staff_maintenance_actions.dart';
import 'staff_work_orders_screens.dart';

final _api = StaffRentalsApi.instance;

/// Staff rentals home: what is waiting for me, the command-centre counts, and
/// the rental screens this person may open (from `/mobile/visibility`).
class StaffRentalsHomeScreen extends StatefulWidget {
  const StaffRentalsHomeScreen({super.key});

  @override
  State<StaffRentalsHomeScreen> createState() => _StaffRentalsHomeScreenState();
}

class _StaffRentalsHomeScreenState extends State<StaffRentalsHomeScreen> {
  final _refresh = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    RentalWriteQueue.instance.sent.addListener(_bump);
  }

  @override
  void dispose() {
    RentalWriteQueue.instance.sent.removeListener(_bump);
    _refresh.dispose();
    super.dispose();
  }

  void _bump() => _refresh.value++;

  @override
  Widget build(BuildContext context) {
    final v = context.watch<RentalsAccess>().staffScreens;
    return RentalsPage(
      title: 'Rentals',
      body: RentalsFutureView<({Json? waiting, Json? centre})>(
        refresh: _refresh,
        load: () async {
          Json? waiting;
          Json? centre;
          if (v.waiting.canView) {
            final r = await Future.wait<Json?>([
              _api.waiting().then<Json?>((e) => e),
              _api
                  .commandCentre()
                  .then<Json?>((e) => e)
                  .catchError((_) => null),
            ]);
            waiting = r[0];
            centre = r[1];
          }
          return (waiting: waiting, centre: centre);
        },
        builder: (context, data, reload) =>
            _body(context, v, data.waiting, data.centre),
      ),
    );
  }

  Widget _body(
      BuildContext context, RentalScreens v, Json? waiting, Json? centre) {
    final tiles = centre?.obj('tiles');
    int? records(String k) {
      final t = tiles?[k];
      if (t is num) return t.toInt();
      if (t is Map) return (t['records'] as num?)?.toInt();
      return null;
    }

    final items = waiting?.objs('data') ?? const <Json>[];
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      children: [
        const RentalsQueueBanner(),
        if (waiting != null)
          RentalsSection(
            title: 'Waiting for you (${waiting.integer('waiting_count') ?? 0})',
            trailing: items.length < (waiting.integer('waiting_count') ?? 0)
                ? TextButton(
                    style: TextButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 8)),
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const StaffWaitingScreen())),
                    child: const Text('See all'),
                  )
                : null,
            child: items.isEmpty
                ? BodyText(
                    waiting.obj('meta')?.str('empty_reason') ??
                        'Nothing is waiting for you.',
                    muted: true)
                : Column(children: [
                    for (final i in items.take(5)) WaitingRow(item: i),
                  ]),
          ),
        if (tiles != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _KpiGrid(children: [
              if (v.faultReports.canView)
                _tile(
                    context,
                    'Open faults',
                    records('open_faults'),
                    () => _push(context,
                        StaffFaultsScreen(canAct: v.faultReports.canAct))),
              if (v.workOrders.canView)
                _tile(
                    context,
                    'Open work orders',
                    records('open_work_orders'),
                    () => _push(context,
                        StaffWorkOrdersScreen(canAct: v.workOrders.canAct))),
              if (v.leases.canView)
                _tile(
                    context,
                    'Expiring',
                    records('expiring'),
                    () => _push(context,
                        const StaffLeasesScreen(initialExpiring: true))),
              if (v.notices.canView)
                _tile(context, 'Notices to review', records('notice_review'),
                    () => _push(context, const StaffNoticesScreen())),
              if (v.inspections.canView)
                _tile(
                    context,
                    'Inspections due',
                    records('inspections_due'),
                    () => _push(context,
                        StaffInspectionsScreen(canAct: v.inspections.canAct))),
            ]),
          ),
        RentalsSection(
          title: 'Open',
          child: Column(children: [
            if (v.faultReports.canView)
              _module(context, TablerIcons.tool, 'Faults',
                  StaffFaultsScreen(canAct: v.faultReports.canAct)),
            if (v.workOrders.canView)
              _module(context, TablerIcons.hammer, 'Work orders',
                  StaffWorkOrdersScreen(canAct: v.workOrders.canAct)),
            // The server has no visibility key for job cards yet; they sit
            // with work orders and a 403 shows the server's refusal.
            if (v.workOrders.canView)
              _module(context, TablerIcons.clipboard_list, 'Job cards',
                  const StaffJobCardsScreen()),
            if (v.leases.canView)
              _module(context, TablerIcons.file_certificate, 'Leases',
                  const StaffLeasesScreen()),
            // Create the applicant and send the application out; nothing
            // else of an application is done on the phone. No visibility key
            // exists for applications, so a 403 shows the server's refusal.
            if (v.leases.canView)
              ValueListenableBuilder<Set<String>>(
                valueListenable: RentalsDenied.keys,
                builder: (context, denied, _) =>
                    denied.contains('rental_applications.create')
                        ? const SizedBox.shrink()
                        : RentalsNavRow(
                            icon: TablerIcons.file_plus,
                            title: 'Send a rental application',
                            onTap: () => startRentalApplication(context),
                          ),
              ),
            if (v.notices.canView)
              _module(context, TablerIcons.file_alert, 'Notices to review',
                  const StaffNoticesScreen()),
            if (v.inspections.canView)
              _module(context, TablerIcons.clipboard_check, 'Inspections',
                  StaffInspectionsScreen(canAct: v.inspections.canAct)),
            if (v.inventories.canView)
              _module(context, TablerIcons.list_details, 'Inventories',
                  const StaffInventoriesScreen()),
          ]),
        ),
      ],
    );
  }

  void _push(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  /// A KPI tile (design system §3.1: value 20 / w600, label 11 muted).
  Widget _tile(BuildContext context, String label, int? n, VoidCallback on) {
    return RentalsCard(
      onTap: on,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(n?.toString() ?? '—',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary(context))),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11, color: AppTheme.textSecondary(context))),
        ],
      ),
    );
  }

  Widget _module(
          BuildContext context, IconData icon, String label, Widget screen) =>
      RentalsNavRow(
        icon: icon,
        title: label,
        onTap: () => _push(context, screen),
      );
}

/// 2-up KPI tiles; an odd last tile takes the full row (no orphan).
class _KpiGrid extends StatelessWidget {
  final List<Widget> children;
  const _KpiGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    const gap = 12.0;
    return Column(children: [
      for (var i = 0; i < children.length; i += 2)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
          child: Row(children: [
            Expanded(child: children[i]),
            if (i + 1 < children.length) ...[
              const SizedBox(width: gap),
              Expanded(child: children[i + 1]),
            ],
          ]),
        ),
    ]);
  }
}

/// One "waiting for me" item; opens the record it names.
class WaitingRow extends StatelessWidget {
  final Json item;
  const WaitingRow({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final age = item.integer('age_days');
    return RentalsNavRow(
      title: item.str('label') ?? '',
      subtitle: [
        item.obj('property')?.str('address'),
        item.str('detail'),
        if (age != null) age < 0 ? 'in ${-age} days' : '$age days',
      ].whereType<String>().join(' · '),
      onTap: () => openStaffSubject(
          context, item.str('subject_type'), item.integer('subject_id'),
          leaseId: item.integer('lease_id'),
          propertyId: item.obj('property')?.integer('id'),
          address: item.obj('property')?.str('address')),
    );
  }
}

/// Routes a server `subject_type` + `subject_id` to its screen.
void openStaffSubject(BuildContext context, String? type, int? id,
    {int? leaseId, int? propertyId, String? address}) {
  final screen = staffSubjectScreen(type, id,
      leaseId: leaseId, propertyId: propertyId, address: address);
  if (screen == null) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open this one on the web for now.')));
    return;
  }
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}

/// The screen for a staff rentals subject, or null when the app has none.
/// Shared by the Waiting list and agent pushes (`target` + `target_id`).
Widget? staffSubjectScreen(String? type, int? id,
    {int? leaseId, int? propertyId, String? address}) {
  switch (type) {
    case 'fault_report':
    case 'fault':
      return id != null ? StaffFaultDetailScreen(faultId: id) : null;
    case 'work_order':
      return id != null ? StaffWorkOrderDetailScreen(workOrderId: id) : null;
    case 'lease':
      final l = id ?? leaseId;
      return l != null ? StaffLeaseFileScreen(leaseId: l) : null;
    case 'lease_notice':
      return leaseId != null
          ? StaffLeaseFileScreen(leaseId: leaseId)
          : const StaffNoticesScreen();
    case 'inspection':
      return id != null
          ? StaffInspectionScreen(
              inspectionId: id,
              propertyId: propertyId ?? 0,
              title: address ?? 'Inspection')
          : const StaffInspectionsScreen(canAct: true);
    case 'job_card':
      return id != null ? StaffJobCardScreen(jobCardId: id) : null;
    default:
      // application and anything new: no app screen yet.
      return null;
  }
}

class StaffWaitingScreen extends StatelessWidget {
  const StaffWaitingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RentalsPage(
      title: 'Waiting for you',
      body: RentalsPagedList<Json>(
        searchable: false,
        fetch: (page, q) async {
          final body = await _api.waiting(page: page);
          return PagedResult.parse(body, (m) => m);
        },
        itemBuilder: (context, i) => RentalsCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: WaitingRow(item: i),
        ),
      ),
    );
  }
}
