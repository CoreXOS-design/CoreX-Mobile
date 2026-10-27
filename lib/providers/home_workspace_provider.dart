import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/home/workspace_modules.dart';

/// Which [WorkspaceModule]s the agent wants on the Home grid. Device-local,
/// like the theme toggle — it's a layout preference, not account data.
///
/// The Home grid is sized for two rows of two, so the choice is bounded to
/// [min]..[max]. Always ask for [visible] rather than the raw selection: a
/// module the agent can no longer open (Rentals switched off) drops out, and
/// an empty result falls back so Home never shows a heading over nothing.
class HomeWorkspaceProvider extends ChangeNotifier {
  static const _key = 'home_workspace_modules';
  static const int min = 1;
  static const int max = 4;

  static const List<WorkspaceModule> defaults = [
    WorkspaceModule.properties,
    WorkspaceModule.contacts,
    WorkspaceModule.coreMatches,
    WorkspaceModule.portalLeads,
  ];

  List<WorkspaceModule> _selected = defaults;

  HomeWorkspaceProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_key);
    if (ids == null) return;
    final parsed = _normalise(ids.map(WorkspaceModule.fromId).nonNulls);
    if (parsed.isEmpty) return;
    _selected = parsed;
    notifyListeners();
  }

  /// Modules available to this agent: everything except Rentals unless
  /// [rentals] (RentalsAccess.staff) says they may open it.
  static List<WorkspaceModule> available({required bool rentals}) => [
        for (final m in WorkspaceModule.values)
          if (m != WorkspaceModule.rentals || rentals) m,
      ];

  /// What Home shows, in the agent's order, always [min]..[max] long.
  List<WorkspaceModule> visible({required bool rentals}) {
    final allowed = available(rentals: rentals);
    final shown = _selected.where(allowed.contains).toList();
    return shown.isEmpty ? [allowed.first] : shown;
  }

  /// Turns [module] on (appended last) or off. Returns false (and changes
  /// nothing) when that would leave fewer than [min] or more than [max]
  /// tiles, so the caller can say why.
  Future<bool> setEnabled(WorkspaceModule module, bool enabled,
      {required bool rentals}) async {
    final current = visible(rentals: rentals);
    if (enabled == current.contains(module)) return true;
    final next = enabled
        ? [...current, module]
        : current.where((m) => m != module).toList();
    // Check before normalising — it caps at [max], which would silently drop
    // a tile instead of refusing the fifth.
    if (next.length < min || next.length > max) return false;
    await _save(next);
    return true;
  }

  /// Moves the tile at [oldIndex] of [visible] to [newIndex], with
  /// ReorderableListView's convention that [newIndex] counts the item still
  /// in its old slot.
  Future<void> reorder(int oldIndex, int newIndex,
      {required bool rentals}) async {
    final next = visible(rentals: rentals);
    if (newIndex > oldIndex) newIndex--;
    if (oldIndex == newIndex) return;
    next.insert(newIndex, next.removeAt(oldIndex));
    await _save(next);
  }

  Future<void> _save(List<WorkspaceModule> next) async {
    _selected = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, [for (final m in next) m.id]);
  }

  /// De-duplicates (first occurrence wins, order kept) and caps at [max].
  static List<WorkspaceModule> _normalise(Iterable<WorkspaceModule> modules) =>
      modules.toSet().take(max).toList();
}
