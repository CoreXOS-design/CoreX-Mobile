import 'package:flutter/material.dart';

import '../../models/gallery_tags.dart';
import '../../services/api_service.dart';
import '../../services/upload_queue.dart';
import '../../services/upload_service.dart';
import '../../theme.dart';
import 'add_custom_tag_dialog.dart';
import 'upload_status_bar.dart';
import '../corex_photo.dart';

/// The room-by-room photo gallery for one property.
///
/// Renders three things that used to be missing, and which together are why an
/// agent could shoot 35 photos and see 8:
///
///  1. **Unsorted.** Photos reach the property with no `room_tag` — deliberately
///     ("No tag"), or because an upload lost its tag on the way. The payload
///     used to expose only `categories`, so those photos were stored, counted
///     nowhere, and shown on no screen. They now get their own section, first
///     in the list while it has anything in it, because an unfiled photo is
///     work outstanding.
///  2. **Filing.** Photos in any section can be multi-selected and moved to a
///     room (or back to Unsorted) in one call, and the grid re-renders from the
///     server's response — no reload, and no chance of the local list and the
///     server disagreeing about where a photo lives.
///  3. **What hasn't uploaded yet.** Queued photos appear as local
///     placeholders, in the section they are headed for, badged pending /
///     uploading / failed. The count the agent sees matches the count they
///     shot. A queued photo is never drawn as though it had landed.
///
/// The room vocabulary is entirely the server's: whatever `available_tags`
/// returns, in its order. There are around fifty space types and the list grows
/// without an app release, so nothing here may assume a fixed set of names.
class PropertyGallery extends StatefulWidget {
  final int propertyId;

  /// Server-side gallery, straight from `gallery_categories`.
  final GalleryCategories gallery;

  /// Rooms this property offers, from `/gallery/tags` (or an assign response).
  final List<String> availableTags;

  /// The property's last-known `gallery_fingerprint`, for optimistic-
  /// concurrency protection on a reorder. `null` is fine — the reorder call
  /// simply omits it and skips the conflict check.
  final String? galleryFingerprint;

  /// Disables every mutating affordance — used while the parent form saves.
  final bool enabled;

  /// A newer gallery / tag list arrived from an assign response; the parent
  /// should adopt both so its own state doesn't go stale behind this widget.
  final ValueChanged<GalleryAssignResult> onAssigned;

  /// A photo drag-reorder was saved; the parent should adopt the recomputed
  /// gallery and fingerprint the same way it does for [onAssigned].
  final ValueChanged<GalleryReorderResult> onReordered;

  /// A room drag-reorder was saved; the parent should adopt the new tag order.
  final ValueChanged<TagReorderResult> onTagsReordered;

  /// A custom tag was created from the "File under…" picker; the parent
  /// should adopt the refreshed tag list. Fires before the assign that
  /// follows, so the tag survives even if that filing fails.
  final ValueChanged<GalleryTagsData> onTagAdded;

  /// The local photo list is stale (the server didn't recognise URLs we sent).
  /// The parent should re-fetch the property.
  final Future<void> Function() onRefreshRequested;

  /// Open the capture sheet, optionally pre-selecting a room.
  final void Function({String? initialTag}) onAddPhotos;

  const PropertyGallery({
    super.key,
    required this.propertyId,
    required this.gallery,
    required this.availableTags,
    this.galleryFingerprint,
    required this.enabled,
    required this.onAssigned,
    required this.onReordered,
    required this.onTagsReordered,
    required this.onTagAdded,
    required this.onRefreshRequested,
    required this.onAddPhotos,
  });

  @override
  State<PropertyGallery> createState() => _PropertyGalleryState();
}

/// Label for the untagged bucket. Only ever a display string — it is never
/// sent as a `room_tag`; "no room" is transmitted as `null`.
const String _unsortedLabel = 'Unsorted';

class _PropertyGalleryState extends State<PropertyGallery> {
  final ApiService _api = ApiService();
  final UploadQueue _queue = UploadQueue.instance;
  final UploadService _uploader = UploadService.instance;

  /// Selected photo URLs, exactly as the API gave them to us — the assign
  /// endpoint matches on them verbatim, so they are never normalised here.
  final Set<String> _selected = {};

