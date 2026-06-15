// Compliance + contact-linking models for the property Overview screen.
// Backed by `/api/mobile/properties/{id}/compliance` and
// `/api/mobile/properties/{id}/contacts`.

class ComplianceGate {
  final String key;
  final bool passed;
  final String detail;

  const ComplianceGate({
    required this.key,
    required this.passed,
    required this.detail,
  });

  factory ComplianceGate.fromJson(String key, Map<String, dynamic> j) =>
      ComplianceGate(
        key: key,
        passed: j['passed'] == true,
        detail: j['detail']?.toString() ?? '',
      );
}

class ComplianceNextAction {
  final String label;
  final String actionUrl;

  const ComplianceNextAction({required this.label, required this.actionUrl});

  factory ComplianceNextAction.fromJson(Map<String, dynamic> j) =>
      ComplianceNextAction(
        label: j['label']?.toString() ?? '',
        actionUrl: j['action_url']?.toString() ?? '',
      );
}

class CompliancePhotos {
  final int count;
  final int required;
  final bool passed;

  const CompliancePhotos({
    this.count = 0,
    this.required = 0,
    this.passed = false,
  });

  factory CompliancePhotos.fromJson(Map<String, dynamic> j) {
    int toInt(dynamic v) =>
        v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
    return CompliancePhotos(
      count: toInt(j['count']),
      required: toInt(j['required']),
      passed: j['passed'] == true,
    );
  }
}

class ComplianceSeller {
  final int? contactId;
  final String name;
  final String? role;
  final String? ficaStatus;
  final bool ficaPassed;

  const ComplianceSeller({
    this.contactId,
    required this.name,
    this.role,
    this.ficaStatus,
    this.ficaPassed = false,
  });

  factory ComplianceSeller.fromJson(Map<String, dynamic> j) {
    final id = j['contact_id'];
    return ComplianceSeller(
      contactId: id is num ? id.toInt() : int.tryParse(id?.toString() ?? ''),
      name: j['name']?.toString() ?? '',
      role: j['role']?.toString(),
      ficaStatus: j['fica_status']?.toString(),
      ficaPassed: j['fica_passed'] == true,
    );
  }
}

/// The canonical order checklist gates are rendered in on the Overview card.
const List<String> kComplianceGateOrder = [
  'authority_to_market',
  'fica_sellers',
  'photos',
  'details_complete',
];

const Map<String, String> kComplianceGateLabels = {
  'authority_to_market': 'Authority to market',
  'fica_sellers': 'Seller FICA',
  'photos': 'Photos',
  'details_complete': 'Listing details',
};

/// Display label for a checklist gate. Uses the curated label when known,
/// otherwise humanises the raw key (replace `_` with spaces, capitalise) so
/// dynamic gates the backend adds later (e.g. `dev_override`) still read well.
String complianceGateLabel(String key) {
  final known = kComplianceGateLabels[key];
  if (known != null) return known;
  final words = key.split('_').where((w) => w.isNotEmpty).map((w) {
    return w[0].toUpperCase() + w.substring(1);
  });
  final joined = words.join(' ');
  return joined.isEmpty ? key : joined;
}

class PropertyCompliance {
  final int propertyId;

  /// Server-computed status label: `LIVE` | `READY` | `BLOCKED`.
  final String? status;
  final bool marketable;
  final bool ready;
  final String? snapshotAt;

  /// Name of the agent who snapshotted the property to market (LIVE only).
  final String? snapshottedBy;
  final String? firstMarketedAt;
  final List<String> blockedBy;
  final List<ComplianceNextAction> nextActions;

  /// Gates in their canonical render order ([kComplianceGateOrder]).
  final List<ComplianceGate> checklist;
  final CompliancePhotos? photos;
  final List<ComplianceSeller> sellers;

  const PropertyCompliance({
    required this.propertyId,
    this.status,
    this.marketable = false,
    this.ready = false,
    this.snapshotAt,
    this.snapshottedBy,
    this.firstMarketedAt,
    this.blockedBy = const [],
    this.nextActions = const [],
    this.checklist = const [],
    this.photos,
    this.sellers = const [],
  });

