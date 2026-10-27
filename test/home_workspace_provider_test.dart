import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corex_mobile/providers/home_workspace_provider.dart';
import 'package:corex_mobile/screens/home/workspace_modules.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<HomeWorkspaceProvider> make([Map<String, Object> stored = const {}]) async {
    SharedPreferences.setMockInitialValues(stored);
    final p = HomeWorkspaceProvider();
    await Future<void>.delayed(Duration.zero); // let _load() finish
    return p;
  }

  test('defaults to the original four tiles', () async {
    final p = await make();
    expect(p.visible(rentals: true), HomeWorkspaceProvider.defaults);
  });

  test('will not go above four', () async {
    final p = await make();
    final ok =
        await p.setEnabled(WorkspaceModule.rentals, true, rentals: true);
    expect(ok, isFalse);
    expect(p.visible(rentals: true), hasLength(4));
  });

  test('will not drop the last tile', () async {
    final p = await make({
      'home_workspace_modules': ['contacts'],
    });
    expect(p.visible(rentals: false), [WorkspaceModule.contacts]);
    final ok =
        await p.setEnabled(WorkspaceModule.contacts, false, rentals: false);
    expect(ok, isFalse);
    expect(p.visible(rentals: false), [WorkspaceModule.contacts]);
  });

  test('reorders and keeps the order across a reload', () async {
    final p = await make();
    // Portal Leads (index 3) to the front.
    await p.reorder(3, 0, rentals: false);
    // Properties (now index 1) to the end — ReorderableListView passes 4.
    await p.reorder(1, 4, rentals: false);
    const expected = [
      WorkspaceModule.portalLeads,
      WorkspaceModule.contacts,
      WorkspaceModule.coreMatches,
      WorkspaceModule.properties,
    ];
    expect(p.visible(rentals: false), expected);

    final prefs = await SharedPreferences.getInstance();
    final reloaded = await make({
      'home_workspace_modules': prefs.getStringList('home_workspace_modules')!,
    });
    expect(reloaded.visible(rentals: false), expected);
  });

  test('a newly enabled tile goes last', () async {
    final p = await make({
      'home_workspace_modules': ['portal_leads', 'properties'],
    });
    await p.setEnabled(WorkspaceModule.contacts, true, rentals: false);
    expect(p.visible(rentals: false), [
      WorkspaceModule.portalLeads,
      WorkspaceModule.properties,
      WorkspaceModule.contacts,
    ]);
  });

  test('swaps a tile and persists it', () async {
    final p = await make();
    expect(await p.setEnabled(WorkspaceModule.properties, false, rentals: true),
        isTrue);
    expect(
        await p.setEnabled(WorkspaceModule.rentals, true, rentals: true), isTrue);
    expect(p.visible(rentals: true), [
      WorkspaceModule.contacts,
      WorkspaceModule.coreMatches,
      WorkspaceModule.portalLeads,
      WorkspaceModule.rentals,
    ]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('home_workspace_modules'),
        ['contacts', 'core_matches', 'portal_leads', 'rentals']);
  });

  test('hides Rentals without access and never ends up empty', () async {
    final p = await make({
      'home_workspace_modules': ['rentals'],
    });
    expect(p.visible(rentals: true), [WorkspaceModule.rentals]);
    expect(p.visible(rentals: false), [WorkspaceModule.properties]);
  });
}
