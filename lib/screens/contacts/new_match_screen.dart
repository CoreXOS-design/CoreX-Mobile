import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../theme.dart';
import '../../widgets/p24_suburbs_picker.dart';

class NewMatchScreen extends StatefulWidget {
  final int contactId;
  const NewMatchScreen({super.key, required this.contactId});

  @override
  State<NewMatchScreen> createState() => _NewMatchScreenState();
}

class _NewMatchScreenState extends State<NewMatchScreen> {
  final ApiService _api = ApiService();

  String _listingType = 'sale';
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _propertyType = TextEditingController();
  final _priceMin = TextEditingController();
  final _priceMax = TextEditingController();
  final _bedsMin = TextEditingController();
  final _bathsMin = TextEditingController();
  final _notes = TextEditingController();
  List<int> _p24SuburbIds = [];
  List<String> _p24SuburbNames = [];
  bool _saving = false;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _propertyType.dispose();
    _priceMin.dispose();
    _priceMax.dispose();
    _bedsMin.dispose();
    _bathsMin.dispose();
    _notes.dispose();
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
      if (s(_name) != null) 'name': s(_name),
      if (s(_category) != null) 'category': s(_category),
      if (s(_propertyType) != null) 'property_type': s(_propertyType),
      if (n(_priceMin) != null) 'price_min': n(_priceMin),
      if (n(_priceMax) != null) 'price_max': n(_priceMax),
      if (n(_bedsMin) != null) 'beds_min': n(_bedsMin),
      if (n(_bathsMin) != null) 'baths_min': n(_bathsMin),
      // Submit P24 suburb IDs only — same source as property suburbs.
      'p24_suburb_ids': _p24SuburbIds,
      if (s(_notes) != null) 'notes': s(_notes),
    };

    try {
      await _api.createMatch(widget.contactId, body);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Match')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
          _label('Listing Type *'),
          Wrap(
            spacing: 8,
            children: [
              _seg('sale', 'For Sale'),
              _seg('rental', 'For Rental'),
            ],
          ),
          if (_fieldErrors['listing_type'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_fieldErrors['listing_type']!,
                  style: TextStyle(fontSize: 11, color: Colors.red.shade400)),
            ),
          _label('Name'),
          _field(_name, 'name'),
          _label('Category'),
          _field(_category, 'category'),
          _label('Property Type'),
          _field(_propertyType, 'property_type'),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Price Min'),
                    _field(_priceMin, 'price_min',
                        keyboard: TextInputType.number),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Price Max'),
                    _field(_priceMax, 'price_max',
                        keyboard: TextInputType.number),
                  ],
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Beds Min'),
                    _field(_bedsMin, 'beds_min',
                        keyboard: TextInputType.number),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Baths Min'),
                    _field(_bathsMin, 'baths_min',
                        keyboard: TextInputType.number),
                  ],
                ),
              ),
            ],
          ),
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
          _label('Notes'),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: InputDecoration(errorText: _fieldErrors['notes']),
          ),
          const SizedBox(height: 24),
          SizedBox(
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
                  : const Text('Create Match'),
            ),
          ),
          ],
        ),
      ),
    );
  }

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

  Widget _field(TextEditingController c, String field,
      {TextInputType? keyboard}) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      decoration: InputDecoration(errorText: _fieldErrors[field]),
      onChanged: (_) {
        if (_fieldErrors.containsKey(field)) {
          setState(() => _fieldErrors = {..._fieldErrors}..remove(field));
        }
      },
    );
  }
}
