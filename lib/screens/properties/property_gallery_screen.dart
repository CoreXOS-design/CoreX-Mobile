import 'package:flutter/material.dart';

import '../../models/gallery_tags.dart';
import '../../models/property.dart';
import '../../services/api_service.dart';
import '../../services/image_cache.dart';
import '../../theme.dart';
import '../../widgets/ui/content_width.dart';
import 'gallery_upload_sheet.dart';
import '../../widgets/properties/add_custom_tag_dialog.dart';
import '../../widgets/corex_photo.dart';

/// Full-screen photo manager for a property — the "too many photos for a
/// tab" answer to [PropertyGallery] (`widgets/properties/property_gallery.dart`),
/// which stays in place for the create/edit wizard where a property rarely
/// has more than a handful of photos yet.
///
/// Three things a cramped in-tab strip couldn't do:
///  1. **A grid**, not a horizontal scroll per room — so 90 photos are a scan,
///     not 15 separate side-scrolls.
///  2. **Room filter chips** — jump straight to one room's photos instead of
///     scrolling past every other room to find it.
///  3. **A dedicated "Reorder rooms" sheet** — a plain drag list, instead of a
///     tiny handle icon buried in a section header next to a photo grid that
///     is *also* draggable.
///
/// Dragging within a room's grid only ever reorders that room's own bucket
/// (see [ApiService.reorderGalleryImages]) — it never touches the property's
/// master photo order, which is the one the website actually shows. The
/// "All Photos" filter (see [_kMasterFilter]) is the view that does: drag
/// there to set the cover photo and the portal order. Moving a photo
/// *between* rooms is still done by selecting it and filing it, in either
/// view. Selected photos can also be deleted outright from here.
class PropertyGalleryScreen extends StatefulWidget {
  final int propertyId;
  final ApiService? api;

  const PropertyGalleryScreen({
    super.key,
    required this.propertyId,
    this.api,
  });

  @override
  State<PropertyGalleryScreen> createState() => _PropertyGalleryScreenState();
}

/// Sentinel `_filter` values — distinct from `null` (rooms, grouped) and
/// safe against collision with a real tag name (tags come from the spaces
/// catalog, which never emits a `__`-wrapped name).
const String _kUnsortedFilter = '__unsorted_filter__';

/// "All Photos": the property's single master photo order — the one
/// [ApiService.reorderGalleryImages] call that actually reaches the web.
/// Reordering *within* a room only ever reorders that room's own bucket; the
/// API deliberately leaves the master grid untouched when a `room_tag` is
/// sent, so a room-scoped drag never changes what the portal/website shows.
/// This is the only view that does.
const String _kMasterFilter = '__master_filter__';

class _PropertyGalleryScreenState extends State<PropertyGalleryScreen> {
  late final ApiService _api = widget.api ?? ApiService();

  bool _loading = true;
  bool _loaded = false;
  String? _error;

  GalleryCategories _gallery = GalleryCategories.empty;
  GalleryTagsData? _liveTags;
  List<String> _galleryFallbackTags = const [];
  String? _galleryFingerprint;

  /// The property's `gallery_images` — every photo in master/portal order.
  /// Only [_kMasterFilter]'s view reads or reorders this; the per-room
  /// sections work entirely off [_gallery].
  List<String> _masterOrder = const [];

  final Set<String> _selected = {};
  bool _assigning = false;
  bool _deleting = false;

  /// Gates every room's drag affordance at once, same as [PropertyGallery] —
  /// a second drag racing the first's optimistic state is worse than a brief
  /// "nothing is draggable right now". Also covers the master-grid drag —
  /// there's never a reason for both to be live simultaneously.
  bool _reordering = false;
  GalleryCategories? _optimisticGallery;
  List<String>? _optimisticMasterOrder;

  /// `null` = rooms, grouped. [_kUnsortedFilter]/[_kMasterFilter]/a tag name
  /// narrow the view to just that bucket.
  String? _filter;

  /// Room keys ('__unsorted__' or a tag name) the agent has collapsed. Rooms
  /// start expanded — a 3-column grid keeps even a 90-photo property to one
  /// continuous, scannable scroll, so there's no case for collapsing by
  /// default the way the (list-heavy) rental-inspections sections do.
  final Set<String> _collapsed = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<String> get _tags => _liveTags?.availableTags.isNotEmpty == true
      ? _liveTags!.availableTags
      : _galleryFallbackTags;

  GalleryCategories get _visibleGallery => _optimisticGallery ?? _gallery;
  List<String> get _visibleMasterOrder => _optimisticMasterOrder ?? _masterOrder;

  Future<void> _load({bool forceRefresh = false}) async {
    if (!_loaded && mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getProperty(widget.propertyId),
        _api
            .getGalleryTags(widget.propertyId)
            .then<Object?>((v) => v, onError: (_) => null),
      ]);
      if (!mounted) return;
      final property = results[0] as Property;
      final tags = results[1];
      setState(() {
        _gallery = GalleryCategories.fromJson(property.galleryCategories);
        _galleryFingerprint = property.galleryFingerprint;
        _galleryFallbackTags = property.galleryTags;
        _masterOrder = property.galleryImages;
        _selected.retainAll(_allUrls(_gallery, _masterOrder));
        if (tags is GalleryTagsData) _liveTags = tags;
        _loading = false;
        _loaded = true;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!_loaded) _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!_loaded) _error = "Couldn't load the gallery — check your connection";
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ---- Filing (selection + assign) ----

