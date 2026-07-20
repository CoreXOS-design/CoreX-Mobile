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

class VisibilityDescriptor {
  final ModuleVisibility contacts;
  final ModuleVisibility properties;

  const VisibilityDescriptor({
    required this.contacts,
    required this.properties,
  });

  /// Safe fallback used when `/v1/mobile/visibility` is unreachable: both
  /// modules collapse to own-only with no filter UI.
  static const VisibilityDescriptor fallback = VisibilityDescriptor(
    contacts: ModuleVisibility.ownOnly,
    properties: ModuleVisibility.ownOnly,
  );

  factory VisibilityDescriptor.fromJson(Map<String, dynamic> j) =>
      VisibilityDescriptor(
        contacts: j['contacts'] is Map
            ? ModuleVisibility.fromJson(
                Map<String, dynamic>.from(j['contacts'] as Map))
            : ModuleVisibility.ownOnly,
        properties: j['properties'] is Map
            ? ModuleVisibility.fromJson(
                Map<String, dynamic>.from(j['properties'] as Map))
            : ModuleVisibility.ownOnly,
      );
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