  bool _assigning = false;

  /// True while a photo-reorder save is in flight. Gates *every* section's
  /// drag affordance at once (not just the one being dragged) to keep a
  /// second drag from racing the first's optimistic state.
  bool _reordering = false;

  /// The dragged-to order for one room, shown immediately while the save in
  /// [_reorderPhotos] is in flight; cleared once the server confirms (or
  /// rejects) it, at which point [widget.gallery] is the source of truth again.
  GalleryCategories? _optimisticGallery;

  bool _reorderingTags = false;

  /// The dragged-to tag order, shown immediately while [_reorderTags]'s save
  /// is in flight.
  List<String>? _optimisticTags;

  @override
  void initState() {
    super.initState();
    _queue.addListener(_onChanged);
    _uploader.addListener(_onChanged);
    // Warms the durable store so the placeholders appear on first paint.
    _queue.itemsFor(widget.propertyId).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _queue.removeListener(_onChanged);
    _uploader.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ---- Filing ----

  void _toggle(String url) {
    setState(() {
      if (!_selected.remove(url)) _selected.add(url);
    });
  }

  /// Asks which room the selection should go to. Returns `null` if dismissed;
  /// a choice wrapping `null` means Unsorted.
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
                title: Text('Move to $_unsortedLabel',
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
      // Hand the list up now, not after the assign: the tag exists whether
      // or not the filing that follows goes through.
      widget.onTagAdded(added.tags);
      return _RoomChoice(added.tag);
    }
  }

