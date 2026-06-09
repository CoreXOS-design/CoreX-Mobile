import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../theme/corex_tokens.dart';
import '../widgets/corex/corex_module_tile.dart';
import 'contacts/contacts_list_screen.dart';
import 'core_matches/core_matches_list_screen.dart';
import 'portal_leads/portal_leads_screen.dart';
import 'properties/property_list_screen.dart';

class RealEstateHubScreen extends StatelessWidget {
  const RealEstateHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final modules = <_ModuleSpec>[
      _ModuleSpec(
        icon: TablerIcons.building_skyscraper,
        label: 'Properties',
        builder: () => const PropertyListScreen(),
      ),
      _ModuleSpec(
        icon: TablerIcons.users,
        label: 'Contacts',
        builder: () => const ContactsListScreen(),
      ),
      _ModuleSpec(
        icon: TablerIcons.heart_handshake,
        label: 'Core Matches',
        builder: () => const CoreMatchesListScreen(),
      ),
      _ModuleSpec(
        icon: TablerIcons.target_arrow,
        label: 'Portal Leads',
        builder: () => const PortalLeadsScreen(),
      ),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: CorexTokens.pageBase(context),
        body: Container(
          decoration: BoxDecoration(gradient: CorexTokens.pageBacklight(context)),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 56,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: Icon(
                            TablerIcons.arrow_left,
                            color: CorexTokens.textPrimary(context),
                          ),
                        ),
                        Text(
                          'Workspace',
                          style: TextStyle(
                            color: CorexTokens.textPrimary(context),
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Browse',
                          style: TextStyle(
                            color: CorexTokens.textPrimary(context),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 1.0,
                          children: [
                            for (final m in modules)
                              CorexModuleTile(
                                icon: m.icon,
                                label: m.label,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => m.builder(),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModuleSpec {
  final IconData icon;
  final String label;
  final Widget Function() builder;
  _ModuleSpec({
    required this.icon,
    required this.label,
    required this.builder,
  });
}
