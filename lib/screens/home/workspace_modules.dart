import 'package:flutter/widgets.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../contacts/contacts_list_screen.dart';
import '../core_matches/core_matches_list_screen.dart';
import '../portal_leads/portal_leads_screen.dart';
import '../properties/property_list_screen.dart';
import '../rentals/staff/staff_rentals_home_screen.dart';

/// Every module that can sit in the Home "Workspace" grid. Declaration order
/// is only the default and the order of the picker's "More modules" list —
/// the agent sets the order of the tiles actually on Home.
///
/// [id] is what's persisted, so never rename one; add new modules instead.
enum WorkspaceModule {
  properties('properties', 'Properties', TablerIcons.building_skyscraper),
  contacts('contacts', 'Contacts', TablerIcons.users),
  coreMatches('core_matches', 'Core Matches', TablerIcons.heart_handshake),
  portalLeads('portal_leads', 'Portal Leads', TablerIcons.target_arrow),
  // AT-508: only offered to staff the server says may see Rentals.
  rentals('rentals', 'Rentals', TablerIcons.key);

  final String id;
  final String label;
  final IconData icon;
  const WorkspaceModule(this.id, this.label, this.icon);

  Widget screen() => switch (this) {
        properties => const PropertyListScreen(),
        contacts => const ContactsListScreen(),
        coreMatches => const CoreMatchesListScreen(),
        portalLeads => const PortalLeadsScreen(),
        rentals => const StaffRentalsHomeScreen(),
      };

  static WorkspaceModule? fromId(String id) {
    for (final m in values) {
      if (m.id == id) return m;
    }
    return null;
  }
}
