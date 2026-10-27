// Agent data-visibility descriptor (mirrors the web).
//
// Returned by `GET /api/v1/mobile/visibility`. Tells the app, per module,
// whether the signed-in user may filter the list by teammate and which
// agents are in scope.

/// One agent the user is allowed to filter by.
class VisAgent {
  final int id;
  final String name;
  final String email;

  const VisAgent({required this.id, required this.name, required this.email});

  factory VisAgent.fromJson(Map<String, dynamic> j) => VisAgent(
        id: (j['id'] as num).toInt(),
        name: (j['name'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
      );
}

/// Per-module visibility (contacts / properties).
class ModuleVisibility {
  /// `own` | `branch` | `all`.
  final String scope;
  final bool canPickAgent;
  final List<VisAgent> agents;

  const ModuleVisibility({
    required this.scope,
    required this.canPickAgent,
    required this.agents,
  });

  /// Safe fallback: own-only, no filter UI.
  static const ModuleVisibility ownOnly =
      ModuleVisibility(scope: 'own', canPickAgent: false, agents: []);

  factory ModuleVisibility.fromJson(Map<String, dynamic> j) => ModuleVisibility(
        scope: (j['scope'] ?? 'own').toString(),
        canPickAgent: j['can_pick_agent'] == true,
        agents: (j['agents'] as List? ?? [])
            .whereType<Map>()
            .map((e) => VisAgent.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  /// Label for the "all" option, per scope.
  String get allLabel {
    switch (scope) {
      case 'all':
        return 'All agency';
      case 'branch':
        return 'All branch';
      default:
        return 'All';
    }
  }
}

/// One rentals screen's gate (AT-508): show the screen only when [canView],
/// show write buttons only when [canAct].
class RentalScreenAccess {
  final bool canView;
  final bool canAct;

  /// `own` | `branch` | `all`, or null when the screen is hidden.
  final String? scope;

  const RentalScreenAccess(
      {required this.canView, required this.canAct, this.scope});

  static const RentalScreenAccess hidden =
      RentalScreenAccess(canView: false, canAct: false);

  factory RentalScreenAccess.fromJson(Map<String, dynamic> j) {
    final view = j['can_view'] == true;
    return RentalScreenAccess(
      canView: view,
      canAct: view && j['can_act'] == true,
      scope: j['scope']?.toString(),
    );
  }
}

/// The `rentals` block of the descriptor. A server that predates it (or an
/// unreachable one) hides every rentals screen — the endpoints behind them
/// would not exist there either.
class RentalScreens {
  final RentalScreenAccess waiting;
  final RentalScreenAccess faultReports;
  final RentalScreenAccess workOrders;
  final RentalScreenAccess leases;
  final RentalScreenAccess notices;
  final RentalScreenAccess inspections;
  final RentalScreenAccess inventories;

  const RentalScreens({
    required this.waiting,
    required this.faultReports,
    required this.workOrders,
    required this.leases,
    required this.notices,
    required this.inspections,
    required this.inventories,
  });

  static const RentalScreens none = RentalScreens(
    waiting: RentalScreenAccess.hidden,
    faultReports: RentalScreenAccess.hidden,
    workOrders: RentalScreenAccess.hidden,
    leases: RentalScreenAccess.hidden,
    notices: RentalScreenAccess.hidden,
    inspections: RentalScreenAccess.hidden,
    inventories: RentalScreenAccess.hidden,
  );

  bool get any =>
      waiting.canView ||
      faultReports.canView ||
      workOrders.canView ||
      leases.canView ||
      notices.canView ||
      inspections.canView ||
      inventories.canView;

  factory RentalScreens.fromJson(Map<String, dynamic> j) {
    RentalScreenAccess read(String k) => j[k] is Map
        ? RentalScreenAccess.fromJson(Map<String, dynamic>.from(j[k] as Map))
        : RentalScreenAccess.hidden;
    return RentalScreens(
      waiting: read('waiting'),
      faultReports: read('fault_reports'),
      workOrders: read('work_orders'),
      leases: read('leases'),
      notices: read('notices'),
      inspections: read('inspections'),
      inventories: read('inventories'),
    );
  }
}

class VisibilityDescriptor {
  final ModuleVisibility contacts;
  final ModuleVisibility properties;
  final RentalScreens rentals;

  /// `rentals_enabled`: false when the agent's role has no rental permissions
  /// or the agency has Rentals switched off. [rentals] is then
  /// [RentalScreens.none] too, and no rental section shows anywhere —
  /// including the property Inspections tab, which predates the flag. That is
  /// why a server without the key reads as true: there the absent per-screen
  /// `can_view` flags already hide the AT-508 screens.
  final bool rentalsEnabled;

  const VisibilityDescriptor({
    required this.contacts,
    required this.properties,
    this.rentals = RentalScreens.none,
    this.rentalsEnabled = true,
  });

  /// Safe fallback used when `/v1/mobile/visibility` is unreachable: both
  /// modules collapse to own-only with no filter UI, and rentals are hidden.
  static const VisibilityDescriptor fallback = VisibilityDescriptor(
    contacts: ModuleVisibility.ownOnly,
    properties: ModuleVisibility.ownOnly,
  );

  factory VisibilityDescriptor.fromJson(Map<String, dynamic> j) {
    final rentalsEnabled = j['rentals_enabled'] != false;
    return VisibilityDescriptor(
      contacts: j['contacts'] is Map
          ? ModuleVisibility.fromJson(
              Map<String, dynamic>.from(j['contacts'] as Map))
          : ModuleVisibility.ownOnly,
      properties: j['properties'] is Map
          ? ModuleVisibility.fromJson(
              Map<String, dynamic>.from(j['properties'] as Map))
          : ModuleVisibility.ownOnly,
      rentals: rentalsEnabled && j['rentals'] is Map
          ? RentalScreens.fromJson(
              Map<String, dynamic>.from(j['rentals'] as Map))
          : RentalScreens.none,
      rentalsEnabled: rentalsEnabled,
    );
  }
}

/// The user's current list filter for a module. Session-only state.
sealed class AgentFilter {
  const AgentFilter();

  /// The default on first load / fresh login.
  static const AgentFilter mine = MineFilter();

  /// Query-param value to send for `agent_id`, or `null` to omit the param
  /// entirely (Mine).
  ///   Mine     → null  (omit)
  ///   All      → ''    (empty string)
  ///   Specific → `'<id>'`
  String? get queryValue;
}

class MineFilter extends AgentFilter {
  const MineFilter();
  @override
  String? get queryValue => null;
}

class AllAgentsFilter extends AgentFilter {
  const AllAgentsFilter();
  @override
  String? get queryValue => '';
}

class SpecificAgentFilter extends AgentFilter {
  final int agentId;
  const SpecificAgentFilter(this.agentId);
  @override
  String? get queryValue => '$agentId';

  @override
  bool operator ==(Object other) =>
      other is SpecificAgentFilter && other.agentId == agentId;
  @override
  int get hashCode => agentId.hashCode;
}