  Future<void> _fileSelection() async {
    if (_selected.isEmpty || _assigning) return;
    final choice = await _chooseRoom(widget.availableTags);
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
      // Re-render straight from the response. The server has just recomputed
      // both the gallery and the tag list, so adopting them wholesale is what
      // makes a re-file a *move*: the photo leaves its old section in the same
      // frame it appears in the new one, with no reload and no way for the two
      // to briefly both show it.
      widget.onAssigned(result);
      setState(() {
        _selected.removeAll(images);
        _assigning = false;
      });
      _snack(result.message);
      if (result.isPartial) {
        // Some of what we sent is no longer on the property. What moved,
        // moved; the rest needs a fresh read.
        _snack(
            "${result.unknownImages.length} photo(s) were no longer here — refreshing");
        await widget.onRefreshRequested();
      }
    } on TagValidationException catch (e) {
      // The room is gone from this property. Refresh the list and re-prompt
      // against it — never retry the same tag blind.
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
      await widget.onRefreshRequested();
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

  // ---- Reordering ----

  /// Persists a drag result within one room's bucket. Applied optimistically
  /// so the grid shows the drop in the same frame it happens; reverted if the
  /// server rejects it (stale fingerprint, permission, or a dropped
  /// connection) since at that point [widget.gallery] is the only order that
  /// is actually true.
  Future<void> _reorderPhotos(
      String roomTag, List<String> currentUrls, int oldIndex, int newIndex) async {
    if (_reordering) return;
    final urls = List<String>.from(currentUrls);
    if (newIndex > oldIndex) newIndex -= 1;
    urls.insert(newIndex, urls.removeAt(oldIndex));

    final base = _optimisticGallery ?? widget.gallery;
    final cats = Map<String, List<String>>.from(base.categories);
    cats[roomTag] = urls;

    setState(() {
      _reordering = true;
      _optimisticGallery = GalleryCategories(categories: cats, unsorted: base.unsorted);
    });

    try {
      final result = await _api.reorderGalleryImages(
        widget.propertyId,
        urls,
        roomTag: roomTag,
        fingerprint: widget.galleryFingerprint,
      );
      if (!mounted) return;
      // Re-render straight from the response, same as [_assign] — the server
      // has just recomputed the gallery, so there is no reason to keep the
      // optimistic guess around once the real answer is in.
      widget.onReordered(result);
      setState(() {
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
      await widget.onRefreshRequested();
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

  /// Persists a drag result over the room order itself. Same optimistic /
  /// revert shape as [_reorderPhotos], scoped to the tag list instead of one
  /// room's photos.
  Future<void> _reorderTags(
      List<String> currentTags, int oldIndex, int newIndex) async {
    if (_reorderingTags) return;
    final tags = List<String>.from(currentTags);
    if (newIndex > oldIndex) newIndex -= 1;
    tags.insert(newIndex, tags.removeAt(oldIndex));

    setState(() {
      _reorderingTags = true;
      _optimisticTags = tags;
    });

    try {
      final result = await _api.reorderGalleryTags(widget.propertyId, tags);
      if (!mounted) return;
      widget.onTagsReordered(result);
      setState(() {
        _reorderingTags = false;
        _optimisticTags = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _reorderingTags = false;
        _optimisticTags = null;
      });
      _snack(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _reorderingTags = false;
        _optimisticTags = null;
      });
      _snack('Could not save that order — check your connection');
    }
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    // The optimistic order stands in for the server's until a drag's save
    // resolves — see [_reorderPhotos] / [_reorderTags].
    final gallery = _optimisticGallery ?? widget.gallery;
    final liveTags = _optimisticTags ?? widget.availableTags;

    final queued = _queue.cachedItemsFor(widget.propertyId);
    final unsortedQueued = queued.where((e) => e.roomTag == null).toList();

    // Sections to render, in order:
    //   Unsorted (only while it holds something), then every live room, then
    //   any category the property still has photos under but no longer offers
    //   as a tag (a space the agent deleted). That last group would otherwise
    //   render nowhere — the same disappearing act as the unsorted bucket.
    final strayTags = gallery.categories.keys
        .where((k) => !liveTags.contains(k))
        .toList();

    final showUnsorted =
        gallery.unsorted.isNotEmpty || unsortedQueued.isNotEmpty;

    // Dragging the room order itself only makes sense with more than one
    // room, and only while nothing else here is mid-save.
    final canReorderTags =
        widget.enabled && !_assigning && !_reorderingTags && liveTags.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The same bar the camera and the upload sheet show, so the count the
        // agent saw while shooting is the count they see here.
        UploadStatusBar(propertyId: widget.propertyId),
        _buildFailureDetail(queued),
        if (_selected.isNotEmpty) _buildSelectionBar(),
        if (showUnsorted)
          _buildSection(
            title: _unsortedLabel,
            urls: gallery.unsorted,
            queued: unsortedQueued,
            isUnsorted: true,
            canAdd: false,
          ),
        if (canReorderTags)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: liveTags.length,
            // Flutter >=3.41 deprecates onReorder in favour of onReorderItem;
            // that callback does not exist on the 3.38.7 used locally and now
            // pinned in codemagic.yaml, so keep onReorder until the toolchain
            // is upgraded everywhere at once.
            // ignore: deprecated_member_use
            onReorder: (oldIndex, newIndex) =>
                _reorderTags(liveTags, oldIndex, newIndex),
            itemBuilder: (ctx, i) {
              final tag = liveTags[i];
              return _buildSection(
                key: ValueKey('tag-$tag'),
                title: tag,
                urls: gallery.categories[tag] ?? const [],
                queued: queued.where((e) => e.roomTag == tag).toList(),
                isUnsorted: false,
                canAdd: true,
                roomTag: tag,
                tagDragHandle: ReorderableDragStartListener(
                  index: i,
                  child: Icon(Icons.drag_indicator,
                      size: 18, color: AppTheme.textMuted(context)),
                ),
              );
            },
          )
        else
          for (final tag in liveTags)
            _buildSection(
              title: tag,
              urls: gallery.categories[tag] ?? const [],
              queued: queued.where((e) => e.roomTag == tag).toList(),
              isUnsorted: false,
              canAdd: true,
              roomTag: tag,
            ),
        for (final tag in strayTags)
          _buildSection(
            title: tag,
            urls: gallery.categories[tag] ?? const [],
            queued: queued.where((e) => e.roomTag == tag).toList(),
            isUnsorted: false,
            canAdd: false,
            subtitle: 'This room no longer exists on the property',
          ),
        if (!showUnsorted && liveTags.isEmpty && strayTags.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'No photos yet. Add spaces to unlock rooms, or tap Upload to add '
              'photos you can file later.',
              style: TextStyle(color: AppTheme.textSecondary(context)),
            ),
          ),
      ],
    );
  }