  void _toggle(String url) {
    setState(() {
      if (!_selected.remove(url)) _selected.add(url);
    });
  }

  bool _allSelected(List<String> urls) =>
      urls.isNotEmpty && urls.every(_selected.contains);

  void _selectAll(List<String> urls) {
    setState(() {
      if (_allSelected(urls)) {
        _selected.removeAll(urls);
      } else {
        _selected.addAll(urls);
      }
    });
  }

  Future<_RoomChoice?> _pickRoom(List<String> tags) {
    return showModalBottomSheet<_RoomChoice>(
      context: context,
      backgroundColor: AppTheme.background(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'File ${_selected.length} photo${_selected.length == 1 ? '' : 's'} under…',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary(ctx)),
                ),
              ),
              for (final tag in tags)
                ListTile(
                  title: Text(tag,
                      style: TextStyle(color: AppTheme.textPrimary(ctx))),
                  onTap: () => Navigator.pop(ctx, _RoomChoice(tag)),
                ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.add, color: AppTheme.brand),
                title: Text('New custom tag…',
                    style: TextStyle(
                        color: AppTheme.brand, fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(ctx, const _RoomChoice.newTag()),
              ),
              ListTile(
                leading: Icon(Icons.inbox_outlined,
                    color: AppTheme.textSecondary(ctx)),
                title: Text('Move to Unsorted',
                    style: TextStyle(color: AppTheme.textSecondary(ctx))),
                onTap: () => Navigator.pop(ctx, const _RoomChoice(null)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// [_pickRoom], plus the "New custom tag…" hand-off: prompts for a name,
  /// creates the tag, and answers with it as an ordinary choice. Backing out
  /// of the name prompt returns the agent to the picker rather than dropping
  /// the whole filing — the selection is still there, only the name was
  /// abandoned.
  Future<_RoomChoice?> _chooseRoom(List<String> tags) async {
    while (true) {
      final choice = await _pickRoom(tags);
      if (choice == null || !mounted) return null;
      if (!choice.isNewTag) return choice;
      final added = await showAddCustomTagDialog(context,
          api: _api, propertyId: widget.propertyId);
      if (!mounted) return null;
      if (added == null) continue;
      // Adopt the server's list now, not after the assign: the tag exists
      // whether or not the filing that follows goes through.
      setState(() => _liveTags = added.tags);
      return _RoomChoice(added.tag);
    }
  }

  Future<void> _fileSelection() async {
    if (_selected.isEmpty || _assigning) return;
    final choice = await _chooseRoom(_tags);
    if (choice == null || !mounted) return;
    await _assign(choice.tag);
  }

  Future<void> _assign(String? roomTag) async {
    final images = _selected.toList();
    if (images.isEmpty) return;
    setState(() => _assigning = true);
    try {
      final result =
          await _api.assignGalleryImages(widget.propertyId, images, roomTag);
      if (!mounted) return;
      setState(() {
        _adoptCategories(result.categories);
        // The server's fingerprint covers the room map, which just changed,
        // and this response doesn't carry the new one — so the value we
        // hold is now guaranteed stale. Dropping it lets the next reorder
        // go through unguarded rather than 409 every time.
        _galleryFingerprint = null;
        if (result.availableTags.isNotEmpty) {
          _liveTags = (_liveTags ?? GalleryTagsData.empty(widget.propertyId))
              .withAvailable(result.availableTags);
        }
        _selected.removeAll(images);
        _assigning = false;
      });
      _snack(result.message);
      if (result.isPartial) {
        _snack(
            "${result.unknownImages.length} photo(s) were no longer here — refreshing");
        await _load(forceRefresh: true);
      }
    } on TagValidationException catch (e) {
      if (!mounted) return;
      setState(() => _assigning = false);
      _snack(e.message);
      final retry = await _chooseRoom(e.availableTags);
      if (retry == null || !mounted) return;
      await _assign(retry.tag);
    } on StaleGalleryImagesException catch (e) {
      if (!mounted) return;
      setState(() {
        _selected.removeAll(e.unknownImages);
        _assigning = false;
      });
      _snack(e.message);
      await _load(forceRefresh: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _assigning = false);
      _snack(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _assigning = false);
      _snack('Could not file those photos — check your connection');
    }
  }

  // ---- Deleting ----

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty || _assigning || _reordering || _deleting) return;
    final images = _selected.toList();
    final n = images.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $n photo${n == 1 ? '' : 's'}?'),
        content: const Text(
            "This removes them from the property's gallery entirely. This "
            "can't be undone."),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          // Overriding minimumSize here, not just backgroundColor — without
          // it this inherits the app-wide ElevatedButtonTheme's full-width,
          // 56-tall primary-CTA sizing, which forces AlertDialog's actions
          // row to wrap Cancel above a giant red bar instead of the normal
          // side-by-side pair.
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      final result =
          await _api.deletePropertyImages(widget.propertyId, imageUrls: images);
      if (!mounted) return;
      setState(() {
        _selected.removeAll(images);
        _gallery = _withoutImages(_gallery, images);
        _masterOrder = _masterOrder.where((u) => !images.contains(u)).toList();
        // Same reason as in _assign: the gallery changed, the response has
        // no new fingerprint, so ours is stale by definition.
        _galleryFingerprint = null;
        _deleting = false;
      });
      // The files are gone server-side; don't let a re-upload at the same
      // URL (or the drag feedback) show them from disk.
      CoreXImageCache.evict(images).ignore();
      _snack(result.message);
      if (result.unknownIds.isNotEmpty) {
        // Some of what we asked to delete wasn't there any more — the local
        // list was already stale, so read the server's current truth rather
        // than guess at what else might have changed.
        await _load(forceRefresh: true);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      _snack(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      _snack('Could not delete those photos — check your connection');
    }
  }

  /// Every URL the screen currently knows about: all rooms, unsorted, and the
  /// master list.
  Set<String> _allUrls(GalleryCategories g, List<String> master) => {
        for (final urls in g.categories.values) ...urls,
        ...g.unsorted,
        ...master,
      };

  /// Takes the server's post-write room map — unless it's absent or empty,
  /// in which case the rooms already on screen are still right and adopting
  /// nothing would wipe every section. Then drops any selection that no
  /// longer exists, so Delete / File can't send URLs the server has already
  /// lost. Call inside `setState`.
  void _adoptCategories(GalleryCategories cats) {
    if (cats.categories.isNotEmpty || cats.unsorted.isNotEmpty) {
      _gallery = cats;
    }
    _selected.retainAll(_allUrls(_gallery, _masterOrder));
  }

  GalleryCategories _withoutImages(GalleryCategories base, List<String> images) {
    final remove = images.toSet();
    final cats = <String, List<String>>{
      for (final e in base.categories.entries)
        e.key: e.value.where((u) => !remove.contains(u)).toList(),
    };
    return GalleryCategories(
      categories: cats,
      unsorted: base.unsorted.where((u) => !remove.contains(u)).toList(),
    );
  }

  // ---- Photo reorder (drag within one room's grid) ----

  Future<void> _reorderPhotos(
      String roomTag, List<String> currentUrls, int oldIndex, int newIndex) async {
    if (_reordering) return;
    // [newIndex] is the cell the photo was dropped *onto*, and the photo
    // takes that cell's slot in either direction — remove-then-insert at the
    // target does exactly that. (A `ReorderableListView`-style `-1` when
    // moving forward is wrong here: it made a one-cell forward drag a no-op.)
    final urls = List<String>.from(currentUrls);
    urls.insert(newIndex, urls.removeAt(oldIndex));

    final base = _optimisticGallery ?? _gallery;
    final cats = Map<String, List<String>>.from(base.categories);
    cats[roomTag] = urls;

    setState(() {
      _reordering = true;
      _optimisticGallery =
          GalleryCategories(categories: cats, unsorted: base.unsorted);
    });

    try {
      final result = await _api.reorderGalleryImages(
        widget.propertyId,
        urls,
        roomTag: roomTag,
        fingerprint: _galleryFingerprint,
      );
      if (!mounted) return;
      setState(() {
        _adoptCategories(result.categories);
        _galleryFingerprint = result.galleryFingerprint;
        _reordering = false;
        _optimisticGallery = null;
      });
    } on StaleGalleryFingerprintException catch (e) {
      if (!mounted) return;
      setState(() {
        _reordering = false;
        _optimisticGallery = null;
      });
      _snack(e.message);
      await _load(forceRefresh: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _reordering = false;
        _optimisticGallery = null;
      });
      _snack(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _reordering = false;
        _optimisticGallery = null;
      });
      _snack('Could not save that order — check your connection');
    }
  }

