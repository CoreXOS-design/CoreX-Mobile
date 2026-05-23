import 'dart:async';
import 'package:flutter/material.dart';
import '../models/p24_location.dart';
import '../services/api_service.dart';
import '../theme.dart';

/// Cascading Property24 picker for a wishlist's location filter.
///
/// Province and City are single-select cascading parents (changing one clears
/// children). Suburbs is multi-select chips — already-picked chips survive
/// when the agent switches province/city to add more, since a wishlist can
/// target suburbs across multiple cities.
///
/// Backed by `/api/mobile/p24/*` — the SAME cascade the property create
/// screen uses, so the suburb `id` submitted as `p24_suburb_ids` is
/// identical to the `p24_suburb_id` stored on a property —
/// the same value submitted as `p24_suburb_ids` and matched against
/// `properties.p24_suburb_id`.
class P24SuburbsPicker extends StatefulWidget {
  /// Initial p24_suburb_ids (from match) zipped with their display names
  /// (from match.suburbs — index-aligned, server-synced). Both lists must be
  /// the same length.
  final List<int> initialIds;
  final List<String> initialNames;

  /// Fires whenever the selection changes. The two lists are index-aligned.
  final void Function(List<int> ids, List<String> names) onChanged;

  final String? errorText;

  const P24SuburbsPicker({
    super.key,
    this.initialIds = const [],
    this.initialNames = const [],
    this.errorText,
    required this.onChanged,
  });

  @override
  State<P24SuburbsPicker> createState() => _P24SuburbsPickerState();
}

class _P24SuburbsPickerState extends State<P24SuburbsPicker> {
  final _api = ApiService();

  // id -> name. Insertion-ordered (LinkedHashMap) so chip order is stable.
  final Map<int, String> _selected = {};

  P24Location? _province;
  P24Location? _city;

  @override
  void initState() {
    super.initState();
    final n = widget.initialIds.length;
    for (var i = 0; i < n; i++) {
      final id = widget.initialIds[i];
      final name =
          i < widget.initialNames.length ? widget.initialNames[i] : 'Suburb $id';
      _selected[id] = name;
    }
  }

  void _emit() {
    widget.onChanged(
      _selected.keys.toList(),
      _selected.values.toList(),
    );
  }

  Future<void> _pickProvince() async {
    final picked = await _openSheet(
      title: 'Select Province',
      loader: (q) => _api.getP24Provinces(q: q),
    );
    if (picked == null || picked.id == _province?.id) return;
    setState(() {
      _province = picked;
      _city = null; // cascade clear
    });
  }

  Future<void> _pickCity() async {
    final prov = _province;
    if (prov == null) return;
    final picked = await _openSheet(
      title: 'Select City',
      loader: (q) => _api.getP24Cities(provinceId: prov.id, q: q),
    );
    if (picked == null || picked.id == _city?.id) return;
    setState(() => _city = picked);
  }

