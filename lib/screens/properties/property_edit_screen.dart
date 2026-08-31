import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/gallery_tags.dart';
import '../../models/property_options.dart';
import '../../services/api_service.dart';
import '../../services/upload_service.dart';
import '../../theme.dart';
import '../../providers/property_provider.dart';
import 'gallery_upload_sheet.dart';
import 'p24_location_picker.dart';
import 'property_option_dropdown.dart';
import 'spaces_editor_section.dart';
import '../../models/space.dart';
import '../../widgets/properties/property_gallery.dart';

class PropertyEditScreen extends StatefulWidget {
  final int propertyId;
  const PropertyEditScreen({super.key, required this.propertyId});

  @override
  State<PropertyEditScreen> createState() => _PropertyEditScreenState();
}

class _PropertyEditScreenState extends State<PropertyEditScreen> {
  final _pageController = PageController();
  final _spacesKey = GlobalKey<SpacesEditorSectionState>();
  int _currentStep = 0;
  bool _saving = false;
  bool _savingSpaces = false;
  bool _loaded = false;

  final _streetNumber = TextEditingController();
  final _streetName = TextEditingController();
  final _complexName = TextEditingController();
  final _unitNumber = TextEditingController();
  final _region = TextEditingController();
  final _district = TextEditingController();

  final _title = TextEditingController();
  String? _propertyType;
  String? _category;
  String? _listingType;
  String? _status;
  String? _mandateType;
  final _price = TextEditingController();
  final _excerpt = TextEditingController();
  final _description = TextEditingController();
  // Rental
  final _rentalAmount = TextEditingController();
  final _depositAmount = TextEditingController();
  final _leaseStart = TextEditingController();
  final _leaseEnd = TextEditingController();

  /// Snapshot of every field's initial value, captured the moment the
  /// property loads. Used to detect dirtiness and to compute the PATCH
  /// payload (only changed keys are sent on save).
  Map<String, dynamic> _initialValues = {};

  Map<String, String> _fieldErrors = {};

  // Property24 cascade. Initial ids/mismatch come from the loaded property
  // and seed the picker; `_p24` tracks the live selection. On PUT we only
  // send the three ids when the user actually changed the location.
  int? _p24InitProvinceId;
  int? _p24InitCityId;
  int? _p24InitSuburbId;
  bool _p24SuburbMismatch = false;
  P24Selection _p24 = const P24Selection();

  PropertyOptions? _options;
  String? _optionsError;

  /// The property's photos as the server groups them: tagged rooms plus the
  /// `unsorted` bucket. Re-seeded from the property payload, and replaced
  /// wholesale by an assign response so a filed photo moves in one frame.
  GalleryCategories _gallery = GalleryCategories.empty;

  /// Live gallery tags for the property. Fetched directly from
  /// `/gallery/tags` so we don't depend on the detail endpoint actually
  /// including the `gallery_tags` field.
  GalleryTagsData? _liveTags;

  /// The Spaces catalog, used only to tell a space-derived tag ("Scullery",
  /// "Braai Room") from a custom one the agent typed. It is fetched rather
  /// than hard-coded because the catalog now runs to about fifty space types
  /// and grows server-side: any pattern baked into the app would start
  /// mislabelling rooms the moment the catalog moved. Cached for 24h by
  /// [ApiService.getSpacesCatalog], so this costs nothing after the first load.
  SpacesCatalog? _spacesCatalog;

  final ApiService _api = ApiService();

  /// [UploadService.successCount] as of the last property fetch. When the
  /// background drainer lands photos we weren't watching for, this is how the
  /// gallery notices and pulls the real URLs in — otherwise a photo would sit
  /// as a local placeholder until the agent happened to reload the screen.
  int _seenUploads = 0;

