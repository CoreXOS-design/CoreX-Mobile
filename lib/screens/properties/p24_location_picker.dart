import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/p24_location.dart';
import '../../services/api_service.dart';
import '../../theme.dart';

/// The three chosen ids plus whether the user has touched the picker.
/// `dirty` lets the edit screen omit `p24_*` from a PUT when location was
/// left untouched (so the server leaves the existing location alone).
class P24Selection {
  final int? provinceId;
  final int? cityId;
  final int? suburbId;
  final bool dirty;

  const P24Selection({
    this.provinceId,
    this.cityId,
    this.suburbId,
    this.dirty = false,
  });
}

/// Province → City → Suburb cascading selector backed by
/// `/api/v1/mobile/p24/*`. Mirrors the web app: City is locked until a
/// Province is picked, Suburb until a City is picked, and changing a
/// higher level clears everything below it.
///
/// Each level opens a searchable sheet that re-queries with `&q=` so the
/// long suburb lists stay usable.
class P24LocationPicker extends StatefulWidget {
  final int? initialProvinceId;
  final int? initialCityId;
  final int? initialSuburbId;

  /// When true (or the suburb id is null on edit) the suburb starts empty
  /// in a "please select" state even if province/city resolve.
  final bool suburbMismatch;

  /// Server-side validation message for `p24_suburb_id`, shown under the
  /// suburb field.
  final String? suburbError;

  final ValueChanged<P24Selection> onChanged;

  const P24LocationPicker({
    super.key,
    this.initialProvinceId,
    this.initialCityId,
    this.initialSuburbId,
    this.suburbMismatch = false,
    this.suburbError,
    required this.onChanged,
  });

  @override
  State<P24LocationPicker> createState() => _P24LocationPickerState();
}

class _P24LocationPickerState extends State<P24LocationPicker> {
  final _api = ApiService();

  P24Location? _province;
  P24Location? _city;
  P24Location? _suburb;

  bool _dirty = false;
  bool _prefilling = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialProvinceId != null) {
      _prefill();
    }
  }

  /// Resolve the stored ids back into named [P24Location]s so the fields
  /// render labels. Does not mark the picker dirty. If the suburb is a
  /// mismatch or absent we resolve province/city only and leave suburb
  /// empty for the agent to fix.
  Future<void> _prefill() async {
    setState(() => _prefilling = true);
    try {
      final provinces = await _api.getP24Provinces();
      final prov = _firstOrNull(provinces, widget.initialProvinceId);
      if (prov == null) return;
      P24Location? city;
      P24Location? suburb;
      if (widget.initialCityId != null) {
        final cities = await _api.getP24Cities(provinceId: prov.id);
        city = _firstOrNull(cities, widget.initialCityId);
      }
      if (city != null &&
          widget.initialSuburbId != null &&
          !widget.suburbMismatch) {
        final suburbs = await _api.getP24Suburbs(cityId: city.id);
        suburb = _firstOrNull(suburbs, widget.initialSuburbId);
      }
      if (!mounted) return;
      setState(() {
        _province = prov;
        _city = city;
        _suburb = suburb;
      });
    } catch (_) {
      // Non-fatal — the agent can still pick from scratch.
    } finally {
      if (mounted) setState(() => _prefilling = false);
    }
  }

  P24Location? _firstOrNull(List<P24Location> list, int? id) {
    for (final l in list) {
      if (l.id == id) return l;
    }
    return null;
  }

  void _emit() {
    widget.onChanged(P24Selection(
      provinceId: _province?.id,
      cityId: _city?.id,
      suburbId: _suburb?.id,
      dirty: _dirty,
    ));
  }

  Future<void> _pickProvince() async {
    final picked = await _openSheet(
      title: 'Select Province',
      loader: (q) => _api.getP24Provinces(q: q),
    );
    if (picked == null || picked.id == _province?.id) return;
    setState(() {
      _province = picked;
      _city = null;
      _suburb = null;
      _dirty = true;
    });
    _emit();
  }

  Future<void> _pickCity() async {
    final prov = _province;
    if (prov == null) return;
    final picked = await _openSheet(
      title: 'Select City',
      loader: (q) => _api.getP24Cities(provinceId: prov.id, q: q),
    );
    if (picked == null || picked.id == _city?.id) return;
    setState(() {
      _city = picked;
      _suburb = null;
      _dirty = true;
    });
    _emit();
  }

  Future<void> _pickSuburb() async {
    final city = _city;
    if (city == null) return;
    final picked = await _openSheet(
      title: 'Select Suburb',
      loader: (q) => _api.getP24Suburbs(cityId: city.id, q: q),
    );
    if (picked == null || picked.id == _suburb?.id) return;
    setState(() {
      _suburb = picked;
      _dirty = true;
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Province *', required: true),
        _selectField(
          value: _province?.name,
          hint: _prefilling ? 'Loading…' : 'Select province',
          enabled: !_prefilling,
          onTap: _pickProvince,
        ),
        _label('City *', required: true),
        _selectField(
          value: _city?.name,
          hint: _province == null ? 'Select a province first' : 'Select city',
          enabled: _province != null && !_prefilling,
          onTap: _pickCity,
        ),
        _label('Suburb *', required: true),
        _selectField(
          value: _suburb?.name,
          hint: _city == null ? 'Select a city first' : 'Select suburb',
          enabled: _city != null && !_prefilling,
          onTap: _pickSuburb,
          hasError: widget.suburbError != null,
        ),
        if (widget.suburbError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              widget.suburbError!,
              style: TextStyle(fontSize: 11, color: Colors.red.shade400),
            ),
          ),
      ],
    );
  }

  Widget _label(String text, {bool required = false}) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: RichText(
          text: TextSpan(
            text: text.replaceAll(' *', ''),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary(context),
            ),
            children: required
                ? const [
                    TextSpan(
                        text: ' *',
                        style: TextStyle(color: Colors.redAccent)),
                  ]
                : const [],
          ),
        ),
      );

  Widget _selectField({
    required String? value,
    required String hint,
    required bool enabled,
    required VoidCallback onTap,
    bool hasError = false,
  }) {
    final hasValue = value != null && value.isNotEmpty;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: InputDecorator(
          decoration: InputDecoration(
            errorText: hasError ? '' : null,
            errorStyle: const TextStyle(height: 0, fontSize: 0),
            suffixIcon: const Icon(Icons.arrow_drop_down),
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

/// Searchable list sheet. Loads on open and re-queries (debounced) as the
/// user types so long suburb lists are navigable via `&q=`.
class _P24SearchSheet extends StatefulWidget {
  final String title;
  final Future<List<P24Location>> Function(String q) loader;

  const _P24SearchSheet({required this.title, required this.loader});

  @override
  State<_P24SearchSheet> createState() => _P24SearchSheetState();
}

class _P24SearchSheetState extends State<_P24SearchSheet> {
  final _searchController = TextEditingController();
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
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String q) {
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
                controller: _searchController,
                autofocus: true,
                onChanged: _onSearchChanged,
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                style: TextStyle(color: AppTheme.textSecondary(context))),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _query(_searchController.text),
              child: const Text('Retry'),
            ),
          ],
        ),
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
