import 'package:flutter/material.dart';
import '../../models/space.dart';
import '../../services/api_service.dart';
import '../../utils/display_text.dart';
import '../../theme.dart';
import '../../widgets/ai/ai_suggestions_section.dart';

/// Self-contained editor for a property's `spaces_json`:
/// - Loads the catalog (cached) + current spaces state.
/// - Lets the agent add/remove space types, step counts, toggle features.
/// - Has its own Save button that PUTs the full object back.
class SpacesEditorSection extends StatefulWidget {
  final int propertyId;
  final VoidCallback? onSaved;

  const SpacesEditorSection({
    super.key,
    required this.propertyId,
    this.onSaved,
  });

  @override
  State<SpacesEditorSection> createState() => SpacesEditorSectionState();
}

class SpacesEditorSectionState extends State<SpacesEditorSection> {
  /// True if there are unsaved local edits.
  bool get hasUnsavedChanges => _dirty;

  /// Flushes unsaved edits to the server. Returns true on success (or when
  /// there was nothing to save). Used by the outer edit screen so its final
  /// "Save Changes" button also persists space edits.
  Future<bool> saveIfDirty() async {
    if (!_dirty) return true;
    await _save();
    return !_dirty;
  }

  final ApiService _api = ApiService();

  SpacesCatalog? _catalog;
  List<PropertySpace> _spaces = [];
  Map<String, List<String>> _features = {};

  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _loadError;

  late final AiSuggestionsController _aiCtrl =
      AiSuggestionsController(widget.propertyId);

  @override
  void initState() {
    super.initState();
    _load();
    _aiCtrl.load();
  }

