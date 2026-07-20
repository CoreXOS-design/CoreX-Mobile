import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/gallery_tags.dart';
import '../../models/property_options.dart';
import '../../providers/property_provider.dart';
import '../../services/api_service.dart';
import '../../theme.dart';
import 'gallery_upload_sheet.dart';
import 'p24_location_picker.dart';
import 'property_option_dropdown.dart';
import 'spaces_editor_section.dart';

/// One required field that's currently empty. Used by the
/// "Missing Required Fields" modal.
class _MissingField {
  final String label;
  // ignore: unused_element_parameter
  final String fieldName;
  final GlobalKey? key;
  final int step;
  const _MissingField(this.label, this.fieldName, this.key, this.step);
}

/// New-property wizard. Mirrors [PropertyEditScreen] exactly: four steps
/// (Address → Details → Spaces → Gallery), same dropdowns, same spaces
/// editor, same tag-aware uploader.
///
/// The only structural difference is that Spaces and Gallery need a real
/// property_id on the server. So: when the user taps "Next" on the Details
/// step for the first time, we POST to create the property, store the new
/// id, and use it for the rest of the wizard. Subsequent forward moves
/// from Address/Details PUT to update that same record.
class PropertyCreateScreen extends StatefulWidget {
  /// Optional contact link — when set, the very first POST to
  /// `/v1/mobile/properties` carries `link_contact_id` + `link_contact_role`
  /// so the new property is auto-linked to that contact.
  final int? linkContactId;
  final String? linkContactRole;

  const PropertyCreateScreen({
    super.key,
    this.linkContactId,
    this.linkContactRole,
  });

  @override
  State<PropertyCreateScreen> createState() => _PropertyCreateScreenState();
}

class _PropertyCreateScreenState extends State<PropertyCreateScreen> {
  final _pageController = PageController();
  final _spacesKey = GlobalKey<SpacesEditorSectionState>();
  final ApiService _api = ApiService();

  int _currentStep = 0;

  /// Non-null after the first successful POST to `/v1/mobile/properties`.
  /// Everything past Details depends on this.
  int? _propertyId;

  bool _saving = false;
  bool _savingSpaces = false;

  // Step 1 — Address
  final _streetNumber = TextEditingController();
  final _streetName = TextEditingController();
  final _complexName = TextEditingController();
  final _unitNumber = TextEditingController();
  final _region = TextEditingController();
  final _district = TextEditingController();

  // Step 2 — Details
  final _title = TextEditingController();
  String? _propertyType;
  String? _category;
  String? _listingType;
  String? _status;
  String? _mandateType;
  final _price = TextEditingController();
  final _excerpt = TextEditingController();
  final _description = TextEditingController();
  // Rental — only used when listingType == 'rental'
  final _rentalAmount = TextEditingController();
  final _depositAmount = TextEditingController();
  final _leaseStart = TextEditingController();
  final _leaseEnd = TextEditingController();

  // Property24 cascade selection (province/city/suburb ids).
  P24Selection _p24 = const P24Selection();

  // Server-side per-field errors from the most recent failed save.
  Map<String, String> _fieldErrors = {};

  // Scroll keys for jumping to required fields from the modal.
  final _titleFieldKey = GlobalKey();
  final _suburbFieldKey = GlobalKey();
  final _priceFieldKey = GlobalKey();
  final _detailsScrollController = ScrollController();
  final _addressScrollController = ScrollController();

  // Options
  PropertyOptions? _options;
  String? _optionsError;

