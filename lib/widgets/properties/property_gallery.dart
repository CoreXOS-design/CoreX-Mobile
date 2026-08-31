import 'package:flutter/material.dart';

import '../../models/gallery_tags.dart';
import '../../services/api_service.dart';
import '../../services/upload_queue.dart';
import '../../services/upload_service.dart';
import '../../theme.dart';
import 'upload_status_bar.dart';

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

  /// Disables every mutating affordance — used while the parent form saves.
  final bool enabled;

  /// A newer gallery / tag list arrived from an assign response; the parent
  /// should adopt both so its own state doesn't go stale behind this widget.
  final ValueChanged<GalleryAssignResult> onAssigned;

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
    required this.enabled,
    required this.onAssigned,
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

  Future<void> _fileSelection() async {
    if (_selected.isEmpty || _assigning) return;
    final choice = await _pickRoom(widget.availableTags);
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
      final retry = await _pickRoom(e.availableTags);
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

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final queued = _queue.cachedItemsFor(widget.propertyId);
    final unsortedQueued = queued.where((e) => e.roomTag == null).toList();

    // Sections to render, in order:
    //   Unsorted (only while it holds something), then every live room, then
    //   any category the property still has photos under but no longer offers
    //   as a tag (a space the agent deleted). That last group would otherwise
    //   render nowhere — the same disappearing act as the unsorted bucket.
    final liveTags = widget.availableTags;
    final strayTags = widget.gallery.categories.keys
        .where((k) => !liveTags.contains(k))
        .toList();

    final showUnsorted =
        widget.gallery.unsorted.isNotEmpty || unsortedQueued.isNotEmpty;

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
            urls: widget.gallery.unsorted,
            queued: unsortedQueued,
            isUnsorted: true,
            canAdd: false,
          ),
        for (final tag in liveTags)
          _buildSection(
            title: tag,
            urls: widget.gallery.categories[tag] ?? const [],
            queued: queued.where((e) => e.roomTag == tag).toList(),
            isUnsorted: false,
            canAdd: true,
          ),
        for (final tag in strayTags)
          _buildSection(
            title: tag,
            urls: widget.gallery.categories[tag] ?? const [],
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
          onPressed: (_assigning || !widget.enabled) ? null : _fileSelection,
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
    required String title,
    required List<String> urls,
    required List<PendingUpload> queued,
    required bool isUnsorted,
    required bool canAdd,
    String? subtitle,
  }) {
    // The count is everything the agent can see in this room: what the server
    // holds plus what is still on its way there. Showing only the server's
    // number is what made a shoot look half-lost.
    final total = urls.length + queued.length;

    return Container(
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
                    onPressed: widget.enabled && !_assigning
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
                        child: ListView(
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
      onTap: widget.enabled && !_assigning ? () => _toggle(url) : null,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            child: Image.network(
              url,
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
  const _RoomChoice(this.tag);
}