  /// The master/portal order — [_kMasterFilter]'s view. This is the *only*
  /// call in this screen that omits `roomTag`, which is what actually
  /// updates the cover photo and the order the website shows; see the note
  /// on [_kMasterFilter].
  Future<void> _reorderMaster(int oldIndex, int newIndex) async {
    if (_reordering) return;
    final urls = List<String>.from(_visibleMasterOrder);
    urls.insert(newIndex, urls.removeAt(oldIndex)); // see _reorderPhotos

    setState(() {
      _reordering = true;
      _optimisticMasterOrder = urls;
    });

    try {
      final result = await _api.reorderGalleryImages(
        widget.propertyId,
        urls,
        fingerprint: _galleryFingerprint,
      );
      if (!mounted) return;
      setState(() {
        _masterOrder = result.galleryImages.isNotEmpty ? result.galleryImages : urls;
        _adoptCategories(result.categories);
        _galleryFingerprint = result.galleryFingerprint;
        _reordering = false;
        _optimisticMasterOrder = null;
      });
    } on StaleGalleryFingerprintException catch (e) {
      if (!mounted) return;
      setState(() {
        _reordering = false;
        _optimisticMasterOrder = null;
      });
      _snack(e.message);
      await _load(forceRefresh: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _reordering = false;
        _optimisticMasterOrder = null;
      });
      _snack(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _reordering = false;
        _optimisticMasterOrder = null;
      });
      _snack('Could not save that order — check your connection');
    }
  }

  /// The website shows one flat photo list, not rooms, so the room order set
  /// in the Sort sheet changes nothing there on its own. This flattens the
  /// current room order — each room's photos in their own order, then any
  /// stray rooms, then unsorted — into that one list and saves it as the
  /// master grid: the same call [_reorderMaster] makes, and the only one the
  /// website reads.
  Future<bool> _applyRoomOrderToWebsite(List<String> orderedTags) async {
    if (_reordering) return false;
    final gallery = _visibleGallery;
    final seen = <String>{};
    final flat = <String>[];
    void take(Iterable<String> urls) {
      for (final u in urls) {
        if (seen.add(u)) flat.add(u);
      }
    }

    for (final t in orderedTags) {
      take(gallery.categories[t] ?? const []);
    }
    for (final e in gallery.categories.entries) {
      if (!orderedTags.contains(e.key)) take(e.value);
    }
    take(gallery.unsorted);
    if (flat.isEmpty) {
      _snack('No photos to sort yet.');
      return false;
    }

    setState(() {
      _reordering = true;
      _optimisticMasterOrder = flat;
    });
    try {
      final result = await _api.reorderGalleryImages(
        widget.propertyId,
        flat,
        fingerprint: _galleryFingerprint,
      );
      if (!mounted) return false;
      final cats = result.categories;
      setState(() {
        _masterOrder =
            result.galleryImages.isNotEmpty ? result.galleryImages : flat;
        _adoptCategories(cats);
        _galleryFingerprint = result.galleryFingerprint;
        _reordering = false;
        _optimisticMasterOrder = null;
      });
      // Name the room whose photo is actually the new cover — the first
      // room in the order can be empty.
      final firstRoom = orderedTags.firstWhere(
          (t) => (gallery.categories[t] ?? const []).isNotEmpty,
          orElse: () => orderedTags.first);
      _snack('Website photo order updated — ${flat.length} photos, '
          '$firstRoom first.');
      return true;
    } on StaleGalleryFingerprintException catch (e) {
      if (!mounted) return false;
      setState(() {
        _reordering = false;
        _optimisticMasterOrder = null;
      });
      _snack(e.message);
      await _load(forceRefresh: true);
      return false;
    } on ApiException catch (e) {
      if (!mounted) return false;
      setState(() {
        _reordering = false;
        _optimisticMasterOrder = null;
      });
      _snack(e.message);
      return false;
    } catch (_) {
      if (!mounted) return false;
      setState(() {
        _reordering = false;
        _optimisticMasterOrder = null;
      });
      _snack('Could not update the website order — check your connection');
      return false;
    }
  }

  // ---- Room order ----

  Future<void> _openReorderRooms() async {
    final tags = _tags;
    if (tags.length < 2) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.background(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => _ReorderRoomsSheet(
        propertyId: widget.propertyId,
        api: _api,
        initialTags: tags,
        photoCount: (t) => _visibleGallery.categories[t]?.length ?? 0,
        onApplyToWebsite: _applyRoomOrderToWebsite,
        onReordered: (result) {
          if (result.availableTags.isEmpty) return;
          setState(() {
            _liveTags =
                (_liveTags ?? GalleryTagsData.empty(widget.propertyId))
                    .withAvailable(result.availableTags);
            // A filtered-to-one-room view survives a reorder untouched; only
            // clear it if that room is somehow gone from the new list.
            if (_filter != null &&
                _filter != _kUnsortedFilter &&
                _filter != _kMasterFilter &&
                !result.availableTags.contains(_filter)) {
              _filter = null;
            }
          });
        },
      ),
    );
  }

  // ---- Upload ----

  Future<void> _openUploadSheet({String? initialTag}) async {
    final uploaded = await GalleryUploadSheet.show(
      context,
      propertyId: widget.propertyId,
      initialTag: initialTag,
      lockTag: initialTag != null,
    );
    if ((uploaded ?? false) && mounted) {
      await _load(forceRefresh: true);
    }
  }

  // ---- Sections ----

  List<_RoomSection> _sections() {
    final gallery = _visibleGallery;
    final tags = _tags;
    final stray =
        gallery.categories.keys.where((k) => !tags.contains(k)).toList();

    final all = <_RoomSection>[
      if (gallery.unsorted.isNotEmpty)
        _RoomSection(
          key: '__unsorted__',
          tag: null,
          title: 'Unsorted',
          urls: gallery.unsorted,
          isUnsorted: true,
        ),
      for (final t in tags)
        _RoomSection(
          key: t,
          tag: t,
          title: t,
          urls: gallery.categories[t] ?? const [],
          isUnsorted: false,
        ),
      for (final t in stray)
        _RoomSection(
          key: t,
          tag: t,
          title: t,
          urls: gallery.categories[t] ?? const [],
          isUnsorted: false,
          stray: true,
        ),
    ];

    if (_filter == null) return all;
    if (_filter == _kUnsortedFilter) {
      return all.where((s) => s.isUnsorted).toList();
    }
    return all.where((s) => s.tag == _filter).toList();
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gallery'),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(
                foregroundColor: AppTheme.textPrimary(context)),
            icon: const Icon(Icons.swap_vert, size: 20),
            label: const Text('Sort'),
            onPressed: _tags.length > 1 ? _openReorderRooms : null,
          ),
          IconButton(
            tooltip: 'Add Photos',
            icon: const Icon(Icons.add_a_photo_outlined),
            onPressed: () => _openUploadSheet(),
          ),
        ],
      ),
      body: ContentSafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    if (_loading && !_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && !_loaded) {
      return _GalleryErrorState(message: _error!, onRetry: () => _load());
    }
    if (_filter == _kMasterFilter) {
      return _masterBody();
    }

    final sections = _sections();
    return RefreshIndicator(
      onRefresh: () => _load(forceRefresh: true),
      // A CustomScrollView with one SliverGrid per room, not a ListView of
      // shrinkWrap'd GridViews. shrinkWrap forces a GridView to lay out
      // *every* child up front to measure its own height — fine for one
      // room, but with dozens of rooms stacked in a ListView it means every
      // photo on the property gets laid out synchronously on every rebuild
      // (any selection tap, any collapse toggle). At ~90 photos that
      // synchronous layout pass ran past Android's 5s input-dispatch
      // timeout and the OS killed the app with "isn't responding". Each
      // room's SliverGrid here is a real sliver, so only what's near the
      // viewport is ever built or laid out, regardless of how many rooms or
      // photos the property has.
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(child: _filterChips()),
          ),
          if (_selected.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(child: _selectionBar()),
            ),
          if (sections.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: Text(
                    _filter == null
                        ? 'No photos yet. Tap Add Photos to get started.'
                        : 'No photos in this room.',
                    style: TextStyle(color: AppTheme.textSecondary(context)),
                  ),
                ),
              ),
            )
          else
            for (final section in sections) ..._roomSlivers(section),
          const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
        ],
      ),
    );
  }

  /// [_kMasterFilter]'s view: every photo on the property, flat, in master
  /// order — the one grid that's actually reorderable in a way the website
  /// picks up. See [_kMasterFilter] and [_reorderMaster].
  Widget _masterBody() {
    final order = _visibleMasterOrder;
    return RefreshIndicator(
      onRefresh: () => _load(forceRefresh: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(child: _filterChips()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Drag to set the order shown on the website — the first '
                'photo is the cover.',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary(context)),
              ),
            ),
          ),
          if (_selected.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(child: _selectionBar()),
            ),
          if (order.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: Text(
                    'No photos yet. Tap Add Photos to get started.',
                    style: TextStyle(color: AppTheme.textSecondary(context)),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: _masterGridSliver(order),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
        ],
      ),
    );
  }

  Widget _masterGridSliver(List<String> order) {
    final canReorder =
        !_assigning && !_reordering && !_deleting && order.length > 1;

    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      delegate: SliverChildBuilderDelegate(
        (ctx, i) {
          final url = order[i];
          final cell = _photoCell(url, isCover: i == 0);
          if (!canReorder) return cell;

          return DragTarget<int>(
            onWillAcceptWithDetails: (d) => d.data != i,
            onAcceptWithDetails: (d) => _reorderMaster(d.data, i),
            builder: (ctx, candidates, rejected) {
              final hovering = candidates.isNotEmpty;
              return Stack(
                fit: StackFit.expand,
                children: [
                  LongPressDraggable<int>(
                    data: i,
                    feedback: _dragFeedback(url),
                    childWhenDragging: Opacity(opacity: 0.3, child: cell),
                    child: cell,
                  ),
                  if (hovering)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: AppTheme.brand, width: 2),
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusSmall),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
        childCount: order.length,
      ),
    );
  }

  Widget _filterChips() {
    final gallery = _visibleGallery;
    final tags = _tags;
    final stray =
        gallery.categories.keys.where((k) => !tags.contains(k)).toList();

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip('All', selected: _filter == null,
              onTap: () => setState(() => _filter = null)),
          const SizedBox(width: 8),
          _chip('All Photos · ${_visibleMasterOrder.length}',
              selected: _filter == _kMasterFilter,
              onTap: () => setState(() => _filter = _kMasterFilter)),
          if (gallery.unsorted.isNotEmpty) ...[
            const SizedBox(width: 8),
            _chip('Unsorted · ${gallery.unsorted.length}',
                selected: _filter == _kUnsortedFilter,
                accent: Colors.orangeAccent,
                onTap: () => setState(() => _filter = _kUnsortedFilter)),
          ],
          for (final t in tags) ...[
            const SizedBox(width: 8),
            _chip('$t · ${gallery.categories[t]?.length ?? 0}',
                selected: _filter == t,
                onTap: () => setState(() => _filter = t)),
          ],
          for (final t in stray) ...[
            const SizedBox(width: 8),
            _chip('$t · ${gallery.categories[t]?.length ?? 0}',
                selected: _filter == t,
                onTap: () => setState(() => _filter = t)),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label,
      {required bool selected, required VoidCallback onTap, Color? accent}) {
    final color = accent ?? AppTheme.brand;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusChip),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.18)
              : AppTheme.surface2(context),
          borderRadius: BorderRadius.circular(AppTheme.radiusChip),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.6)
                : AppTheme.borderColor(context),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? color : AppTheme.textSecondary(context),
          ),
        ),
      ),
    );
  }

  Widget _selectionBar() {
    final n = _selected.length;
    final busy = _assigning || _reordering || _deleting;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.brand.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.brand.withValues(alpha: 0.4)),
      ),
      child: LayoutBuilder(builder: (ctx, constraints) {
        final label = Text(
          '$n photo${n == 1 ? '' : 's'} selected',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary(context)),
        );
        // A Wrap, not a Row: on a real phone width these three controls
        // (unlike PropertyGallery's plain two-button bar this was modeled
        // on) can be too wide even alone on their own line once the system
        // font scale is up a notch. A Row either overflows or — worse, the
        // way this actually broke live — hands a descendant Material button
        // a degenerate infinite-width constraint when squeezed inside the
        // narrow branch's Align below. Wrap always has somewhere to put the
        // overflow: a second line.
        final actions = Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            IconButton(
              tooltip: 'Delete',
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 32, minHeight: 32),
              iconSize: 19,
              visualDensity: VisualDensity.compact,
              color: Colors.redAccent,
              icon: _deleting
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.redAccent))
                  : const Icon(Icons.delete_outline),
              onPressed: busy ? null : _deleteSelected,
            ),
            TextButton(
              onPressed:
                  busy ? null : () => setState(() => _selected.clear()),
              // The app-wide button themes are sized for full-width primary
              // CTAs (ElevatedButtonTheme forces minimumSize 56 tall) —
              // fine for a "Save" button, way too heavy for an inline
              // action next to a selection count. Every control in this
              // bar overrides down to a compact ~32px pill instead.
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
              child: const Text('Clear'),
            ),
            ElevatedButton(
              onPressed: busy ? null : _fileSelection,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700),
              ),
              child: _assigning
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('File under…'),
            ),
          ],
        );

        // Same "stack below a certain width" rule as PropertyGallery's own
        // selection bar — three actions plus the count is too much for one
        // row once the system font scale or a narrow phone eats into it.
        final needed = 280 * MediaQuery.textScalerOf(ctx).scale(1.0);
        if (constraints.maxWidth < needed) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label,
              const SizedBox(height: 4),
              actions,
            ],
          );
        }
        // `label` at its own natural (short, single-line) size, then
        // `actions` gets whatever's left via Flexible rather than Expanded —
        // a Row always hands a *non*-flex child unbounded width to measure
        // itself against, so without this, three buttons' combined natural
        // width can exceed what's actually available even past the `needed`
        // threshold above (that gap is exactly how this broke live).
        // Flexible caps it at the remainder and lets the Wrap above fall
        // back to a second line instead.
        return Row(
          children: [
            label,
            const SizedBox(width: 8),
            Flexible(child: actions),
          ],
        );
      }),
    );
  }

  /// One room's slivers: a header box (always shown — the collapse toggle
  /// lives there), then, while expanded, its grid (or an empty-state line).
  /// A card *box* wrapping both would be simplest, but that needs to lay out
  /// its whole child up front the same way `Container` and `Column` always
  /// have — exactly the eager-layout trap this screen exists to avoid. The
  /// header is cheap regardless (one row), so only the grid needs to stay a
  /// real sliver.
  List<Widget> _roomSlivers(_RoomSection section) {
    final collapsed = _collapsed.contains(section.key);
    final total = section.urls.length;
    final borderColor = section.isUnsorted && total > 0
        ? Colors.orangeAccent.withValues(alpha: 0.5)
        : AppTheme.borderColor(context);

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        sliver: SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
            decoration: BoxDecoration(
              color: AppTheme.surface2(context),
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: borderColor),
            ),
            child: _roomHeader(section, collapsed, total),
          ),
        ),
      ),
      if (!collapsed)
        if (total == 0)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Text(
                section.isUnsorted
                    ? 'Nothing waiting to be filed.'
                    : 'No photos in this room yet.',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary(context)),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: _roomGridSliver(section),
          ),
    ];
  }

  Widget _roomHeader(_RoomSection section, bool collapsed, int total) {
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(collapsed ? Icons.chevron_right : Icons.expand_more,
              color: AppTheme.textSecondary(context)),
          onPressed: () => setState(() {
            collapsed
                ? _collapsed.remove(section.key)
                : _collapsed.add(section.key);
          }),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      section.title,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary(context)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _countPill(total, section.isUnsorted),
                ],
              ),
              if (section.stray)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('This room no longer exists on the property',
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.textMuted(context))),
                ),
            ],
          ),
        ),
        if (section.isUnsorted && section.urls.isNotEmpty)
          TextButton(
            onPressed: !_assigning && !_deleting
                ? () => _selectAll(section.urls)
                : null,
            style: TextButton.styleFrom(
                foregroundColor: AppTheme.brand,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32)),
            child:
                Text(_allSelected(section.urls) ? 'Select none' : 'Select all'),
          ),
        if (!section.isUnsorted && !section.stray)
          TextButton.icon(
            onPressed: () => _openUploadSheet(initialTag: section.title),
            icon: const Icon(Icons.add_a_photo, size: 14),
            label: const Text('Add'),
            style: TextButton.styleFrom(
                foregroundColor: AppTheme.brand,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32)),
          ),
      ],
    );
  }

  Widget _countPill(int count, bool isUnsorted) {
    final color =
        isUnsorted && count > 0 ? Colors.orangeAccent : AppTheme.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  /// A real sliver — as opposed to a `GridView` merely shaped like one —
  /// meaning only the cells actually near the viewport are ever built or
  /// laid out. See the note on [_body] for why that distinction is the
  /// entire fix here.
  Widget _roomGridSliver(_RoomSection section) {
    // A stray room's tag isn't on the property any more, so a room-scoped
    // reorder there is a guaranteed 422; and a drag during a delete could
    // PUT (and then re-adopt) a photo that's mid-removal.
    final canReorder = !section.isUnsorted &&
        !section.stray &&
        !_assigning &&
        !_reordering &&
        !_deleting &&
        section.urls.length > 1;

    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      delegate: SliverChildBuilderDelegate(
        (ctx, i) {
          final url = section.urls[i];
          final cell = _photoCell(url);
          if (!canReorder) return cell;

          return DragTarget<_DragPhoto>(
            onWillAcceptWithDetails: (d) =>
                d.data.roomTag == section.tag && d.data.index != i,
            onAcceptWithDetails: (d) =>
                _reorderPhotos(section.tag!, section.urls, d.data.index, i),
            builder: (ctx, candidates, rejected) {
              final hovering = candidates.isNotEmpty;
              return Stack(
                fit: StackFit.expand,
                children: [
                  LongPressDraggable<_DragPhoto>(
                    data: _DragPhoto(section.tag!, i),
                    feedback: _dragFeedback(url),
                    childWhenDragging: Opacity(opacity: 0.3, child: cell),
                    child: cell,
                  ),
                  if (hovering)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: AppTheme.brand, width: 2),
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusSmall),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
        childCount: section.urls.length,
      ),
    );
  }

  Widget _photoCell(String url, {bool isCover = false}) {
    final selected = _selected.contains(url);
    return GestureDetector(
      key: ValueKey('photo-cell-$url'),
      onTap: !_assigning && !_deleting ? () => _toggle(url) : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            // Server thumbnail, cached to disk — the whole point of this
            // screen is browsing a property's photos repeatedly (filtering,
            // reordering, coming back to it later), and none of that should
            // re-download anything, let alone the full-size originals.
            child: CoreXPhoto.thumb(
              url: url,
              // Three columns: decode at cell size, not camera size.
              logicalWidth: MediaQuery.sizeOf(context).width / 3,
              placeholder: (ctx) => Container(
                color: AppTheme.surface2(ctx),
                child: const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              errorWidget: (ctx) => Container(
                color: AppTheme.surface2(ctx),
                child: Icon(Icons.broken_image_outlined,
                    color: AppTheme.textMuted(ctx)),
              ),
            ),
          ),
          if (selected)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.brand.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  border: Border.all(color: AppTheme.brand, width: 2),
                ),
              ),
            ),
          Positioned(
            top: 4,
            right: 4,
            child: Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              size: 18,
              color: selected ? Colors.white : Colors.white70,
            ),
          ),
          if (isCover)
            Positioned(
              bottom: 4,
              left: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(AppTheme.radiusChip),
                ),
                child: const Text(
                  'Cover',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dragFeedback(String url) {
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: 96,
        height: 96,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          child: Container(
            decoration: BoxDecoration(
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 10),
              ],
              border: Border.all(color: AppTheme.brand, width: 2),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: CoreXPhoto.thumb(
              url: url,
              logicalWidth: 96,
              placeholder: (ctx) => Container(color: AppTheme.surface2(ctx)),
              errorWidget: (ctx) => Container(color: AppTheme.surface2(ctx)),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomSection {
  final String key;
  final String? tag;
  final String title;
  final List<String> urls;
  final bool isUnsorted;
  final bool stray;

  const _RoomSection({
    required this.key,
    required this.tag,
    required this.title,
    required this.urls,
    required this.isUnsorted,
    this.stray = false,
  });
}

class _DragPhoto {
  final String roomTag;
  final int index;
  const _DragPhoto(this.roomTag, this.index);
}

class _RoomChoice {
  final String? tag;

  /// The agent picked "New custom tag…" — the caller prompts for a name,
  /// creates it, and files under that. Never sent to the server as-is.
  final bool isNewTag;

  const _RoomChoice(this.tag) : isNewTag = false;
  const _RoomChoice.newTag()
      : tag = null,
        isNewTag = true;
}

class _GalleryErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _GalleryErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: AppTheme.textMuted(context), size: 32),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary(context))),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// A numbered, drag-to-reorder grid of room names — the low-friction
/// alternative to the small handle icon [PropertyGallery] wedges into a
/// section header next to a photo grid that is *also* draggable. Two
/// columns fit roughly twice as many rooms on screen at once as a single
/// list, which matters once a property has a dozen-plus rooms — the same
/// case the number dropdown exists for.
///
/// Every tile shows its 1-based position, and that number is itself a
/// dropdown: pick a different number and the room jumps straight there — no
/// need to drag it the length of the list. Drag still works for a quick
/// nearby swap; the dropdown is for the long moves drag is bad at, the same
/// complaint that motivated the (now-removed) "move to top/bottom" menu —
/// the dropdown is strictly more capable, since it reaches *any* position,
/// not just the two ends.
class _ReorderRoomsSheet extends StatefulWidget {
  final int propertyId;
  final ApiService api;
  final List<String> initialTags;
  final ValueChanged<TagReorderResult> onReordered;

  /// Pushes the sheet's current room order to the website as one flat photo
  /// list. Resolves true once saved, so the sheet can close on success.
  final Future<bool> Function(List<String> tags) onApplyToWebsite;

  /// How many photos a room holds right now — so the apply-to-website copy
  /// can name the room whose photo really becomes the cover, not just
  /// whichever room happens to be first (it may be empty).
  final int Function(String tag) photoCount;

  const _ReorderRoomsSheet({
    required this.propertyId,
    required this.api,
    required this.initialTags,
    required this.onReordered,
    required this.onApplyToWebsite,
    required this.photoCount,
  });

  @override
  State<_ReorderRoomsSheet> createState() => _ReorderRoomsSheetState();
}

class _ReorderRoomsSheetState extends State<_ReorderRoomsSheet> {
  late List<String> _tags = List.of(widget.initialTags);
  bool _saving = false;
  bool _applying = false;

  Future<void> _applyToWebsite() async {
    if (_saving || _applying || _tags.isEmpty) return;
    final first = _tags.firstWhere((t) => widget.photoCount(t) > 0,
        orElse: () => _tags.first);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sort website photos by room?'),
        content: Text(
            'Every photo on the website will be reordered to follow this '
            'room order, starting with $first. The cover photo becomes the '
            'first $first photo.'),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sort website'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _applying = true);
    final ok = await widget.onApplyToWebsite(List.of(_tags));
    if (!mounted) return;
    setState(() => _applying = false);
    if (ok) Navigator.of(context).pop();
  }

  /// Moves the room at [oldIndex] so it ends up at [newIndex] (both
  /// 0-based, final positions — not `ReorderableListView.onReorder`'s
  /// pre-removal convention). Used by both the number dropdown and the
  /// grid's own drag-and-drop, so there is exactly one place that turns "put
  /// this room at position N" into a save.
  Future<void> _moveToPosition(int oldIndex, int newIndex) async {
    if (_saving || _applying || newIndex == oldIndex) return;
    final before = List<String>.from(_tags);
    final tags = List<String>.from(_tags);
    tags.insert(newIndex, tags.removeAt(oldIndex));

    setState(() {
      _tags = tags;
      _saving = true;
    });

    try {
      final result = await widget.api.reorderGalleryTags(widget.propertyId, tags);
      if (!mounted) return;
      widget.onReordered(result);
      setState(() => _saving = false);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _tags = before;
        _saving = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _tags = before;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save that order — check your connection')));
    }
  }

  /// A dragged tile is dropped *onto* another tile and takes that tile's
  /// slot — which is exactly `_moveToPosition`'s final-index contract, in
  /// both directions. (The `ReorderableListView`-style "minus one when
  /// moving forward" adjustment doesn't belong here: it turned dropping a
  /// room onto its right-hand neighbour into a no-op.)
  void _onDropOnto(int oldIndex, int droppedOnIndex) {
    _moveToPosition(oldIndex, droppedOnIndex);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Reorder rooms',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary(context)),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Drag to fine-tune, or pick a number to jump a room straight '
                  'to that position.',
                  style:
                      TextStyle(fontSize: 12, color: AppTheme.textSecondary(context)),
                ),
              ),
            ),
            if (_saving) const LinearProgressIndicator(minHeight: 2),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  mainAxisExtent: 46,
                ),
                itemCount: _tags.length,
                itemBuilder: (ctx, i) => _tagCell(i),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'This order only changes the app. To show photos on the '
                    'website room by room in this order, apply it:',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary(context)),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: (_saving || _applying) ? null : _applyToWebsite,
                    icon: _applying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.public, size: 18),
                    label: const Text('Sort website photos by room'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The `key` lives on this method's return value — the direct child
  /// `GridView.builder` sees — rather than down inside [_tagTile], so
  /// Flutter tracks each tile by the room it holds, not by its grid slot,
  /// across a reorder.
  Widget _tagCell(int i) {
    final key = ValueKey(_tags[i]);
    final tile = _tagTile(i);
    if (_saving || _applying) return KeyedSubtree(key: key, child: tile);

    return DragTarget<int>(
      key: key,
      onWillAcceptWithDetails: (d) => d.data != i,
      onAcceptWithDetails: (d) => _onDropOnto(d.data, i),
      builder: (ctx, candidates, rejected) {
        final hovering = candidates.isNotEmpty;
        return Stack(
          fit: StackFit.expand,
          children: [
            LongPressDraggable<int>(
              data: i,
              feedback: _tagDragFeedback(_tags[i]),
              childWhenDragging: Opacity(opacity: 0.3, child: tile),
              child: tile,
            ),
            if (hovering)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.brand, width: 2),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _tagTile(int i) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface2(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Row(
        children: [
          Icon(Icons.drag_indicator, size: 16, color: AppTheme.textMuted(context)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              _tags[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: AppTheme.textPrimary(context)),
            ),
          ),
          const SizedBox(width: 4),
          _positionBadge(i),
        ],
      ),
    );
  }

  /// The room's 1-based position, and the control that jumps it to any
  /// other one — rebuilt from [_tags]' current order every time, so a drag,
  /// a different tile's picker pick, or a server-confirmed reorder all show
  /// up here immediately.
  Widget _positionBadge(int i) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusChip),
      onTap: _saving ? null : () => _pickPosition(i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.brand.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTheme.radiusChip),
          border: Border.all(color: AppTheme.brand.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${i + 1}',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  // Readable against the tint in both themes — black in
                  // light mode, white in dark — same token every other
                  // label on this screen already uses.
                  color: AppTheme.textPrimary(context)),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 16, color: AppTheme.brand),
          ],
        ),
      ),
    );
  }

  /// A sheet of every position as a number chip, laid out with `Wrap` so
  /// several sit side by side per row — a dozen-plus rooms used to mean a
  /// dropdown that was mostly scrolling to reach the far numbers; a grid of
  /// chips puts nearly all of them on screen at once instead.
  Future<void> _pickPosition(int i) async {
    final current = i + 1;
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppTheme.background(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Move "${_tags[i]}" to position',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary(ctx)),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints:
                    BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var p = 1; p <= _tags.length; p++)
                        _positionChip(ctx, p, current: current),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (selected != null && selected != current) {
      _moveToPosition(i, selected - 1);
    }
  }

  Widget _positionChip(BuildContext ctx, int p, {required int current}) {
    final selected = p == current;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => Navigator.of(ctx).pop(p),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected
              ? AppTheme.brand.withValues(alpha: 0.18)
              : AppTheme.surface2(ctx),
          border: Border.all(
              color: selected ? AppTheme.brand : AppTheme.borderColor(ctx)),
        ),
        child: Text(
          '$p',
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? AppTheme.brand : AppTheme.textPrimary(ctx)),
        ),
      ),
    );
  }

  Widget _tagDragFeedback(String tag) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface2(context),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(color: AppTheme.brand, width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
        ),
        child: Text(
          tag,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: AppTheme.textPrimary(context)),
        ),
      ),
    );
  }
}
