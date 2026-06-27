import 'package:flutter/material.dart';
import '../../models/core_match.dart';
import '../../services/api_service.dart';
import '../../theme.dart';
import '../../widgets/p24_suburbs_picker.dart';

const Color _kDanger = Color(0xFFDC2626);

class CoreMatchEditScreen extends StatefulWidget {
  final CoreMatch match;
  const CoreMatchEditScreen({super.key, required this.match});

  @override
  State<CoreMatchEditScreen> createState() => _CoreMatchEditScreenState();
}

class _CoreMatchEditScreenState extends State<CoreMatchEditScreen> {
  final ApiService _api = ApiService();

  late String _listingType;
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _propertyType;
  late final TextEditingController _priceMin;
  late final TextEditingController _priceMax;
  late final TextEditingController _bedsMin;
  late final TextEditingController _bathsMin;
  late final TextEditingController _garagesMin;
  late final TextEditingController _notes;
  final _featureInput = TextEditingController();
  late List<int> _p24SuburbIds;
  late List<String> _p24SuburbNames;
  late final List<String> _features;
  bool _saving = false;
  Map<String, String> _fieldErrors = const {};

  @override
  void initState() {
    super.initState();
    final m = widget.match;
    _listingType = m.listingType ?? 'sale';
    _name = TextEditingController(text: m.name ?? '');
    _category = TextEditingController(text: m.category ?? '');
    _propertyType = TextEditingController(text: m.propertyType ?? '');
    _priceMin = TextEditingController(text: m.priceMin?.toString() ?? '');
    _priceMax = TextEditingController(text: m.priceMax?.toString() ?? '');
    _bedsMin = TextEditingController(text: m.bedsMin?.toString() ?? '');
    _bathsMin = TextEditingController(text: m.bathsMin?.toString() ?? '');
    _garagesMin = TextEditingController(text: m.garagesMin?.toString() ?? '');
    _notes = TextEditingController(text: m.notes ?? '');
    _p24SuburbIds = [...m.p24SuburbIds];
    // Server returns suburbs index-aligned with p24_suburb_ids; trust that
    // for display, and the IDs for submission.
    _p24SuburbNames = [
      for (var i = 0; i < _p24SuburbIds.length; i++)
        i < m.suburbs.length ? m.suburbs[i] : 'Suburb ${_p24SuburbIds[i]}'
    ];
    _features = [...m.mustHaveFeatures];
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _propertyType.dispose();
    _priceMin.dispose();
    _priceMax.dispose();
    _bedsMin.dispose();
    _bathsMin.dispose();
    _garagesMin.dispose();
    _notes.dispose();
    _featureInput.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _fieldErrors = const {};
    });

    int? n(TextEditingController c) {
      final t = c.text.trim();
      if (t.isEmpty) return null;
      return int.tryParse(t.replaceAll(RegExp(r'[^0-9-]'), ''));
    }

    String? s(TextEditingController c) {
      final t = c.text.trim();
      return t.isEmpty ? null : t;
    }

    final body = <String, dynamic>{
      'listing_type': _listingType,
      'name': s(_name),
      'category': s(_category),
      'property_type': s(_propertyType),
      'price_min': n(_priceMin),
      'price_max': n(_priceMax),
      'beds_min': n(_bedsMin),
      'baths_min': n(_bathsMin),
      'garages_min': n(_garagesMin),
      // suburb / suburbs are rejected by the validator — send IDs only.
      'p24_suburb_ids': _p24SuburbIds,
      'must_have_features': _features,
      'notes': s(_notes),
    };

    try {
      await _api.updateCoreMatch(widget.match.id, body);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _fieldErrors = e.fieldErrors;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  void _addFeature() {
    final t = _featureInput.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _features.add(t);
      _featureInput.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Match')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          _label('Listing Type', required: true),
          Wrap(spacing: 8, children: [
            _seg('sale', 'For Sale'),
            _seg('rental', 'For Rental'),
          ]),
          _label('Name'),
          _field(_name, 'name'),
          _label('Category'),
          _field(_category, 'category'),
          _label('Property Type'),
          _field(_propertyType, 'property_type'),
          Row(children: [
            Expanded(child: _col('Price Min', _priceMin, 'price_min', num: true)),
            const SizedBox(width: 12),
            Expanded(child: _col('Price Max', _priceMax, 'price_max', num: true)),
          ]),
          Row(children: [
            Expanded(child: _col('Beds Min', _bedsMin, 'beds_min', num: true)),
            const SizedBox(width: 12),
            Expanded(child: _col('Baths Min', _bathsMin, 'baths_min', num: true)),
          ]),
          _col('Garages Min', _garagesMin, 'garages_min', num: true),
          _label('Suburbs'),
          P24SuburbsPicker(
            initialIds: _p24SuburbIds,
            initialNames: _p24SuburbNames,
            errorText: _fieldErrors['p24_suburb_ids'],
            onChanged: (ids, names) {
              setState(() {
                _p24SuburbIds = ids;
                _p24SuburbNames = names;
                if (_fieldErrors.containsKey('p24_suburb_ids')) {
                  _fieldErrors = {..._fieldErrors}..remove('p24_suburb_ids');
                }
              });
            },
          ),
          _label('Must-have Features'),
          _chipInput(_featureInput, _addFeature),
          if (_features.isNotEmpty) _chipList(_features),
          _label('Notes'),
          TextField(
            controller: _notes,
            maxLines: 3,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(errorText: _fieldErrors['notes']),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save Changes'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _col(String l, TextEditingController c, String f, {bool num = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(l),
        _field(c, f,
            keyboard: num ? TextInputType.number : null,
            action: TextInputAction.next),
      ],
    );
  }

  Widget _chipInput(TextEditingController c, VoidCallback onAdd) => Row(
        children: [
          Expanded(
            child: TextField(
              controller: c,
              decoration: const InputDecoration(hintText: 'Add…'),
              onSubmitted: (_) => onAdd(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.add_rounded, color: AppTheme.brand),
            onPressed: onAdd,
          ),
        ],
      );

  Widget _chipList(List<String> items) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < items.length; i++)
              Chip(
                label: Text(items[i]),
                // Remove by index so duplicate feature labels delete the
                // chip the user actually tapped, not the first match.
                onDeleted: () => setState(() => items.removeAt(i)),
              ),
          ],
        ),
      );

  Widget _seg(String value, String label) {
    final selected = _listingType == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _listingType = value),
      backgroundColor: AppTheme.surface2(context),
      selectedColor: AppTheme.brand,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppTheme.textPrimary(context),
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide.none,
    );
  }

  Widget _label(String text, {bool required = false}) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: RichText(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary(context),
            ),
            children: required
                ? const [
                    TextSpan(
                      text: ' *',
                      style: TextStyle(
                          color: _kDanger, fontWeight: FontWeight.w600),
                    ),
                  ]
                : const [],
          ),
        ),
      );

  Widget _field(TextEditingController c, String field,
      {TextInputType? keyboard, TextInputAction? action}) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      textInputAction: action,
      decoration: InputDecoration(errorText: _fieldErrors[field]),
      onChanged: (_) {
        if (_fieldErrors.containsKey(field)) {
          setState(() => _fieldErrors = {..._fieldErrors}..remove(field));
        }
      },
    );
  }
}
