import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/branding.dart';
import '../../theme.dart';
import '../../models/property.dart';
import '../../models/visibility.dart';
import '../../providers/property_provider.dart';
import '../../providers/visibility_provider.dart';
import '../../widgets/agent_filter_bar.dart';
import '../../widgets/ui/list_row.dart';
import '../../widgets/ui/status_chip.dart';
import 'property_create_screen.dart';
import 'property_edit_screen.dart';
import 'property_overview_screen.dart';

class PropertyListScreen extends StatefulWidget {
  const PropertyListScreen({super.key});

  @override
  State<PropertyListScreen> createState() => _PropertyListScreenState();
}

class _PropertyListScreenState extends State<PropertyListScreen> {
  final _searchController = TextEditingController();
  String _search = '';

  // Filter state — null means "any".
  String? _suburbFilter;
  String? _listingTypeFilter;
  String? _statusFilter;
  int? _minPrice;
  int? _maxPrice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PropertyProvider>().fetchProperties();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Pull-to-refresh re-pulls visibility (resets the agent filter to Mine
  /// per spec), then reloads the list with that reset filter.
  Future<void> _refresh() async {
    await context.read<VisibilityProvider>().refresh();
    if (!mounted) return;
    await context
        .read<PropertyProvider>()
        .fetchProperties(agentFilter: AgentFilter.mine);
  }

  void _onAgentFilterChanged(AgentFilter f) {
    context.read<VisibilityProvider>().setPropertiesFilter(f);
    context.read<PropertyProvider>().fetchProperties(agentFilter: f);
  }

  int get _activeFilterCount {
    var n = 0;
    if (_suburbFilter != null) n++;
    if (_listingTypeFilter != null) n++;
    if (_statusFilter != null) n++;
    if (_minPrice != null || _maxPrice != null) n++;
    return n;
  }

  List<Property> _applyFilters(List<Property> input) {
    final q = _search.trim().toLowerCase();
    return input.where((p) {
      if (q.isNotEmpty && !p.address.toLowerCase().contains(q)) {
        return false;
      }
      if (_suburbFilter != null && p.suburb != _suburbFilter) {
        return false;
      }
      if (_listingTypeFilter != null && p.listingType != _listingTypeFilter) {
        return false;
      }
      if (_statusFilter != null && p.status != _statusFilter) {
        return false;
      }
      if (_minPrice != null && (p.price == null || p.price! < _minPrice!)) {
        return false;
      }
      if (_maxPrice != null && (p.price == null || p.price! > _maxPrice!)) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Unique, sorted non-null values of [selector] across the currently-loaded
  /// properties. Used to populate filter chips dynamically — no dependency
  /// on the options endpoint, works with whatever the list actually has.
  List<String> _uniqueValues(
      List<Property> input, String? Function(Property) selector) {
    final set = <String>{};
    for (final p in input) {
      final v = selector(p);
      if (v != null && v.isNotEmpty) set.add(v);
    }
    final list = set.toList()..sort();
    return list;
  }

  void _clearFilters() {
    setState(() {
      _suburbFilter = null;
      _listingTypeFilter = null;
      _statusFilter = null;
      _minPrice = null;
      _maxPrice = null;
    });
  }

  Future<void> _openFilterSheet(List<Property> all) async {
    // Capture the currently-loaded list so the sheet's chip options are
    // stable while the sheet is open.
    final suburbs = _uniqueValues(all, (p) => p.suburb);
    final listingTypes = _uniqueValues(all, (p) => p.listingType);
    final statuses = _uniqueValues(all, (p) => p.status);

    // Seed the sheet with the current state and commit on Apply.
    String? suburb = _suburbFilter;
    String? listingType = _listingTypeFilter;
    String? status = _statusFilter;
    final minCtrl = TextEditingController(
        text: _minPrice != null ? _minPrice.toString() : '');
    final maxCtrl = TextEditingController(
        text: _maxPrice != null ? _maxPrice.toString() : '');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.background(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollCtrl) => Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Filters',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setSheet(() {
                            suburb = null;
                            listingType = null;
                            status = null;
                            minCtrl.clear();
                            maxCtrl.clear();
                          });
                        },
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollCtrl,
                      children: [
                        if (suburbs.isNotEmpty) ...[
                          _sectionLabel('Suburb'),
                          _chipGroup(
                            options: suburbs,
                            selected: suburb,
                            onSelected: (v) => setSheet(() => suburb = v),
                          ),
                          const SizedBox(height: 16),
                        ],
                        _sectionLabel('Price'),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: minCtrl,
                                keyboardType: TextInputType.number,
                                decoration:
                                    const InputDecoration(labelText: 'Min'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: maxCtrl,
                                keyboardType: TextInputType.number,
                                decoration:
                                    const InputDecoration(labelText: 'Max'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (listingTypes.isNotEmpty) ...[
                          _sectionLabel('Listing Type'),
                          _chipGroup(
                            options: listingTypes,
                            selected: listingType,
                            onSelected: (v) =>
                                setSheet(() => listingType = v),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (statuses.isNotEmpty) ...[
                          _sectionLabel('Status'),
                          _chipGroup(
                            options: statuses,
                            selected: status,
                            onSelected: (v) => setSheet(() => status = v),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _suburbFilter = suburb;
                          _listingTypeFilter = listingType;
                          _statusFilter = status;
                          _minPrice = int.tryParse(minCtrl.text.trim());
                          _maxPrice = int.tryParse(maxCtrl.text.trim());
                        });
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
    minCtrl.dispose();
    maxCtrl.dispose();
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary(context),
          ),
        ),
      );

  Widget _chipGroup({
    required List<String> options,
    required String? selected,
    required ValueChanged<String?> onSelected,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((o) {
        final isSelected = o == selected;
        return ChoiceChip(
          label: Text(o),
          selected: isSelected,
          onSelected: (_) => onSelected(isSelected ? null : o),
          backgroundColor: AppTheme.surface2(context),
          selectedColor: AppTheme.brand,
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textPrimary(context),
          ),
          side: BorderSide.none,
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PropertyProvider>();
    final all = provider.properties;
    final filtered = _applyFilters(all);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Properties'),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.filter_list),
                tooltip: 'Filters',
                onPressed: () => _openFilterSheet(all),
              ),
              if (_activeFilterCount > 0)
                Positioned(
                  top: 8,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.brand,
                      shape: BoxShape.circle,
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '$_activeFilterCount',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      floatingActionButton: _PropertiesFab(onPressed: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PropertyCreateScreen()),
        );
        if (mounted) context.read<PropertyProvider>().fetchProperties();
      }),
      body: SafeArea(
        top: false,
        child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search by address',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppTheme.surface(context),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  borderSide: BorderSide(color: AppTheme.borderColor(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  borderSide: BorderSide(color: AppTheme.borderColor(context)),
                ),
              ),
            ),
          ),
          if (_activeFilterCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Text(
                    '${filtered.length} of ${all.length} match',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.close, size: 14),
                    label: const Text('Clear filters'),
                    style:
                        TextButton.styleFrom(foregroundColor: AppTheme.brand),
                    onPressed: _clearFilters,
                  ),
                ],
              ),
            ),
          AgentFilterBar(
            noun: 'Properties',
            module: context.watch<VisibilityProvider>().properties,
            selected: context.watch<VisibilityProvider>().propertiesFilter,
            onChanged: _onAgentFilterChanged,
          ),
          Expanded(
            child: provider.isLoading && all.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : all.isEmpty
                    ? _buildEmpty()
                    : filtered.isEmpty
                        ? _buildNoMatches()
                        : RefreshIndicator(
                            onRefresh: _refresh,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) =>
                                  _PropertyCard(property: filtered[index]),
                            ),
                          ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const EmptyState(
      icon: Icons.home_outlined,
      title: 'No properties yet',
      subtitle: 'Tap + to add your first property',
    );
  }

  Widget _buildNoMatches() {
    return EmptyState(
      icon: Icons.search_off_rounded,
      title: 'No matches',
      subtitle: 'Try a different search or clear the filters.',
      action: TextButton(
        onPressed: () {
          _searchController.clear();
          setState(() => _search = '');
          _clearFilters();
        },
        child: const Text('Clear all'),
      ),
    );
  }
}