  /// The reasons behind a failure, under the shared bar.
  ///
  /// [UploadStatusBar] says *how many* didn't upload and offers the retry;
  /// this says *why*, in the server's own words. "Upload failed" tells the
  /// agent nothing they can act on; "Image is too large" tells them
  /// everything, so the messages stay even though the count moved out.
  Widget _buildFailureDetail(List<PendingUpload> queued) {
    final failed = queued
        .where((e) => e.state == PendingUploadState.failed)
        .toList(growable: false);
    if (failed.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...failed.take(3).map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '• ${f.error ?? 'Upload failed'}',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary(context)),
                ),
              )),
          if (failed.length > 3)
            Text('• and ${failed.length - 3} more',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textMuted(context))),
        ],
      ),
    );
  }

  Widget _buildSelectionBar() {
    final n = _selected.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.brand.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.brand.withValues(alpha: 0.4)),
      ),
      child: LayoutBuilder(builder: (ctx, constraints) {
        final label = Text(
          '$n photo${n == 1 ? '' : 's'} selected',
          // Never allowed to wrap. Squeezed narrow enough, a wrapping Text
          // breaks one character per line and turns this bar into a tall
          // column of single letters — the "one long box" report.
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary(context)),
        );
        final clear = TextButton(
          onPressed:
              _assigning ? null : () => setState(() => _selected.clear()),
          child: const Text('Clear'),
        );
        final file = ElevatedButton(
          onPressed: (_assigning || _reordering || !widget.enabled)
              ? null
              : _fileSelection,
          child: _assigning
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('File under…'),
        );

        // The two buttons are sized by their own text, so they grow with the
        // system font scale while the bar does not. Past a point they leave
        // the label nothing, so below that the bar stacks instead of letting
        // the label collapse. Ellipsising alone would "fix" it by hiding the
        // count, which is the one thing this bar exists to say.
        final needed = 230 * MediaQuery.textScalerOf(ctx).scale(1.0);
        if (constraints.maxWidth < needed) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label,
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [clear, const SizedBox(width: 4), file],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: label),
            clear,
            file,
          ],
        );
      }),
    );
  }

  Widget _buildSection({
    Key? key,
    required String title,
    required List<String> urls,
    required List<PendingUpload> queued,
    required bool isUnsorted,
    required bool canAdd,
    String? subtitle,
    String? roomTag,
    Widget? tagDragHandle,
  }) {
    // The count is everything the agent can see in this room: what the server
    // holds plus what is still on its way there. Showing only the server's
    // number is what made a shoot look half-lost.
    final total = urls.length + queued.length;

    // Dragging photos needs an unambiguous room to save the new order under,
    // and a settled list to drag within — Unsorted has no reorder scope of
    // its own (see [ApiService.reorderGalleryImages]), and a photo mid-upload
    // has no server position yet to reorder relative to.
    final canReorderPhotos = !isUnsorted &&
        roomTag != null &&
        widget.enabled &&
        !_assigning &&
        !_reordering &&
        queued.isEmpty &&
        urls.length > 1;

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: isUnsorted && urls.isNotEmpty
              ? Colors.orangeAccent.withValues(alpha: 0.5)
              : AppTheme.borderColor(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: BoxDecoration(
              color: AppTheme.surface2(context),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppTheme.radius)),
              border: Border(
                bottom: BorderSide(color: AppTheme.borderColor(context)),
              ),
            ),
            child: Row(
              children: [
                if (tagDragHandle != null) ...[
                  tagDragHandle,
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary(context)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _countPill(total, isUnsorted),
                        ],
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subtitle,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textMuted(context))),
                        ),
                    ],
                  ),
                ),
                if (isUnsorted && urls.isNotEmpty)
                  TextButton(
                    onPressed: widget.enabled && !_assigning && !_reordering
                        ? () => _selectAll(urls)
                        : null,
                    style: TextButton.styleFrom(
                        foregroundColor: AppTheme.brand,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32)),
                    child:
                        Text(_allSelected(urls) ? 'Select none' : 'Select all'),
                  ),
                if (canAdd)
                  TextButton.icon(
                    onPressed: widget.enabled
                        ? () => widget.onAddPhotos(initialTag: title)
                        : null,
                    icon: const Icon(Icons.add_a_photo, size: 14),
                    label: const Text('Add Photo'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppTheme.brand,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32)),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: total == 0
                ? Text(
                    isUnsorted
                        ? 'Nothing waiting to be filed.'
                        : 'No photos in this room yet.',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary(context)),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isUnsorted && urls.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Tap photos to select, then file them under a room.',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary(context)),
                          ),
                        ),
                      SizedBox(
                        height: 90,
                        child: canReorderPhotos
                            ? ReorderableListView.builder(
                                scrollDirection: Axis.horizontal,
                                buildDefaultDragHandles: false,
                                itemCount: urls.length,
                                // ignore: deprecated_member_use
                                onReorder: (oldIndex, newIndex) =>
                                    _reorderPhotos(
                                        roomTag, urls, oldIndex, newIndex),
                                itemBuilder: (ctx, i) {
                                  final url = urls[i];
                                  return Padding(
                                    key: ValueKey('photo-$roomTag-$url'),
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ReorderableDelayedDragStartListener(
                                      index: i,
                                      child: _remoteThumb(url),
                                    ),
                                  );
                                },
                              )
                            : ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  for (final url in urls) ...[
                                    _remoteThumb(url),
                                    const SizedBox(width: 8),
                                  ],
                                  for (final item in queued) ...[
                                    _pendingThumb(item),
                                    const SizedBox(width: 8),
                                  ],
                                ],
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
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

  /// A photo the server holds. Selectable — that is what filing operates on.
  Widget _remoteThumb(String url) {
    final selected = _selected.contains(url);
    return GestureDetector(
      onTap: widget.enabled && !_assigning && !_reordering
          ? () => _toggle(url)
          : null,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            // Server thumbnail, cached to disk (not just Flutter's in-memory
            // ImageCache) so reopening this property's gallery — or just
            // navigating back to it — doesn't re-download every photo again.
            child: CoreXPhoto.thumb(
              url: url,
              logicalWidth: 120,
              width: 120,
              height: 90,
              placeholder: (_) => Container(
                width: 120,
                height: 90,
                color: AppTheme.surface2(context),
              ),
              errorWidget: (_) => Container(
                width: 120,
                height: 90,
                color: AppTheme.surface2(context),
                child: Icon(Icons.broken_image,
                    color: AppTheme.textMuted(context)),
              ),
            ),
          ),
          if (selected)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.brand.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppTheme.radius),
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
        ],
      ),
    );
  }

  /// A photo still on this phone. Deliberately distinct from [_remoteThumb]:
  /// dimmed, badged, and not selectable, because it cannot be filed until the
  /// server has it and a URL to name it by. Only a 2xx turns one of these into
  /// a real thumbnail.
  Widget _pendingThumb(PendingUpload item) {
    final failed = item.state == PendingUploadState.failed;
    final uploading = item.state == PendingUploadState.uploading;
    final Color tint =
        failed ? Colors.redAccent : (uploading ? AppTheme.brand : Colors.grey);
    final String label =
        failed ? 'Failed' : (uploading ? 'Uploading' : 'Waiting');

    return Semantics(
      label: '$label — not yet uploaded',
      child: Stack(
        children: [
          Opacity(
            opacity: 0.55,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              child: Image.file(item.file,
                  width: 120, height: 90, fit: BoxFit.cover),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radius),
                border: Border.all(
                    color: tint.withValues(alpha: 0.8),
                    width: 1.5,
                    style: BorderStyle.solid),
              ),
            ),
          ),
          if (uploading)
            const Positioned.fill(
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.9),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(AppTheme.radius),
                  bottomRight: Radius.circular(AppTheme.radius),
                ),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
            ),
          ),
          if (failed)
            Positioned(
              top: 2,
              right: 2,
              child: InkWell(
                onTap: () => _uploader.retry(item),
                child: Container(
                  decoration: const BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                  padding: const EdgeInsets.all(2),
                  child:
                      const Icon(Icons.refresh, color: Colors.white, size: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Wrapper so the room picker can return "Unsorted" (`null`) distinctly from
/// "dismissed" (also `null` out of [showModalBottomSheet]).
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