  @override
  void dispose() {
    _aiCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final catalog = await _api.getSpacesCatalog();
      final data = await _api.getPropertySpaces(widget.propertyId);
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _spaces = data.spaces;
        // Deep-copy: the inner lists belong to the parsed model. Editing a
        // chip mutates these lists in place, so we must not alias the model's.
        _features =
            data.features.map((k, v) => MapEntry(k, List<String>.from(v)));
        // Ensure every catalog category exists as a key so the UI has a stable shape
        for (final key in catalog.featureCategories.keys) {
          _features.putIfAbsent(key, () => <String>[]);
        }
        _loading = false;
        _dirty = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load spaces';
      });
    }
  }

  bool _isHalfUnit(String type) =>
      _catalog?.halfUnitSpaces.contains(type) ?? false;

  String _formatCount(double c) {
    if (c == c.roundToDouble()) return c.toInt().toString();
    return c.toStringAsFixed(1);
  }

  void _addSpace(String type) {
    if (_spaces.any((s) => s.type == type)) return;
    setState(() {
      _spaces.add(PropertySpace(
        type: type,
        count: 1,
        featuresAll: [],
        descriptionAll: '',
        units: [PropertySpaceUnit(label: '$type 1', features: [])],
      ));
      _dirty = true;
    });
    // Jump straight into the feature editor for the newly added space
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openFeaturePicker(_spaces.length - 1);
    });
  }

  void _removeSpace(int index) {
    setState(() {
      _spaces.removeAt(index);
      _dirty = true;
    });
  }

  void _stepCount(int index, double delta) {
    final space = _spaces[index];
    double next = space.count + delta;
    if (next < 0) next = 0;
    // Normalize to 0.5 steps to avoid float drift
    next = (next * 2).round() / 2;

    setState(() {
      space.count = next;
      // units length must equal ceil(count)
      final target = next.ceil();
      while (space.units.length < target) {
        space.units.add(PropertySpaceUnit(
          label: '${space.type} ${space.units.length + 1}',
          features: [],
        ));
      }
      while (space.units.length > target) {
        space.units.removeLast();
      }
      if (next == 0) {
        _spaces.removeAt(index);
      }
      _dirty = true;
    });
  }

  IconData _iconForType(String type) {
    final t = type.toLowerCase();
    if (t.contains('bed')) return Icons.bed;
    if (t.contains('bath')) return Icons.bathtub_outlined;
    if (t.contains('kitchen')) return Icons.kitchen;
    if (t.contains('garage')) return Icons.garage;
    if (t.contains('park')) return Icons.local_parking;
    if (t.contains('pool')) return Icons.pool;
    if (t.contains('garden')) return Icons.park;
    if (t.contains('lounge') || t.contains('living')) return Icons.weekend;
    if (t.contains('dining')) return Icons.dining;
    if (t.contains('study')) return Icons.menu_book;
    if (t.contains('flatlet')) return Icons.house_siding;
    return Icons.room_preferences;
  }

  // ---- Feature picker modal ----

  void _openFeaturePicker(int index) {
    if (index < 0 || index >= _spaces.length) return;
    final space = _spaces[index];
    final catalog = _catalog;
    if (catalog == null) return;
    final groups = catalog.featuresForType(space.type);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.background(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetCtx) {
        int tab = 0;
        int unitIndex = 0;

        return StatefulBuilder(builder: (ctx, setSheet) {
          final showPerUnit = space.count >= 2 && space.units.isNotEmpty;

          List<String> currentList() {
            if (tab == 0) return space.featuresAll;
            return space.units[unitIndex].features;
          }

          void toggle(String feature) {
            final list = currentList();
            setSheet(() {
              if (list.contains(feature)) {
                list.remove(feature);
              } else {
                list.add(feature);
              }
            });
            // Mark outer state dirty without rebuilding the sheet
            _dirty = true;
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (ctx2, scrollCtrl) {
              return Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(ctx2).viewInsets.bottom + 16,
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(_iconForType(space.type), color: AppTheme.brand),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              titleCaseLabel(space.type),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary(context),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            color: AppTheme.textSecondary(context),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (showPerUnit)
                        Row(
                          children: [
                            _tabButton('All Units', tab == 0,
                                () => setSheet(() => tab = 0)),
                            const SizedBox(width: 8),
                            _tabButton('Per Unit', tab == 1,
                                () => setSheet(() => tab = 1)),
                          ],
                        ),
                      if (tab == 1 && showPerUnit) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 40,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: space.units.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              final selected = i == unitIndex;
                              return ChoiceChip(
                                label: Text(space.units[i].label),
                                selected: selected,
                                onSelected: (_) =>
                                    setSheet(() => unitIndex = i),
                                backgroundColor: AppTheme.surface2(context),
                                selectedColor: AppTheme.brand,
                                labelStyle: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : AppTheme.textPrimary(context),
                                ),
                                side: BorderSide.none,
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView(
                          controller: scrollCtrl,
                          children: groups.entries
                              .where((e) => e.value.isNotEmpty)
                              .map((entry) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.key,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textSecondary(context),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: entry.value.map((f) {
                                      final selected =
                                          currentList().contains(f);
                                      return FilterChip(
                                        label: Text(titleCaseLabel(f)),
                                        selected: selected,
                                        onSelected: (_) => toggle(f),
                                        backgroundColor: AppTheme.surface2(context),
                                        selectedColor: AppTheme.brand,
                                        checkmarkColor: Colors.white,
                                        labelStyle: TextStyle(
                                          color: selected
                                              ? Colors.white
                                              : AppTheme.textPrimary(context),
                                        ),
                                        side: BorderSide.none,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                              AppTheme.radius),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        });
      },
    ).then((_) {
      // Sheet closed — force a rebuild so the card's feature count refreshes
      if (mounted) setState(() {});
    });
  }

  Widget _tabButton(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppTheme.brand : AppTheme.surface2(context),
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : AppTheme.textPrimary(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ---- Save ----

  Future<void> _save() async {
    // A retry SnackBarAction can fire after the widget is gone.
    if (!mounted) return;
    if (_saving || !_dirty) return;
    setState(() => _saving = true);

    final payload = {
      'spaces': _spaces.map((s) => s.toJson()).toList(),
      'features': _features,
    };

    try {
      final result =
          await _api.updatePropertySpaces(widget.propertyId, payload);
      if (!mounted) return;
      setState(() {
        _spaces = result.spaces;
        _features =
            result.features.map((k, v) => MapEntry(k, List<String>.from(v)));
        for (final key
            in _catalog?.featureCategories.keys ?? const <String>[]) {
          _features.putIfAbsent(key, () => <String>[]);
        }
        _dirty = false;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved')),
      );
      widget.onSaved?.call();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Couldn't save — try again"),
          action: SnackBarAction(label: 'Retry', onPressed: _save),
        ),
      );
    }
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              _loadError!,
              style: TextStyle(color: AppTheme.textSecondary(context)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final catalog = _catalog!;
    final availableTypes = catalog.allSpaceTypes
        .where((t) => !_spaces.any((s) => s.type == t))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spaces & Features',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 16),
          _buildAddSpaceDropdown(availableTypes),
          const SizedBox(height: 16),
          if (_spaces.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No spaces added yet.',
                style: TextStyle(color: AppTheme.textSecondary(context)),
              ),
            )
          else
            Column(
              children: List.generate(
                _spaces.length,
                (i) => _buildSpaceCard(i),
              ),
            ),
          const SizedBox(height: 12),
          AiSuggestionsSection(controller: _aiCtrl),
          const SizedBox(height: 12),
          Text(
            'Property Features',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          ...catalog.featureCategories.entries
              .map((e) => _buildFeatureCategory(e.key, e.value)),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildAddSpaceDropdown(List<String> availableTypes) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.surface2(context)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          hint: Text(
            'Add a space',
            style: TextStyle(color: AppTheme.textSecondary(context)),
          ),
          dropdownColor: AppTheme.surface(context),
          value: null,
          items: availableTypes
              .map((t) => DropdownMenuItem(
                    value: t,
                    child: Row(
                      children: [
                        Icon(_iconForType(t), size: 18, color: AppTheme.brand),
                        const SizedBox(width: 8),
                        Text(
                          titleCaseLabel(t),
                          style:
                              TextStyle(color: AppTheme.textPrimary(context)),
                        ),
                      ],
                    ),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) _addSpace(v);
          },
        ),
      ),
    );
  }

  Widget _buildSpaceCard(int index) {
    final space = _spaces[index];
    final delta = _isHalfUnit(space.type) ? 0.5 : 1.0;
    final totalFeatureCount = space.featuresAll.length +
        space.units.fold<int>(0, (a, u) => a + u.features.length);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.surface2(context)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: () => _openFeaturePicker(index),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              Icon(_iconForType(space.type), color: AppTheme.brand),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleCaseLabel(space.type),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    if (totalFeatureCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '$totalFeatureCount feature${totalFeatureCount == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed:
                    space.count > 0 ? () => _stepCount(index, -delta) : null,
                icon: const Icon(Icons.remove_circle_outline),
                color: AppTheme.brand,
                visualDensity: VisualDensity.compact,
              ),
              SizedBox(
                width: 32,
                child: Text(
                  _formatCount(space.count),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _stepCount(index, delta),
                icon: const Icon(Icons.add_circle_outline),
                color: AppTheme.brand,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: () => _removeSpace(index),
                icon: const Icon(Icons.close, size: 18),
                color: AppTheme.textSecondary(context),
                visualDensity: VisualDensity.compact,
                tooltip: 'Remove',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCategory(String key, FeatureCategory cat) {
    final selectedCount = (_features[key] ?? const []).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.surface2(context)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: AppTheme.brand,
          collapsedIconColor: AppTheme.brand,
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(
            cat.label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary(context),
            ),
          ),
          subtitle: Text(
            '$selectedCount selected',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary(context),
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: cat.features.map((f) {
                final list = _features[key] ?? <String>[];
                final selected = list.contains(f);
                return FilterChip(
                  label: Text(titleCaseLabel(f)),
                  selected: selected,
                  onSelected: (_) {
                    setState(() {
                      final current = _features[key] ?? <String>[];
                      if (selected) {
                        current.remove(f);
                      } else {
                        current.add(f);
                      }
                      _features[key] = current;
                      _dirty = true;
                    });
                  },
                  backgroundColor: AppTheme.surface2(context),
                  selectedColor: AppTheme.brand,
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color:
                        selected ? Colors.white : AppTheme.textPrimary(context),
                  ),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