  Future<void> _addSuburbs() async {
    final city = _city;
    if (city == null) return;
    final picked = await showModalBottomSheet<List<P24Location>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _P24SuburbsMultiSheet(
        cityName: city.name,
        loader: (q) => _api.getP24Suburbs(cityId: city.id, q: q),
        preselectedIds: _selected.keys.toSet(),
      ),
    );
    if (picked == null) return;
    setState(() {
      for (final s in picked) {
        _selected[s.id] = s.name;
      }
    });
    _emit();
  }

  Future<P24Location?> _openSheet({
    required String title,
    required Future<List<P24Location>> Function(String q) loader,
  }) {
    return showModalBottomSheet<P24Location>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _P24SearchSheet(title: title, loader: loader),
    );
  }

  void _removeChip(int id) {
    setState(() => _selected.remove(id));
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Currently-selected suburb chips (survive province/city changes).
        if (_selected.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _selected.entries
                .map((e) => InputChip(
                      label: Text(e.value),
                      onDeleted: () => _removeChip(e.key),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
        ] else
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'No suburbs selected — matches will be unconstrained by location.',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ),
        _label('Province'),
        _selectField(
          value: _province?.name,
          hint: 'Select province',
          enabled: true,
          onTap: _pickProvince,
        ),
        _label('City'),
        _selectField(
          value: _city?.name,
          hint: _province == null ? 'Select a province first' : 'Select city',
          enabled: _province != null,
          onTap: _pickCity,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _city == null ? null : _addSuburbs,
            icon: const Icon(Icons.add_location_alt_outlined),
            label: Text(_city == null
                ? 'Pick a city to add suburbs'
                : 'Add suburbs in ${_city!.name}'),
          ),
        ),
        if (widget.errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              widget.errorText!,
              style: TextStyle(fontSize: 12, color: Colors.red.shade400),
            ),
          ),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppTheme.textSecondary(context),
          ),
        ),
      );

  Widget _selectField({
    required String? value,
    required String hint,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final hasValue = value != null && value.isNotEmpty;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: InputDecorator(
          decoration: const InputDecoration(
            suffixIcon: Icon(Icons.arrow_drop_down),
          ),
          child: Text(
            hasValue ? value : hint,
            style: TextStyle(
              color: hasValue
                  ? AppTheme.textPrimary(context)
                  : AppTheme.textMuted(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _P24SearchSheet extends StatefulWidget {
  final String title;
  final Future<List<P24Location>> Function(String q) loader;
  const _P24SearchSheet({required this.title, required this.loader});

  @override
  State<_P24SearchSheet> createState() => _P24SearchSheetState();
}

class _P24SearchSheetState extends State<_P24SearchSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<P24Location> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _query('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _query(q));
  }

  Future<void> _query(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.loader(q.trim());
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load list — try again';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.borderColor(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: _onChanged,
                decoration: const InputDecoration(
                  hintText: 'Search…',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!,
              style: TextStyle(color: AppTheme.textSecondary(context))),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _query(_search.text),
            child: const Text('Retry'),
          ),
        ]),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text('No matches',
            style: TextStyle(color: AppTheme.textSecondary(context))),
      );
    }
    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: AppTheme.borderColor(context)),
      itemBuilder: (_, i) {
        final item = _items[i];
        return ListTile(
          title: Text(item.name,
              style: TextStyle(color: AppTheme.textPrimary(context))),
          onTap: () => Navigator.of(context).pop(item),
        );
      },
    );
  }
}

/// Multi-select suburb sheet — checkbox list, returns the full set picked
/// on Done. Pre-checks suburbs the user has already added so the sheet
/// reflects existing state.
class _P24SuburbsMultiSheet extends StatefulWidget {
  final String cityName;
  final Future<List<P24Location>> Function(String q) loader;
  final Set<int> preselectedIds;

  const _P24SuburbsMultiSheet({
    required this.cityName,
    required this.loader,
    required this.preselectedIds,
  });

  @override
  State<_P24SuburbsMultiSheet> createState() => _P24SuburbsMultiSheetState();
}

class _P24SuburbsMultiSheetState extends State<_P24SuburbsMultiSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<P24Location> _items = [];
  bool _loading = true;
  String? _error;
  final Map<int, P24Location> _picked = {};

  @override
  void initState() {
    super.initState();
    _query('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _query(q));
  }

  Future<void> _query(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.loader(q.trim());
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load list — try again';
        _loading = false;
      });
    }
  }

  bool _isChecked(P24Location s) =>
      _picked.containsKey(s.id) || widget.preselectedIds.contains(s.id);

  void _toggle(P24Location s, bool? v) {
    setState(() {
      if (v == true) {
        _picked[s.id] = s;
      } else {
        _picked.remove(s.id);
      }
    });
  }

  void _done() {
    // Only return newly-picked ones; the picker merges them with existing.
    Navigator.of(context).pop(_picked.values.toList());
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.borderColor(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Suburbs in ${widget.cityName}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _done,
                    child: Text(_picked.isEmpty
                        ? 'Done'
                        : 'Add ${_picked.length}'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: _onChanged,
                decoration: const InputDecoration(
                  hintText: 'Search suburbs…',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!,
              style: TextStyle(color: AppTheme.textSecondary(context))),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _query(_search.text),
            child: const Text('Retry'),
          ),
        ]),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text('No matches',
            style: TextStyle(color: AppTheme.textSecondary(context))),
      );
    }
    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: AppTheme.borderColor(context)),
      itemBuilder: (_, i) {
        final s = _items[i];
        final preexisting = widget.preselectedIds.contains(s.id);
        return CheckboxListTile(
          value: _isChecked(s),
          // Already-locked-in suburbs can't be unchecked from this sheet —
          // remove them via the chip × on the form instead.
          onChanged: preexisting ? null : (v) => _toggle(s, v),
          title: Text(s.name,
              style: TextStyle(color: AppTheme.textPrimary(context))),
          subtitle: preexisting
              ? Text('Already added',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary(context)))
              : null,
        );
      },
    );
  }
}