  // Step 4 — Gallery
  Map<String, List<String>> _existingImages = {};
  GalleryTagsData? _liveTags;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOptions());
  }

  @override
  void dispose() {
    _pageController.dispose();
    _streetNumber.dispose();
    _streetName.dispose();
    _complexName.dispose();
    _unitNumber.dispose();
    _region.dispose();
    _district.dispose();
    _title.dispose();
    _price.dispose();
    _excerpt.dispose();
    _description.dispose();
    _rentalAmount.dispose();
    _depositAmount.dispose();
    _leaseStart.dispose();
    _leaseEnd.dispose();
    _detailsScrollController.dispose();
    _addressScrollController.dispose();
    super.dispose();
  }

  // ---- Required-field validation ----

  /// Returns the list of human-readable required fields that are still
  /// empty. Order matters — the modal's "Take me there" jumps to the
  /// first one in this list.
  List<_MissingField> _missingRequiredFields() {
    final missing = <_MissingField>[];
    if (_title.text.trim().isEmpty) {
      missing.add(_MissingField('Title', 'title', _titleFieldKey, 1));
    }
    if (_propertyType == null || _propertyType!.isEmpty) {
      missing.add(const _MissingField('Property Type', 'property_type', null, 1));
    }
    if (_listingType == null || _listingType!.isEmpty) {
      missing.add(const _MissingField('Listing Type', 'listing_type', null, 1));
    }
    if (_status == null || _status!.isEmpty) {
      missing.add(const _MissingField('Status', 'status', null, 1));
    }
    if (_p24.suburbId == null) {
      missing.add(
          _MissingField('Suburb', 'p24_suburb_id', _suburbFieldKey, 0));
    }
    if (_price.text.trim().isEmpty) {
      missing.add(_MissingField('Price', 'price', _priceFieldKey, 1));
    }
    return missing;
  }

  Future<bool> _showMissingFieldsModal(List<_MissingField> missing) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface(context),
        title: Text(
          'Missing Required Fields',
          style: TextStyle(color: AppTheme.textPrimary(context)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Please fill in the following before creating the property:',
              style: TextStyle(color: AppTheme.textSecondary(context)),
            ),
            const SizedBox(height: 12),
            ...missing.map(
              (m) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        size: 14, color: Colors.red.shade400),
                    const SizedBox(width: 6),
                    Text(
                      m.label,
                      style: TextStyle(
                          color: AppTheme.textPrimary(context),
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('close'),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop('jump'),
            child: const Text('Take me there'),
          ),
        ],
      ),
    );
    return result == 'jump';
  }

  Future<void> _jumpToMissing(_MissingField first) async {
    if (_currentStep != first.step) {
      _goTo(first.step);
      // Allow the page transition to settle before scrolling.
      await Future.delayed(const Duration(milliseconds: 350));
    }
    if (first.key?.currentContext != null) {
      await Scrollable.ensureVisible(
        first.key!.currentContext!,
        duration: const Duration(milliseconds: 300),
        alignment: 0.1,
      );
    }
  }

  // ---- Field error helpers ----

  void _clearFieldError(String field) {
    if (_fieldErrors.containsKey(field)) {
      setState(() => _fieldErrors.remove(field));
    }
  }

  String? _errorFor(String field) => _fieldErrors[field];

  // ---- Options + defaults ----

  Future<void> _loadOptions({bool forceRefresh = false}) async {
    try {
      final opts = await _api.getPropertyOptions(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _options = opts;
        _optionsError = null;
        _applyOptionDefaults();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() =>
          _optionsError = 'Could not load dropdown options — pull to retry');
    }
  }

  void _applyOptionDefaults() {
    final o = _options;
    if (o == null) return;
    _category ??= o.categories.defaultSubmit;
    _propertyType ??= o.propertyTypes.defaultSubmit;
    _status ??= o.statuses.defaultSubmit;
    _mandateType ??= o.mandateTypes.defaultSubmit;
    if (_listingType == null && o.listingTypes.isNotEmpty) {
      final sale = o.listingTypes.where((x) => x.submit == 'sale');
      _listingType =
          sale.isNotEmpty ? sale.first.submit : o.listingTypes.first.submit;
    }
  }

  // ---- Gallery tags + existing images ----

  Future<void> _loadGalleryTags() async {
    if (_propertyId == null) return;
    try {
      final tags = await _api.getGalleryTags(_propertyId!);
      if (!mounted) return;
      setState(() => _liveTags = tags);
    } catch (_) {
      // Non-fatal
    }
  }

  Future<void> _refreshProperty() async {
    if (_propertyId == null) return;
    final provider = context.read<PropertyProvider>();
    try {
      await provider.fetchProperty(_propertyId!);
    } on ApiException {
      // Just-created property the user owns — a 403 here is unexpected;
      // leave the form as-is rather than crashing.
      return;
    }
    final p = provider.selectedProperty;
    if (p != null && mounted) {
      setState(() {
        if (p.galleryCategories != null) {
          final cats = p.galleryCategories!['categories'];
          if (cats is Map<String, dynamic>) {
            _existingImages = cats.map((k, v) =>
                MapEntry(k, List<String>.from(v is List ? v : [])));
          }
        }
      });
    }
    await _loadGalleryTags();
  }

  // ---- Save flow ----

  /// Builds a request body containing only the filled fields. Empty
  /// strings are omitted entirely so the server doesn't get
  /// `"city": ""` and treat it as a clear-the-column instruction.
  Map<String, dynamic> _buildPayload() {
    String? trimOrNull(TextEditingController c) {
      final t = c.text.trim();
      return t.isEmpty ? null : t;
    }

    int? intOrNull(TextEditingController c) {
      final t = c.text.trim();
      if (t.isEmpty) return null;
      return int.tryParse(t.replaceAll(RegExp(r'[^0-9-]'), ''));
    }

    final isRental = _listingType == 'rental';
    final data = <String, dynamic>{};

    void put(String key, dynamic value) {
      if (value == null) return;
      if (value is String && value.isEmpty) return;
      data[key] = value;
    }

    // Required-ish + core
    put('title', trimOrNull(_title));
    put('property_type', _propertyType);
    put('listing_type', _listingType);
    put('status', _status);
    put('price', intOrNull(_price));

    // Property24 cascade ids. Never send the suburb/city/province strings
    // — the server derives those from these ids and overwrites them.
    put('p24_province_id', _p24.provinceId);
    put('p24_city_id', _p24.cityId);
    put('p24_suburb_id', _p24.suburbId);

    // Optional address
    put('street_number', trimOrNull(_streetNumber));
    put('street_name', trimOrNull(_streetName));
    put('complex_name', trimOrNull(_complexName));
    put('unit_number', trimOrNull(_unitNumber));
    put('region', trimOrNull(_region));
    put('district', trimOrNull(_district));

    // Optional details
    put('category', _category);
    put('mandate_type', _mandateType);
    put('excerpt', trimOrNull(_excerpt));
    put('description', trimOrNull(_description));

    // Rental-only
    if (isRental) {
      put('rental_amount', intOrNull(_rentalAmount));
      put('deposit_amount', intOrNull(_depositAmount));
      put('lease_start_date', trimOrNull(_leaseStart));
      put('lease_end_date', trimOrNull(_leaseEnd));
    }

    return data;
  }

  /// POSTs on first call, PUTs on subsequent. Returns true on success.
  /// On 422 the per-field errors land in [_fieldErrors] for inline display.
  Future<bool> _saveAddressAndDetails() async {
    final data = _buildPayload();
    final provider = context.read<PropertyProvider>();
    bool ok;
    if (_propertyId == null) {
      if (widget.linkContactId != null && widget.linkContactRole != null) {
        data['link_contact_id'] = widget.linkContactId;
        data['link_contact_role'] = widget.linkContactRole;
      }
      final created = await provider.createProperty(data);
      ok = created != null;
      if (created != null && mounted) {
        setState(() => _propertyId = created.id);
      }
    } else {
      ok = await provider.updateProperty(_propertyId!, data);
    }

    if (!ok) {
      if (mounted) {
        setState(() {
          _fieldErrors = Map<String, String>.from(provider.fieldErrors);
        });
      }
      return false;
    }
    if (mounted) setState(() => _fieldErrors = {});
    return true;
  }

  Future<void> _nextFromDetails() async {
    // Client-side required-field check (only on initial create — once the
    // property exists, edits are PATCH-style and the modal is irrelevant).
    if (_propertyId == null) {
      final missing = _missingRequiredFields();
      if (missing.isNotEmpty) {
        final wantsJump = await _showMissingFieldsModal(missing);
        if (!mounted) return;
        if (wantsJump) {
          await _jumpToMissing(missing.first);
        }
        return;
      }
    }

    setState(() => _saving = true);
    final ok = await _saveAddressAndDetails();
    if (!mounted) return;
    if (!ok) {
      setState(() => _saving = false);
      final err =
          context.read<PropertyProvider>().error ?? 'Failed to create';
      // Scroll the form to the first invalid field if we have one.
      if (_fieldErrors.isNotEmpty) {
        final first = _fieldErrors.keys.first;
        _jumpToFieldError(first);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err),
          action: SnackBarAction(label: 'Retry', onPressed: _nextFromDetails),
        ),
      );
      return;
    }
    await _refreshProperty();
    if (!mounted) return;
    setState(() => _saving = false);
    _goTo(2);
  }

  void _jumpToFieldError(String field) {
    GlobalKey? key;
    int? step;
    switch (field) {
      case 'title':
        key = _titleFieldKey;
        step = 1;
        break;
      case 'price':
        key = _priceFieldKey;
        step = 1;
        break;
      case 'p24_suburb_id':
        key = _suburbFieldKey;
        step = 0;
        break;
    }
    if (key == null || step == null) return;
    _jumpToMissing(_MissingField(field, field, key, step));
  }

  Future<void> _saveSpacesAndNext() async {
    setState(() => _savingSpaces = true);
    final ok = await _spacesKey.currentState?.saveIfDirty() ?? true;
    if (!mounted) return;
    if (ok) await _loadGalleryTags();
    if (!mounted) return;
    setState(() => _savingSpaces = false);
    if (ok) _goTo(3);
  }

  Future<void> _finalize() async {
    setState(() => _saving = true);
    // Flush any unsaved space edits first as a safety net.
    final spacesOk = await _spacesKey.currentState?.saveIfDirty() ?? true;
    if (!mounted) return;
    if (!spacesOk) {
      setState(() => _saving = false);
      return;
    }
    // Persist any last-minute edits to address/details.
    final ok = await _saveAddressAndDetails();
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.of(context).pop();
    } else {
      final err = context.read<PropertyProvider>().error ?? 'Failed to save';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err)),
      );
    }
  }

  // ---- Upload sheet ----

  Future<void> _openUploadSheet({String? initialTag}) async {
    if (_propertyId == null) return;
    final uploaded = await GalleryUploadSheet.show(
      context,
      propertyId: _propertyId!,
      initialTag: initialTag,
    );
    if ((uploaded ?? false) && mounted) {
      await _refreshProperty();
    }
  }

  // ---- Navigation ----

  void _goTo(int step) {
    _pageController.animateToPage(step,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    setState(() => _currentStep = step);
  }

  bool _handleBack() {
    if (_currentStep > 0) {
      _goTo(_currentStep - 1);
      return false;
    }
    return true;
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentStep == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New Property'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Previous step',
            onPressed: () {
              if (_currentStep > 0) {
                _goTo(_currentStep - 1);
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Row(
                  children: List.generate(4, (i) {
                    final active = i <= _currentStep;
                    return Expanded(
                      child: Container(
                        height: 4,
                        margin: EdgeInsets.only(right: i < 3 ? 8 : 0),
                        decoration: BoxDecoration(
                          color: active
                              ? AppTheme.brand
                              : AppTheme.surface2(context),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _stepAddress(),
                    _stepDetails(),
                    _stepSpaces(),
                    _stepGallery(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Step 1: Address ----

  Widget _stepAddress() {
    return SingleChildScrollView(
      controller: _addressScrollController,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Street Number'), _field(_streetNumber),
          _label('Street Name'), _field(_streetName),
          _label('Complex Name (optional)'), _field(_complexName),
          _label('Unit Number (optional)'), _field(_unitNumber),
          P24LocationPicker(
            key: _suburbFieldKey,
            suburbError: _errorFor('p24_suburb_id'),
            onChanged: (sel) {
              setState(() => _p24 = sel);
              _clearFieldError('p24_suburb_id');
            },
          ),
          _label('District (optional)'), _field(_district),
          _label('Region (optional)'), _field(_region),
          const SizedBox(height: 24),
          _navButton('Next', () => _goTo(1)),
        ],
      ),
    );
  }

  /// A [TextField] wired up to the [_fieldErrors] map for inline error
  /// display + clear-on-touch behavior.
  Widget _errorField({
    Key? key,
    required TextEditingController controller,
    required String errorField,
    TextInputType? keyboard,
    int maxLines = 1,
    int? maxLength,
    String? hintText,
  }) {
    final err = _errorFor(errorField);
    return TextField(
      key: key,
      controller: controller,
      keyboardType: keyboard,
      maxLines: maxLines,
      maxLength: maxLength,
      decoration: InputDecoration(
        hintText: hintText,
        errorText: err,
        errorMaxLines: 2,
      ),
      onChanged: (_) => _clearFieldError(errorField),
    );
  }

  // ---- Step 2: Details ----

  Widget _stepDetails() {
    final o = _options ?? PropertyOptions.empty;
    final isRental = _listingType == 'rental';
    return RefreshIndicator(
      onRefresh: () => _loadOptions(forceRefresh: true),
      child: SingleChildScrollView(
        controller: _detailsScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_optionsError != null) _optionsErrorBanner(),
            _label('Listing Type *', required: true),
            _listingTypeSegmented(o),
            if (_errorFor('listing_type') != null)
              _inlineFieldError(_errorFor('listing_type')!),
            _label('Title *', required: true),
            _errorField(
              key: _titleFieldKey,
              controller: _title,
              errorField: 'title',
              hintText: 'e.g. Stunning 4 Bed House in Uvongo',
            ),
            _label('Property Type *', required: true),
            PropertyOptionDropdown(
              options: o.propertyTypes,
              value: _propertyType,
              onChanged: (v) {
                setState(() => _propertyType = v);
                _clearFieldError('property_type');
              },
            ),
            if (_errorFor('property_type') != null)
              _inlineFieldError(_errorFor('property_type')!),
            _label('Property Status *', required: true),
            PropertyOptionDropdown(
              options: o.statuses,
              value: _status,
              onChanged: (v) {
                setState(() => _status = v);
                _clearFieldError('status');
              },
            ),
            if (_errorFor('status') != null)
              _inlineFieldError(_errorFor('status')!),
            _label('Price (R) *', required: true),
            _errorField(
              key: _priceFieldKey,
              controller: _price,
              errorField: 'price',
              keyboard: TextInputType.number,
              hintText: 'e.g. 2500000',
            ),
            _label('Category'),
            PropertyOptionDropdown(
              options: o.categories,
              value: _category,
              onChanged: (v) => setState(() => _category = v),
            ),
            _label('Mandate Type'),
            PropertyOptionDropdown(
              options: o.mandateTypes,
              value: _mandateType,
              onChanged: (v) => setState(() => _mandateType = v),
            ),
            _label('Excerpt (max 500 chars)'),
            _errorField(
              controller: _excerpt,
              errorField: 'excerpt',
              maxLines: 2,
              maxLength: 500,
            ),
            _label('Description'),
            _errorField(
              controller: _description,
              errorField: 'description',
              maxLines: 4,
            ),
            if (isRental) ...[
              const SizedBox(height: 16),
              _sectionHeader('Rental Details'),
              _label('Rental Amount (R / month)'),
              _errorField(
                controller: _rentalAmount,
                errorField: 'rental_amount',
                keyboard: TextInputType.number,
              ),
              _label('Deposit Amount (R)'),
              _errorField(
                controller: _depositAmount,
                errorField: 'deposit_amount',
                keyboard: TextInputType.number,
              ),
              _label('Lease Start Date'),
              _dateField(_leaseStart, 'lease_start_date'),
              _label('Lease End Date'),
              _dateField(_leaseEnd, 'lease_end_date'),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _saving ? null : _nextFromDetails,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_propertyId == null
                        ? 'Create & Continue'
                        : 'Next: Spaces'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary(context),
          ),
        ),
      );

  Widget _inlineFieldError(String message) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          message,
          style: TextStyle(fontSize: 11, color: Colors.red.shade400),
        ),
      );

  /// Listing Type rendered as a chip-based segmented control fed by
  /// `options.listingTypes`. Falls back to the standard sale/rental pair
  /// when options haven't loaded yet, so the form is usable offline.
  Widget _listingTypeSegmented(PropertyOptions o) {
    final items = o.listingTypes.isNotEmpty
        ? o.listingTypes
        : const [
            PropertyOption(display: 'For Sale', submit: 'sale'),
            PropertyOption(display: 'For Rental', submit: 'rental'),
          ];
    return Wrap(
      spacing: 8,
      children: items.map((opt) {
        final isSelected = _listingType == opt.submit;
        return ChoiceChip(
          label: Text(opt.display),
          selected: isSelected,
          onSelected: (_) {
            setState(() {
              _listingType = opt.submit;
              // Discard rental field state when leaving rental mode so the
              // values don't slip into the next save.
              if (opt.submit != 'rental') {
                _rentalAmount.clear();
                _depositAmount.clear();
                _leaseStart.clear();
                _leaseEnd.clear();
              }
            });
            _clearFieldError('listing_type');
          },
          backgroundColor: AppTheme.surface2(context),
          selectedColor: AppTheme.brand,
          labelStyle: TextStyle(
            color:
                isSelected ? Colors.white : AppTheme.textPrimary(context),
            fontWeight: FontWeight.w600,
          ),
          side: BorderSide.none,
        );
      }).toList(),
    );
  }

  Widget _dateField(TextEditingController c, String errorField) {
    return TextField(
      controller: c,
      readOnly: true,
      onTap: () async {
        DateTime? initial;
        if (c.text.isNotEmpty) {
          try {
            initial = DateTime.parse(c.text);
          } catch (_) {}
        }
        final picked = await showDatePicker(
          context: context,
          initialDate: initial ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) {
          final iso =
              '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
          setState(() => c.text = iso);
          _clearFieldError(errorField);
        }
      },
      decoration: InputDecoration(
        hintText: 'YYYY-MM-DD',
        errorText: _errorFor(errorField),
        suffixIcon: const Icon(Icons.calendar_today, size: 18),
      ),
    );
  }

  Widget _optionsErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 18, color: Colors.orange.shade400),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _optionsError ?? '',
              style:
                  TextStyle(fontSize: 12, color: Colors.orange.shade400),
            ),
          ),
          TextButton(
            onPressed: () => _loadOptions(forceRefresh: true),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ---- Step 3: Spaces ----

  Widget _stepSpaces() {
    if (_propertyId == null) {
      // Shouldn't be reachable — _nextFromDetails is the only way to get
      // here and it only advances on success — but render a safe fallback.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Save the property details first to add spaces.',
            style: TextStyle(color: AppTheme.textSecondary(context)),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: SpacesEditorSection(
            key: _spacesKey,
            propertyId: _propertyId!,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _savingSpaces ? null : _saveSpacesAndNext,
              child: _savingSpaces
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Next: Gallery'),
            ),
          ),
        ),
      ],
    );
  }

  // ---- Step 4: Gallery ----

  Widget _stepGallery() {
    if (_propertyId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Save the property details first to upload photos.',
            style: TextStyle(color: AppTheme.textSecondary(context)),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final p = context.watch<PropertyProvider>().selectedProperty;
    final liveTags = _liveTags?.availableTags.isNotEmpty == true
        ? _liveTags!.availableTags
        : (p?.galleryTags ?? const <String>[]);
    final extraKeys = _existingImages.keys
        .where((k) => !liveTags.contains(k))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Gallery',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary(context))),
              ),
              TextButton.icon(
                onPressed: _saving ? null : () => _openUploadSheet(),
                icon: const Icon(Icons.add_a_photo, size: 16),
                label: const Text('Upload'),
                style:
                    TextButton.styleFrom(foregroundColor: AppTheme.brand),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (liveTags.isEmpty && extraKeys.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No photos yet. Add spaces first to unlock tags, or tap Upload to add untagged photos.',
                style: TextStyle(color: AppTheme.textSecondary(context)),
              ),
            )
          else ...[
            ...liveTags.map((tag) => _gallerySection(tag, isLive: true)),
            ...extraKeys.map((tag) => _gallerySection(tag, isLive: false)),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _saving ? null : _finalize,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save Property'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gallerySection(String tag, {required bool isLive}) {
    final existing = _existingImages[tag] ?? const <String>[];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$tag  ·  ${existing.length}',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary(context)),
                ),
              ),
              if (isLive)
                TextButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _openUploadSheet(initialTag: tag),
                  icon: const Icon(Icons.add_a_photo, size: 14),
                  label: const Text('Add Photo'),
                  style: TextButton.styleFrom(
                      foregroundColor: AppTheme.brand,
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (existing.isEmpty)
            Text(
              'No photos in this group yet.',
              style: TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary(context)),
            )
          else
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: existing.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  child: Image.network(
                    existing[i],
                    width: 120,
                    height: 90,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 120,
                      height: 90,
                      color: AppTheme.surface2(context),
                      child: Icon(Icons.broken_image,
                          color: AppTheme.textMuted(context)),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---- Shared widgets ----

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
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ]
                : const [],
          ),
        ),
      );

  Widget _field(TextEditingController c,
          {TextInputType? keyboard, int maxLines = 1}) =>
      TextField(controller: c, keyboardType: keyboard, maxLines: maxLines);

  Widget _navButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(onPressed: onPressed, child: Text(label)),
    );
  }
}