class _PropertiesFab extends StatelessWidget {
  final VoidCallback onPressed;
  const _PropertiesFab({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: AppTheme.brandGlow(brand.button, intensity: 0.35),
      ),
      child: FloatingActionButton(
        backgroundColor: brand.button,
        foregroundColor: Branding.onColor(brand.button),
        onPressed: onPressed,
        elevation: 0,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

class _PropertyCard extends StatelessWidget {
  final Property property;
  const _PropertyCard({required this.property});

  Color _statusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'active':
        return const Color(0xFF22C55E);
      case 'draft':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF8890A4);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.cardGradient(context),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          boxShadow: AppTheme.softShadow(context),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            onTap: () async {
              final isDraft =
                  (property.status ?? '').toLowerCase() == 'draft' ||
                      (property.status ?? '').isEmpty;
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => isDraft
                      ? PropertyEditScreen(propertyId: property.id)
                      : PropertyOverviewScreen(propertyId: property.id),
                ),
              );
              if (context.mounted) {
                context.read<PropertyProvider>().fetchProperties();
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: property.thumbnail != null
                        ? Image.network(
                            property.thumbnail!,
                            width: 76,
                            height: 76,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _placeholder(context),
                          )
                        : _placeholder(context),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          property.address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (property.beds != null) ...[
                              _Stat(icon: Icons.bed_rounded, value: '${property.beds}'),
                              const SizedBox(width: 12),
                            ],
                            if (property.baths != null) ...[
                              _Stat(icon: Icons.bathtub_rounded, value: '${property.baths}'),
                              const SizedBox(width: 12),
                            ],
                            if (property.garages != null)
                              _Stat(icon: Icons.garage_rounded, value: '${property.garages}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusChip(
                    label: property.status ?? 'N/A',
                    color: _statusColor(property.status),
                    dense: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: AppTheme.surface2(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(Icons.home_rounded,
          color: AppTheme.textMuted(context), size: 28),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  const _Stat({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppTheme.textSecondary(context)),
        const SizedBox(width: 4),
        Text(value,
            style: TextStyle(
                color: AppTheme.textSecondary(context),
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}
