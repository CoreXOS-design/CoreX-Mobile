import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/client_models.dart';
import '../../services/api_service.dart' show ApiException;
import '../../services/client_auth_service.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../widgets/corex/corex_primary_button.dart';
import '../../widgets/corex/corex_scaffold.dart';
import '../../widgets/p24_suburbs_picker.dart';

/// Used in both create and edit modes — pass [existing] for edit, omit for create.
class ClientMatchEditScreen extends StatefulWidget {
  final ClientMatch? existing;
  const ClientMatchEditScreen({super.key, this.existing});

  bool get isEdit => existing != null;

  @override
  State<ClientMatchEditScreen> createState() => _ClientMatchEditScreenState();
}

class _ClientMatchEditScreenState extends State<ClientMatchEditScreen> {
  final _api = ClientAuthService();

  bool _loadingOptions = true;
  String? _optionsError;
  ClientMatchOptions _options = ClientMatchOptions();

  bool _saving = false;
  Map<String, String> _fieldErrors = {};

  late TextEditingController _name;
  late TextEditingController _priceMin;
  late TextEditingController _priceMax;
  late TextEditingController _notes;

  String? _listingType; // 'sale' | 'rental'
  String? _propertyType; // null = Any
  String? _category;
  int _bedsMin = 0;
  int _bathsMin = 0;
  int _garagesMin = 0;
  List<int> _p24SuburbIds = [];
  List<String> _p24SuburbNames = [];

  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    _name = TextEditingController(text: m?.name ?? '');
    _priceMin = TextEditingController(
        text: m?.priceMin != null ? m!.priceMin!.round().toString() : '');
    _priceMax = TextEditingController(
        text: m?.priceMax != null ? m!.priceMax!.round().toString() : '');
    _notes = TextEditingController(text: m?.notes ?? '');

    _listingType = m?.listingType;
    _propertyType = m?.propertyType;
    _category = m?.category ?? (widget.isEdit ? null : 'Residential');
    _bedsMin = m?.bedsMin ?? 0;
    _bathsMin = m?.bathsMin ?? 0;
    _garagesMin = m?.garagesMin ?? 0;
    if (m != null) {
      _p24SuburbIds = [...m.p24SuburbIds];
      // m.suburbs is index-aligned with m.p24SuburbIds (server-synced).
      _p24SuburbNames = [
        for (var i = 0; i < _p24SuburbIds.length; i++)
          i < m.suburbs.length ? m.suburbs[i] : 'Suburb ${_p24SuburbIds[i]}'
      ];
    }