  /// True when the property has gone live (snapshotted to market). Prefers the
  /// server `status` label, falling back to the marketable + snapshot heuristic
  /// for older payloads that don't carry `status`.
  bool get isLive =>
      status == 'LIVE' || (marketable && (snapshotAt ?? '').isNotEmpty);

  factory PropertyCompliance.fromJson(Map<String, dynamic> j) {
    int toInt(dynamic v) =>
        v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

    final checklistRaw = j['checklist'];
    final gates = <ComplianceGate>[];
    if (checklistRaw is Map) {
      // Render in the canonical order, then append any unknown extra gates.
      final seen = <String>{};
      for (final key in kComplianceGateOrder) {
        final g = checklistRaw[key];
        if (g is Map) {
          gates.add(
              ComplianceGate.fromJson(key, Map<String, dynamic>.from(g)));
          seen.add(key);
        }
      }
      for (final entry in checklistRaw.entries) {
        if (seen.contains(entry.key)) continue;
        if (entry.value is Map) {
          gates.add(ComplianceGate.fromJson(
              entry.key.toString(), Map<String, dynamic>.from(entry.value)));
        }
      }
    }

    final actionsRaw = j['next_actions'];
    final actions = actionsRaw is List
        ? actionsRaw
            .whereType<Map>()
            .map((e) =>
                ComplianceNextAction.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <ComplianceNextAction>[];

    final sellersRaw = j['sellers'];
    final sellers = sellersRaw is List
        ? sellersRaw
            .whereType<Map>()
            .map((e) => ComplianceSeller.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <ComplianceSeller>[];

    final blockedRaw = j['blocked_by'];
    final blocked = blockedRaw is List
        ? blockedRaw.map((e) => e.toString()).toList()
        : <String>[];

    final photosRaw = j['photos'];

    return PropertyCompliance(
      propertyId: toInt(j['property_id']),
      status: j['status']?.toString(),
      marketable: j['marketable'] == true,
      ready: j['ready'] == true,
      snapshotAt: j['snapshot_at']?.toString(),
      snapshottedBy: j['snapshotted_by']?.toString(),
      firstMarketedAt: j['first_marketed_at']?.toString(),
      blockedBy: blocked,
      nextActions: actions,
      checklist: gates,
      photos: photosRaw is Map
          ? CompliancePhotos.fromJson(Map<String, dynamic>.from(photosRaw))
          : null,
      sellers: sellers,
    );
  }

  /// Builds a report-shaped compliance object from a 422 `marketing_blocked`
  /// body: `{ blocked_by, report: { ready, checklist, ... } }`.
  factory PropertyCompliance.fromBlockedReport(
      int propertyId, Map<String, dynamic> body) {
    final report = body['report'];
    final map = report is Map
        ? Map<String, dynamic>.from(report)
        : <String, dynamic>{};
    map['property_id'] ??= propertyId;
    if (body['blocked_by'] != null && map['blocked_by'] == null) {
      map['blocked_by'] = body['blocked_by'];
    }
    return PropertyCompliance.fromJson(map);
  }
}

class PropertyContact {
  final int id;
  final String fullName;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final String? email;
  final String? role;
  final String? type;
  final String? ficaStatus;

  const PropertyContact({
    required this.id,
    required this.fullName,
    this.firstName,
    this.lastName,
    this.phone,
    this.email,
    this.role,
    this.type,
    this.ficaStatus,
  });

  factory PropertyContact.fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final first = j['first_name']?.toString();
    final last = j['last_name']?.toString();
    final full = j['full_name']?.toString();
    return PropertyContact(
      id: id is num ? id.toInt() : int.tryParse(id?.toString() ?? '') ?? 0,
      fullName: (full == null || full.isEmpty)
          ? '${first ?? ''} ${last ?? ''}'.trim()
          : full,
      firstName: first,
      lastName: last,
      phone: j['phone']?.toString(),
      email: j['email']?.toString(),
      role: j['role']?.toString(),
      type: j['type']?.toString(),
      ficaStatus: j['fica_status']?.toString(),
    );
  }
}