  @override
  void initState() {
    super.initState();
    _seenUploads = UploadService.instance.successCount;
    UploadService.instance.addListener(_onUploadsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProperty();
      _loadOptions();
      _loadSpacesCatalog();
    });
  }

  void _onUploadsChanged() {
    final service = UploadService.instance;
    // Wait for the run to finish rather than refetching per photo: a 27-photo
    // batch would otherwise fire 27 property GETs in thirteen seconds.
    if (service.isRunning) return;
    if (service.successCount == _seenUploads) return;
    _seenUploads = service.successCount;
    if (mounted) _loadProperty();
  }

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
      setState(() => _optionsError =
          'Could not load dropdown options — pull to retry');
    }
  }

  /// Fill any unset dropdown with its server-specified default. Called
  /// after both `_loadProperty` and `_loadOptions` have landed, so the
  /// property's stored values take precedence over defaults.
  void _applyOptionDefaults() {
    final o = _options;
    if (o == null) return;
    _category ??= o.categories.defaultSubmit;
    _propertyType ??= o.propertyTypes.defaultSubmit;
    _status ??= o.statuses.defaultSubmit;
    _mandateType ??= o.mandateTypes.defaultSubmit;
    // Listing types have no is_default flag — spec says default to "sale".
    if (_listingType == null && o.listingTypes.isNotEmpty) {
      final sale = o.listingTypes.where((x) => x.submit == 'sale');
      _listingType =
          sale.isNotEmpty ? sale.first.submit : o.listingTypes.first.submit;
    }
  }

  Future<void> _loadGalleryTags() async {
    try {
      final tags = await _api.getGalleryTags(widget.propertyId);
      if (!mounted) return;
      setState(() => _liveTags = tags);
    } catch (_) {
      // Fall back to whatever was on the property detail — not fatal.
    }
  }

  Future<void> _loadSpacesCatalog() async {
    try {
      final catalog = await _api.getSpacesCatalog();
      if (!mounted) return;
      setState(() => _spacesCatalog = catalog);
    } catch (_) {
      // Only affects whether a tag chip offers a ×; not worth surfacing.
    }
  }

  /// Adopts a `gallery/assign` response as the new truth for this screen.
  ///
  /// Both halves matter. The gallery re-renders the move without a reload, and
  /// the tag list comes along because the server recomputes it in the same
  /// breath — so a room deleted while the agent was filing can't leave the
  /// picker offering it.
  void _adoptAssignResult(GalleryAssignResult result) {
    setState(() {
      _gallery = result.categories;
      if (result.availableTags.isNotEmpty) {
        _liveTags = (_liveTags ?? GalleryTagsData.empty(widget.propertyId))
            .withAvailable(result.availableTags);
      }
    });
  }

  Future<void> _loadProperty() async {
    final provider = context.read<PropertyProvider>();
    try {
      await provider.fetchProperty(widget.propertyId);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 403) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
        Navigator.of(context).pop();
        return;
      }
      return;
    }
    // Fetch the tag list directly — the detail endpoint may not yet expose
    // `gallery_tags`, so we don't want to rely on it alone.
    await _loadGalleryTags();
    final p = provider.selectedProperty;
    if (p != null && mounted) {
      setState(() {
        _streetNumber.text = p.streetNumber ?? '';
        _streetName.text = p.streetName ?? '';
        _complexName.text = p.complexName ?? '';
        _unitNumber.text = p.unitNumber ?? '';
        _region.text = p.region ?? '';
        _p24InitProvinceId = p.p24ProvinceId;
        _p24InitCityId = p.p24CityId;
        _p24InitSuburbId = p.p24SuburbId;
        // Legacy / unmatched location → open the suburb picker empty so
        // the agent picks a real P24 suburb.
        _p24SuburbMismatch = p.p24SuburbMismatch || p.p24SuburbId == null;
        _district.text = p.district ?? '';
        _title.text = p.title ?? '';
        _propertyType = p.propertyType;
        _category = p.category;
        _listingType = p.listingType;
        _status = p.status;
        _mandateType = p.mandateType;
        _price.text = p.price?.toString() ?? '';
        _excerpt.text = p.excerpt ?? '';
        _description.text = p.description ?? '';
        _rentalAmount.text = p.rentalAmount?.toString() ?? '';
        _depositAmount.text = p.depositAmount?.toString() ?? '';
        _leaseStart.text = p.leaseStartDate ?? '';
        _leaseEnd.text = p.leaseEndDate ?? '';
        // Options may have loaded first — fill in any gaps with defaults
        // without clobbering the property's stored values.
        _applyOptionDefaults();
        // Snapshot for dirty diff (after all values are set above).
        _initialValues = _captureSnapshot();
        // Photos, including the `unsorted` bucket — see [GalleryCategories],
        // which absorbs every shape this endpoint has emitted. Reading only
        // `categories` (as this did) is what left untagged photos on the
        // property but on no screen.
        _gallery = GalleryCategories.fromJson(p.galleryCategories);
        _loaded = true;
      });
    }
  }

  @override
  void dispose() {
    UploadService.instance.removeListener(_onUploadsChanged);
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
    super.dispose();
  }

  // ---- Field error helpers (mirror create screen) ----

  void _clearFieldError(String field) {
    if (_fieldErrors.containsKey(field)) {
      setState(() => _fieldErrors.remove(field));
    }
  }

  String? _errorFor(String field) => _fieldErrors[field];

  Widget _inlineFieldError(String message) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          message,
          style: TextStyle(fontSize: 11, color: Colors.red.shade400),
        ),
      );

  Widget _errorField({
    required TextEditingController controller,
    required String errorField,
    TextInputType? keyboard,
    int maxLines = 1,
    int? maxLength,
    String? hintText,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      maxLines: maxLines,
      maxLength: maxLength,
      decoration: InputDecoration(
        hintText: hintText,
        errorText: _errorFor(errorField),
        errorMaxLines: 2,
      ),
      onChanged: (_) => _clearFieldError(errorField),
    );
  }

  // ---- Dirty diff ----

  /// Snapshot of every editable field's submitted value as of the last
  /// successful load. Used to detect dirtiness and to compute the PATCH
  /// payload — only changed keys land in the body sent to the server.
  Map<String, dynamic> _captureSnapshot() {
    return _buildPayload(includeAll: true);
  }

  Map<String, dynamic> _buildPayload({bool includeAll = false}) {
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
    final all = <String, dynamic>{
      'title': trimOrNull(_title),
      'property_type': _propertyType,
      'listing_type': _listingType,
      'status': _status,
      'price': intOrNull(_price),
      'street_number': trimOrNull(_streetNumber),
      'street_name': trimOrNull(_streetName),
      'complex_name': trimOrNull(_complexName),
      'unit_number': trimOrNull(_unitNumber),
      'region': trimOrNull(_region),
      'district': trimOrNull(_district),
      'category': _category,
      'mandate_type': _mandateType,
      'excerpt': trimOrNull(_excerpt),
      'description': trimOrNull(_description),
      'rental_amount': isRental ? intOrNull(_rentalAmount) : null,
      'deposit_amount': isRental ? intOrNull(_depositAmount) : null,
      'lease_start_date': isRental ? trimOrNull(_leaseStart) : null,
      'lease_end_date': isRental ? trimOrNull(_leaseEnd) : null,
    };

    if (includeAll) return all;

    // PATCH-style: only send keys whose value differs from the snapshot.
    final diff = <String, dynamic>{};
    all.forEach((k, v) {
      if (_initialValues[k] != v) diff[k] = v;
    });
    // Location: only send the three ids when the agent actually changed
    // the cascade. Omitting them leaves the server-side location as-is.
    if (_p24.dirty) {
      diff['p24_province_id'] = _p24.provinceId;
      diff['p24_city_id'] = _p24.cityId;
      diff['p24_suburb_id'] = _p24.suburbId;
    }
    return diff;
  }

  bool get _isDirty => _buildPayload().isNotEmpty;

  void _goTo(int step) {
    _pageController.animateToPage(step,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    setState(() => _currentStep = step);
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    // Flush any unsaved space edits first — the Spaces step has its own
    // Save button, but if the user skipped it we still want their changes
    // to persist when they tap "Save Changes" here.
    final spacesOk = await _spacesKey.currentState?.saveIfDirty() ?? true;
    if (!mounted) return;
    if (!spacesOk) {
      setState(() => _saving = false);
      return;
    }

    final provider = context.read<PropertyProvider>();
    // PATCH-style: only send keys whose value has changed since load.
    final data = _buildPayload();
    if (data.isEmpty) {
      // Nothing to save on the property fields themselves; spaces may
      // already have been flushed above. Just close.
      setState(() => _saving = false);
      Navigator.of(context).pop();
      return;
    }

    final ok = await provider.updateProperty(widget.propertyId, data);
    if (mounted) {
      if (ok) {
        // Refresh snapshot so dirty becomes false again.
        setState(() {
          _fieldErrors = {};
          _initialValues = _captureSnapshot();
        });
        Navigator.of(context).pop();
      } else {
        setState(() {
          _fieldErrors = Map<String, String>.from(provider.fieldErrors);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.error ?? 'Failed to save')),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _openUploadSheet({String? initialTag}) async {
    final uploaded = await GalleryUploadSheet.show(
      context,
      propertyId: widget.propertyId,
      initialTag: initialTag,
    );
    // Always refetch after the sheet closes — even a partial upload changes
    // tag_counts, and the spaces editor may have been invalidated from
    // under us while the sheet was open.
    if ((uploaded ?? false) && mounted) {
      await _loadProperty();
    }
  }

  /// System/AppBar back: step backwards through the wizard instead of
  /// exiting. Returns `false` from the [PopScope] callback when we
  /// consumed the back press, `true` (i.e. allow the pop) only when
  /// already on the first step.
  bool _handleBack() {
    if (_currentStep > 0) {
      _goTo(_currentStep - 1);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PropertyProvider>();

    return PopScope(
      canPop: _currentStep == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit Property'),
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
        body: !_loaded && provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: Column(
                children: [
                  _tabBar(),
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      // Keep every page alive once built. Otherwise the
                      // PageView disposes off-screen pages and
                      // `_spacesKey.currentState` becomes null — which made
                      // `_save` silently skip unsaved space edits.
                      children: [
                        _KeepAlive(child: _stepAddress()),
                        _KeepAlive(child: _stepDetails()),
                        _KeepAlive(child: _stepSpaces()),
                        _KeepAlive(child: _stepGallery()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }

  static const _stepTitles = ['Address', 'Details', 'Spaces', 'Gallery'];

  /// Tappable step tabs that replace the old progress lines. The agent can
  /// jump straight to any section (e.g. Gallery) instead of stepping through
  /// the wizard with Next. The brand underline still marks the active step.
  Widget _tabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: List.generate(_stepTitles.length, (i) {
          final active = i == _currentStep;
          return Expanded(
            child: InkWell(
              onTap: () => _goTo(i),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                child: Column(
                  children: [
                    Text(
                      _stepTitles[i],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active
                            ? AppTheme.brand
                            : AppTheme.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color:
                            active ? AppTheme.brand : AppTheme.surface2(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _stepAddress() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Street Number'), _field(_streetNumber),
          _label('Street Name'), _field(_streetName),
          _label('Complex Name (optional)'), _field(_complexName),
          _label('Unit Number (optional)'), _field(_unitNumber),
          P24LocationPicker(
            key: ValueKey('p24-$_loaded-$_p24InitSuburbId-$_p24InitCityId'),
            initialProvinceId: _p24InitProvinceId,
            initialCityId: _p24InitCityId,
            initialSuburbId: _p24InitSuburbId,
            suburbMismatch: _p24SuburbMismatch,
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

  Widget _stepDetails() {
    final o = _options ?? PropertyOptions.empty;
    final isRental = _listingType == 'rental';
    return RefreshIndicator(
      onRefresh: () => _loadOptions(forceRefresh: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_optionsError != null) _optionsErrorBanner(),
            _label('Title'),
            _errorField(
              controller: _title,
              errorField: 'title',
              hintText: 'e.g. Stunning 4 Bed House in Uvongo',
            ),
            _label('Property Type'),
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
            _label('Property Status'),
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
            _label('Price (R)'),
            _errorField(
              controller: _price,
              errorField: 'price',
              keyboard: TextInputType.number,
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
            _label('Description'),
            _errorField(
              controller: _description,
              errorField: 'description',
              maxLines: 4,
            ),
            if (isRental) ...[
              const SizedBox(height: 16),
              Text(
                'Rental Details',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary(context)),
              ),
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
            _navButton('Next', () => _goTo(2)),
          ],
        ),
      ),
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
              style: TextStyle(
                  fontSize: 12, color: Colors.orange.shade400),
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

  Widget _stepSpaces() {
    return Column(
      children: [
        Expanded(
          child: SpacesEditorSection(
            key: _spacesKey,
            propertyId: widget.propertyId,
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

  Future<void> _saveSpacesAndNext() async {
    setState(() => _savingSpaces = true);
    final ok = await _spacesKey.currentState?.saveIfDirty() ?? true;
    if (!mounted) return;
    // Spaces just changed — the tag list may now include new entries.
    // Refresh before advancing so the Gallery step is accurate.
    if (ok) await _loadGalleryTags();
    if (!mounted) return;
    setState(() => _savingSpaces = false);
    if (ok) _goTo(3);
  }

  Widget _stepGallery() {
    final p = context.watch<PropertyProvider>().selectedProperty;
    // Prefer the dedicated /gallery/tags response; fall back to whatever
    // the detail endpoint carried.
    final liveTags = _liveTags?.availableTags.isNotEmpty == true
        ? _liveTags!.availableTags
        : (p?.galleryTags ?? const <String>[]);

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
          PropertyGallery(
            propertyId: widget.propertyId,
            gallery: _gallery,
            availableTags: liveTags,
            enabled: !_saving,
            onAssigned: _adoptAssignResult,
            onRefreshRequested: _loadProperty,
            onAddPhotos: ({String? initialTag}) =>
                _openUploadSheet(initialTag: initialTag),
          ),
          const SizedBox(height: 16),
          _customTagManager(liveTags),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(
              // Always allow Save here — even if no field-level diff, the
              // user might have queued space edits we still need to flush.
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_isDirty ? 'Save Changes' : 'Done'),
            ),
          ),
        ],
      ),
    );
  }

  /// Strips a trailing instance number, so "Bedroom 3" is compared as
  /// "Bedroom". Space-derived tags are numbered per property; the catalog
  /// lists the unnumbered type.
  static final RegExp _instanceSuffix = RegExp(r'\s+\d+$');

  /// True when [tag] is derived from the spaces catalog rather than typed by
  /// the agent. Derived tags can't be removed via the tag endpoint — the
  /// backend silently no-ops the delete — so we hide the × on their chip.
  ///
  /// Decided against the *live* catalog, never a pattern baked into the app.
  /// This used to be a regex listing eleven room names; the catalog now offers
  /// around fifty (Entrance Hall, Scullery, Braai Room, Laundry Room…) and
  /// grows without an app release, so every space type the regex had never
  /// heard of was being mislabelled as a custom tag and offered a delete that
  /// does nothing.
  ///
  /// Until the catalog loads, nothing is treated as custom: an affordance that
  /// silently fails is worse than one that appears a moment late.
  bool _isDerivedTag(String tag) {
    final catalog = _spacesCatalog;
    if (catalog == null) return true;
    final base = tag.replaceFirst(_instanceSuffix, '').trim();
    return catalog.allSpaceTypes
        .any((t) => t.trim().toLowerCase() == base.toLowerCase());
  }

  Widget _customTagManager(List<String> liveTags) {
    // Custom tags = anything in the live list that isn't derived from a
    // space (Bedroom N, Bathroom N, Garage, etc.). These are the only ones
    // the agent can add or remove from here, and they sync straight to the
    // web via POST/DELETE /gallery/tags.
    final customTags =
        liveTags.where((t) => !_isDerivedTag(t)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Custom Tags',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary(context)),
              ),
            ),
            TextButton.icon(
              onPressed: _saving ? null : _showAddTagDialog,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add custom tag'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.brand),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Custom tags sync to the web and can be applied when uploading photos.',
          style: TextStyle(
              fontSize: 12, color: AppTheme.textSecondary(context)),
        ),
        const SizedBox(height: 8),
        if (customTags.isEmpty)
          Text(
            'No custom tags yet.',
            style: TextStyle(
                fontSize: 12, color: AppTheme.textMuted(context)),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: customTags.map(_tagChip).toList(),
          ),
      ],
    );
  }

  Widget _tagChip(String tag) {
    final derived = _isDerivedTag(tag);
    return Chip(
      label: Text(tag),
      backgroundColor: AppTheme.surface2(context),
      side: BorderSide.none,
      labelStyle: TextStyle(color: AppTheme.textPrimary(context), fontSize: 12),
      deleteIcon: derived ? null : const Icon(Icons.close, size: 14),
      onDeleted: derived ? null : () => _confirmDeleteTag(tag),
    );
  }

  Future<void> _showAddTagDialog() async {
    final controller = TextEditingController();
    String? errorText;
    bool busy = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          backgroundColor: AppTheme.surface(context),
          title: const Text('Add custom tag'),
          content: TextField(
            controller: controller,
            maxLength: 40,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'e.g. Sea View',
              errorText: errorText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: busy
                  ? null
                  : () async {
                      final input = controller.text.trim();
                      if (input.isEmpty) {
                        setLocal(() => errorText = 'Tag cannot be empty');
                        return;
                      }
                      setLocal(() {
                        busy = true;
                        errorText = null;
                      });
                      try {
                        final updated = await _api.addGalleryTag(
                            widget.propertyId, input);
                        if (!mounted) return;
                        setState(() => _liveTags = updated);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      } on ApiException catch (e) {
                        setLocal(() {
                          busy = false;
                          errorText = e.statusCode == 422
                              ? (e.message.toLowerCase().contains('exist')
                                  ? 'Tag already exists'
                                  : e.message)
                              : e.message;
                        });
                      } catch (e) {
                        setLocal(() {
                          busy = false;
                          errorText = e.toString();
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Add'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _confirmDeleteTag(String tag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface(context),
        title: const Text('Remove tag?'),
        content: Text(
            "Remove tag '$tag'? Photos under this tag will become untagged."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final updated = await _api.deleteGalleryTag(widget.propertyId, tag);
      if (!mounted) return;
      setState(() => _liveTags = updated);
      // Backend strips the tag from images — refresh property so the
      // gallery groupings reflect the new untagged bucket.
      await _loadProperty();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  // ---- Shared widgets ----

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Text(text, style: TextStyle(
        fontSize: 13, fontWeight: FontWeight.w500,
        color: AppTheme.textSecondary(context))),
  );

  Widget _field(TextEditingController c, {TextInputType? keyboard, int maxLines = 1}) =>
      TextField(controller: c, keyboardType: keyboard, maxLines: maxLines);

  Widget _navButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity, height: 48,
      child: ElevatedButton(onPressed: onPressed, child: Text(label)),
    );
  }
}

/// Keeps a wizard page alive after it leaves the viewport, so its [State]
/// (and thus `_spacesKey.currentState`) survives navigation between steps.
class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
