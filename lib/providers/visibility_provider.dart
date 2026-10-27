import 'package:flutter/foundation.dart';
import '../models/visibility.dart';
import '../services/api_service.dart';

/// Holds the agent data-visibility descriptor and the user's per-module
/// list filter. The filter selection is session-only — a fresh login (or
/// any refresh) resets both modules back to "Mine".
class VisibilityProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  VisibilityDescriptor _descriptor = VisibilityDescriptor.fallback;
  bool _loaded = false;

  AgentFilter _contactsFilter = AgentFilter.mine;
  AgentFilter _propertiesFilter = AgentFilter.mine;

  VisibilityDescriptor get descriptor => _descriptor;
  ModuleVisibility get contacts => _descriptor.contacts;
  ModuleVisibility get properties => _descriptor.properties;
  RentalScreens get rentals => _descriptor.rentals;
  bool get loaded => _loaded;

  AgentFilter get contactsFilter => _contactsFilter;
  AgentFilter get propertiesFilter => _propertiesFilter;

  /// Fetch (or refresh) the descriptor. Resets the per-module filters to
  /// Mine, and prunes any selection no longer permitted. On failure, falls
  /// back to own-only with no filter UI.
  Future<void> refresh() async {
    try {
      _descriptor = await _api.getVisibility();
    } catch (_) {
      _descriptor = VisibilityDescriptor.fallback;
    }
    _loaded = true;
    // Session reset: every refresh (login / pull-to-refresh) starts at Mine.
    _contactsFilter = AgentFilter.mine;
    _propertiesFilter = AgentFilter.mine;
    notifyListeners();
  }

  /// App resume: pick up an admin's change (e.g. Rentals switched off)
  /// without a re-login. Unlike [refresh] it keeps the agent's list filters
  /// where still allowed, and keeps the current descriptor when offline.
  Future<void> refreshOnResume() async {
    if (!_loaded) return;
    final VisibilityDescriptor next;
    try {
      next = await _api.getVisibility();
    } catch (_) {
      return;
    }
    if (!_loaded) return; // signed out meanwhile
    _descriptor = next;
    if (!_isAllowed(next.contacts, _contactsFilter)) {
      _contactsFilter = AgentFilter.mine;
    }
    if (!_isAllowed(next.properties, _propertiesFilter)) {
      _propertiesFilter = AgentFilter.mine;
    }
    notifyListeners();
  }

  /// Clear state on logout so the next user starts clean.
  void reset() {
    _descriptor = VisibilityDescriptor.fallback;
    _loaded = false;
    _contactsFilter = AgentFilter.mine;
    _propertiesFilter = AgentFilter.mine;
    notifyListeners();
  }

  void setContactsFilter(AgentFilter f) {
    if (!_isAllowed(_descriptor.contacts, f)) return;
    _contactsFilter = f;
    notifyListeners();
  }

  void setPropertiesFilter(AgentFilter f) {
    if (!_isAllowed(_descriptor.properties, f)) return;
    _propertiesFilter = f;
    notifyListeners();
  }

  /// The agents list is authoritative — never honour a specific-agent
  /// selection that isn't in scope.
  bool _isAllowed(ModuleVisibility m, AgentFilter f) {
    if (f is SpecificAgentFilter) {
      return m.canPickAgent && m.agents.any((a) => a.id == f.agentId);
    }
    if (f is AllAgentsFilter) return m.canPickAgent;
    return true; // Mine is always allowed.
  }
}