    _loadOptions();
  }

  @override
  void dispose() {
    _name.dispose();
    _priceMin.dispose();
    _priceMax.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loadingOptions = true;
      _optionsError = null;
    });
    try {
      final o = await _api.matchOptions();
      if (!mounted) return;
      setState(() {
        _options = o;
        _loadingOptions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingOptions = false;
        _optionsError = e.toString();
      });
    }
  }

  ClientMatchInput _buildInput() {
    num? toNum(String s) {
      final cleaned = s.replaceAll(RegExp(r'[^0-9.]'), '');
      if (cleaned.isEmpty) return null;
      return num.tryParse(cleaned);
    }

    return ClientMatchInput(
      name: _name.text.trim().isEmpty ? null : _name.text.trim(),
      listingType: _listingType,
      category: _category,
      propertyType: _propertyType,
      priceMin: toNum(_priceMin.text),
      priceMax: toNum(_priceMax.text),
      bedsMin: _bedsMin > 0 ? _bedsMin : null,
      bathsMin: _bathsMin > 0 ? _bathsMin : null,
      garagesMin: _garagesMin > 0 ? _garagesMin : null,
      p24SuburbIds: _p24SuburbIds,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
  }

  Future<void> _save() async {
    if (!widget.isEdit && (_listingType == null || _listingType!.isEmpty)) {
      setState(() {
        _fieldErrors = {'listing_type': 'Please choose Buy or Rent'};
      });
      return;
    }
    setState(() {
      _saving = true;
      _fieldErrors = {};
    });
    try {
      if (widget.isEdit) {
        await _api.updateMatch(widget.existing!.id, _buildInput());
      } else {
        await _api.createMatch(_buildInput());
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _fieldErrors = _parseErrors(e);
      });
      if (_fieldErrors.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  Map<String, String> _parseErrors(ApiException e) {
    // ApiException only carries the message; for full Laravel field errors we'd
    // need the body. For now surface the generic message via snackbar.
    return {};
  }

  @override
  Widget build(BuildContext context) {
    return CorexScaffold(
      title: widget.isEdit ? 'Edit search' : 'Set up my search',
      actions: [
        TextButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
      body: SafeArea(
        top: false,
        child: _loadingOptions
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_optionsError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Could not load options: $_optionsError',
                        style: TextStyle(
                            color: CorexTokens.textSecondary(context)),
                      ),
                    ),
                  _section('Looking to'),
                  _segmented(
                    value: _listingType,
                    options: const [
                      ('sale', 'Buy'),
                      ('rental', 'Rent'),
                    ],
                    onChanged: (v) => setState(() => _listingType = v),
                  ),
                  if (_fieldErrors['listing_type'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _fieldErrors['listing_type']!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  _section('Property type'),
                  _dropdown(
                    value: _propertyType,
                    items: _options.propertyTypes,
                    onChanged: (v) => setState(() => _propertyType = v),
                  ),
                  _section('Category'),
                  _dropdown(
                    value: _category,
                    items: _options.categories.isEmpty
                        ? const ['Residential', 'Commercial', 'Agricultural']
                        : _options.categories,
                    onChanged: (v) => setState(() => _category = v),
                  ),
                  _section('Price (ZAR)'),
                  Row(
                    children: [
                      Expanded(child: _moneyField(_priceMin, 'Min')),
                      const SizedBox(width: 12),
                      Expanded(child: _moneyField(_priceMax, 'Max')),
                    ],
                  ),
                  _section('Beds'),
                  _stepper(_bedsMin, (v) => setState(() => _bedsMin = v)),
                  _section('Baths'),
                  _stepper(_bathsMin, (v) => setState(() => _bathsMin = v)),
                  _section('Garages'),
                  _stepper(_garagesMin, (v) => setState(() => _garagesMin = v)),
                  _section('Suburbs'),
                  _suburbsPicker(),
                  _section('Notes'),
                  TextField(
                    controller: _notes,
                    maxLines: 3,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Anything else we should know?',
                    ),
                  ),
                  _section('Name (optional)'),
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Beach house under R2.5m',
                    ),
                  ),
                  const SizedBox(height: 24),
                  CorexPrimaryButton(
                    label: widget.isEdit ? 'Save changes' : 'Create search',
                    loading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
      ),
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 6),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: CorexTokens.textSecondary(context),
          ),
        ),
      );

  Widget _segmented({
    required String? value,
    required List<(String, String)> options,
    required ValueChanged<String?> onChanged,
  }) {
    final accent = CorexAccentTheme.of(context).accent;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(CorexTokens.radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: options.map((o) {
          final selected = value == o.$1;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(CorexTokens.radius),
              onTap: () => onChanged(o.$1),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(CorexTokens.radius),
                ),
                child: Text(
                  o.$2,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? Colors.white
                        : CorexTokens.textPrimary(context),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _dropdown({
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Any')),
        ...items
            .map((e) => DropdownMenuItem<String?>(value: e, child: Text(e))),
      ],
      onChanged: onChanged,
    );
  }

  Widget _moneyField(TextEditingController c, String hint) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        prefixText: 'R ',
        hintText: hint,
      ),
      onEditingComplete: () {
        final n = num.tryParse(c.text);
        if (n != null) {
          c.text = _money(n);
          c.selection = TextSelection.collapsed(offset: c.text.length);
        }
      },
    );
  }

  Widget _stepper(int value, ValueChanged<int> onChanged) {
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        const SizedBox(width: 8),
        Container(
          width: 48,
          alignment: Alignment.center,
          child: Text(
            value == 0 ? 'Any' : '$value+',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: value < 10 ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }

  Widget _suburbsPicker() {
    return P24SuburbsPicker(
      initialIds: _p24SuburbIds,
      initialNames: _p24SuburbNames,
      // Authenticate the P24 cascade as the signed-in client (the default
      // ApiService loaders use the agent token, which a client doesn't have).
      provincesLoader: (q) => _api.getP24Provinces(q: q),
      citiesLoader: (provinceId, q) =>
          _api.getP24Cities(provinceId: provinceId, q: q),
      suburbsLoader: (cityId, q) => _api.getP24Suburbs(cityId: cityId, q: q),
      onChanged: (ids, names) {
        setState(() {
          _p24SuburbIds = ids;
          _p24SuburbNames = names;
        });
      },
    );
  }

  static String _money(num n) {
    final s = n.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      buf.write(s[i]);
      if (fromEnd > 1 && (fromEnd - 1) % 3 == 0) buf.write(' ');
    }
    return buf.toString();
  }
}
