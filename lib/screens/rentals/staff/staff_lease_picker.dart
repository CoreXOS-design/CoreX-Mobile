import 'package:flutter/material.dart';

import '../../../services/rentals/staff_rentals_api.dart';
import '../widgets/rentals_ui.dart';

/// A tenancy chosen for a new fault / work order / inspection.
class PickedLease {
  final int leaseId;
  final int propertyId;
  final String address;
  final String tenantNames;

  const PickedLease({
    required this.leaseId,
    required this.propertyId,
    required this.address,
    required this.tenantNames,
  });

  static PickedLease? fromLease(Json l) {
    final p = l.obj('property');
    final leaseId = l.integer('id');
    final propertyId = p?.integer('id');
    if (leaseId == null || propertyId == null) return null;
    final tenants = l.objs('tenants').map((t) => t.str('name')).whereType<String>();
    return PickedLease(
      leaseId: leaseId,
      propertyId: propertyId,
      address: p?.str('address') ?? '',
      tenantNames: l.str('tenant_names') ?? tenants.join(', '),
    );
  }
}

/// Search the person's own leases (the same scope as the lease list) and
/// pick one. Faults, work orders and inspections all hang off a tenancy, so
/// the lease gives both the property and the lease id.
Future<PickedLease?> pickLease(BuildContext context) {
  return Navigator.of(context).push<PickedLease>(MaterialPageRoute(
    builder: (_) => RentalsPage(
      title: 'Choose the tenancy',
      body: RentalsPagedList<Json>(
        searchHint: 'Address, tenant or owner',
        fetch: (page, q) => StaffRentalsApi.instance
            .leases(page, {...q, 'sort': 'property'}),
        itemBuilder: (context, l) {
          final picked = PickedLease.fromLease(l);
          return RentalsListCard(
            title: l.obj('property')?.str('address') ?? 'Lease',
            subtitle: picked?.tenantNames,
            meta: l.str('reference'),
            statusLabel: l.str('status_label'),
            statusKey: l.str('status'),
            onTap: picked == null
                ? null
                : () => Navigator.of(context).pop(picked),
          );
        },
      ),
    ),
  ));
}
