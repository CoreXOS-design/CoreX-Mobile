import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/gallery_tags.dart';
import '../../services/api_service.dart';
import '../../services/photo_telemetry.dart';
import '../../services/upload_queue.dart';
import '../../services/upload_service.dart';
import '../../theme.dart';
import '../../utils/image_processing.dart';
import '../../utils/image_upload.dart';
import 'camera_info.dart';
import 'multi_capture_camera.dart';

/// Modal bottom sheet for adding photos to a property.
///
/// On open it fetches the property's live tag list (not cached — tags change as
/// the agent edits spaces). The agent picks a room (or "No tag") and shoots;
/// each photo is stamped with the selection live at that moment and handed to
/// the durable [UploadQueue].
///
/// **This sheet does not upload.** [UploadService] does, on its own schedule,
/// whether or not this sheet is open. That split is the point: uploading used
/// to happen only while this sheet was on screen, so closing it stranded the
/// batch — silently, for as long as the agent stayed away. Everything here is
/// capture and visibility; the drain runs regardless.
class GalleryUploadSheet extends StatefulWidget {
  final int propertyId;
  final String? initialTag;

  const GalleryUploadSheet({
    super.key,
    required this.propertyId,
    this.initialTag,
  });

  /// Opens the sheet. Returns `true` if at least one photo landed on the
  /// server while it was open — the caller can use that to refresh the
  /// property detail.
  static Future<bool?> show(
    BuildContext context, {
    required int propertyId,
    String? initialTag,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.background(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => GalleryUploadSheet(
        propertyId: propertyId,
        initialTag: initialTag,
      ),
    );
  }

  @override
  State<GalleryUploadSheet> createState() => _GalleryUploadSheetState();
}

class _GalleryUploadSheetState extends State<GalleryUploadSheet> {
  final ApiService _api = ApiService();
  final ImagePicker _picker = ImagePicker();
  final UploadQueue _queue = UploadQueue.instance;
  final UploadService _uploader = UploadService.instance;

  GalleryTagsData? _tags;
  bool _loadingTags = true;
  String? _tagsError;

  // null means "No tag"
  String? _selectedTag;

  /// True while picked photos are being downscaled/orientation-baked.
  bool _preparing = false;

  /// [UploadService.successCount] when the sheet opened. Anything above it on
  /// close means the property changed and the caller should refetch — even if
  /// the upload was driven by a background tick rather than by this sheet.
  late final int _successesAtOpen;

  /// This sheet session, as one shoot. Every photo added while the sheet is
  /// open reports under it, so a batch that half-arrived can be read as a
  /// batch instead of reassembled from timestamps.
  final String _batchId =
      'shoot-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';

  /// The queue is the single source of truth for what is waiting; this sheet
  /// keeps no parallel copy that could drift from it.
  List<PendingUpload> get _items => _queue.cachedItemsFor(widget.propertyId);
  List<PendingUpload> get _waiting => _items
      .where((e) => e.state != PendingUploadState.failed)
      .toList(growable: false);
  List<PendingUpload> get _failed => _items
      .where((e) => e.state == PendingUploadState.failed)
      .toList(growable: false);

  bool get _anySuccess => _uploader.successCount > _successesAtOpen;

  @override
  void initState() {
    super.initState();
    _selectedTag = widget.initialTag;
    _successesAtOpen = _uploader.successCount;
    _queue.addListener(_onChanged);
    _uploader.addListener(_onChanged);
    _loadTags();
    _loadQueue();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowCameraInfo(context);
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

  /// Warms the durable store so [_items] stops being empty; the listener
  /// rebuilds us when it lands.
  Future<void> _loadQueue() async {
    await _queue.itemsFor(widget.propertyId);
    if (mounted) setState(() {});
  }

  /// Downscale + orientation-bake each picked photo, then add it to the durable
  /// queue. Processing runs in a background isolate so the UI stays responsive;
  /// if it fails (e.g. an undecodable format) we enqueue the original rather
  /// than drop the photo.
  ///
  /// The bake has to happen here, before the photo becomes a queue item: the
  /// server's thumbnailer drops EXIF without rotating pixels, so anything that
  /// reaches it leaning on an orientation tag lands sideways on the web.
  ///
  /// [_selectedTag] is read *here*, per photo, and then belongs to the item.
  /// This is the only moment the on-screen selection and the photo's room are
  /// the same thing.
  Future<void> _enqueueAll(List<CapturedPhoto> photos) async {
    if (photos.isEmpty) return;
    if (mounted) setState(() => _preparing = true);
    var skipped = 0;
    for (final photo in photos) {
      final prepared = await prepareForUpload(photo);
      try {
        await _queue.enqueue(
          propertyId: widget.propertyId,
          source: prepared.file,
          roomTag: _selectedTag,
          // The id the photo has carried since the shutter, so the `queued`
          // event lands on the same photo the `captured` event described.
          clientUploadId: photo.uploadId,
          batchId: _batchId,
        );
      } catch (e) {
        // Couldn't copy into durable storage (e.g. storage full). Count it so
        // we can warn the user rather than losing the photo silently.
        skipped++;
        // And say so on the record. This is the exact gap the report exists
        // for: a photo that was captured, never queued, and never seen by the
        // server. The snackbar tells the agent; this tells us which photo.
        PhotoTelemetry.instance.record(
          propertyId: widget.propertyId,
          clientUploadId: photo.uploadId,
          phase: PhotoPhase.dropped,
          batchId: _batchId,
          meta: {'reason': 'enqueue_failed', 'error': e.toString()},
        );
      } finally {
        // The queue copied it into durable storage; drop the temp file.
        try {
          if (prepared.isTemp && await prepared.file.exists()) {
            await prepared.file.delete();
          }
        } catch (_) {}
      }
      if (!mounted) return;
    }
    if (mounted) setState(() => _preparing = false);
    if (skipped > 0) {
      _showSnack(
          "Couldn't add $skipped photo${skipped == 1 ? '' : 's'} — device storage may be full");
    }
    // Start moving straight away rather than waiting for the next tick. The
    // agent is standing in the room; the sooner the count starts falling the
    // sooner they can trust it.
    unawaited(_uploader.flush());
  }

  Future<void> _loadTags() async {
    setState(() {
      _loadingTags = true;
      _tagsError = null;
    });
    try {
      final data = await _api.getGalleryTags(widget.propertyId);
      if (!mounted) return;
      setState(() {
        _tags = data;
        _loadingTags = false;
        // Drop a pre-selected tag that is no longer valid. This touches the
        // *selection only* — never the tag already stamped on a queued photo.
        if (_selectedTag != null &&
            !data.availableTags.contains(_selectedTag)) {
          _selectedTag = null;
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingTags = false;
        _tagsError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingTags = false;
        _tagsError = 'Could not load tags';
      });
    }
  }

  /// Selects the room stamped on photos added **from here on**, and nothing
  /// else.
  ///
  /// It used to also rewrite the tag on every already-queued photo whose room
  /// the property no longer offered. That was well-intentioned — a photo stuck
  /// on a dead tag can only 422 forever — but it meant a single chip tap could
  /// silently re-file a batch the agent shot twenty minutes ago, and tapping
  /// "No tag" re-filed all of them to nothing. A queued photo's room is now
  /// only ever changed one photo at a time, by name, through [_refile].
  void _selectTag(String? tag) => setState(() => _selectedTag = tag);

  /// True when [item] is queued under a tag the property no longer offers, so
  /// uploading it as-is can only 422. Surfaced on the thumbnail.
  bool _isStaleTag(PendingUpload item) {
    final data = _tags;
    if (data == null || item.roomTag == null) return false;
    return !data.availableTags.contains(item.roomTag);
  }

  /// Re-files one queued photo, by explicit choice, and kicks the queue.
  ///
  /// The escape hatch for a photo whose room has been deleted from the
  /// property: without it every attempt 422s and the only way to clear the
  /// queue is to throw the photo away.
  Future<void> _refile(PendingUpload item) async {
    final available = _tags?.availableTags ?? const <String>[];
    final chosen = await showDialog<_RefileChoice>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('File this photo under…',
            style: TextStyle(color: AppTheme.textPrimary(ctx), fontSize: 16)),
        children: [
          for (final tag in available)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, _RefileChoice(tag)),
              child: Text(tag,
                  style: TextStyle(color: AppTheme.textPrimary(ctx))),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, const _RefileChoice(null)),
            child: Text('Unsorted',
                style: TextStyle(color: AppTheme.textSecondary(ctx))),
          ),
        ],
      ),
    );
    if (chosen == null) return;
    await _queue.setRoomTag(item.id, chosen.tag);
    await _uploader.retry(item);
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await _picker.pickMultiImage(
        maxWidth: ImageUploadConfig.maxWidth,
        maxHeight: ImageUploadConfig.maxHeight,
        imageQuality: ImageUploadConfig.quality,
      );
      if (picked.isEmpty) return;
      final photos = picked.map((x) => CapturedPhoto(File(x.path))).toList();
      // "The picker returned this photo" is this path's shutter, so it is
      // reported here — ahead of the `mounted` check, which would otherwise
      // discard the whole selection without a word if the sheet closed while
      // the picker was up.
      _reportCaptured(photos);
      if (!mounted) return;
      await _enqueueAll(photos);
    } catch (_) {
      // user cancelled, ignore
    }
  }

  Future<void> _pickFromBurst() async {
    try {
      // The camera files its own `captured` events, at the shutter — the only
      // place they mean anything. It needs the property and the shoot to do
      // that; nothing else about that screen changes.
      final files = await MultiCaptureCamera.open(
        context,
        propertyId: widget.propertyId,
        batchId: _batchId,
      );
      if (files.isEmpty || !mounted) return;
      await _enqueueAll(files);
    } catch (_) {/* user cancelled, ignore */}
  }

  /// The agent throwing a queued photo away, from the pending grid or from the
  /// failed list.
  ///
  /// Reported here rather than inside [UploadQueue.remove], which is also how
  /// a photo leaves the queue after it has *landed*. Same call, opposite
  /// meanings — and a report that cannot tell "the agent deleted it" from "the
  /// server has it" is worse than no report.
  Future<void> _discard(PendingUpload item) async {
    PhotoTelemetry.instance.record(
      propertyId: item.propertyId,
      clientUploadId: item.clientUploadId,
      phase: PhotoPhase.dropped,
      batchId: item.batchId,
      meta: {
        'reason': 'discarded_by_agent',
        'attempts': item.attempts,
        if (item.error != null) 'error': item.error,
      },
    );
    await _queue.remove(item.id);
  }

  /// Files a `captured` event per photo for the `image_picker` paths, which
  /// have no shutter of their own to hook.
  void _reportCaptured(List<CapturedPhoto> photos) {
    for (final photo in photos) {
      PhotoTelemetry.instance.record(
        propertyId: widget.propertyId,
        clientUploadId: photo.uploadId,
        phase: PhotoPhase.captured,
        batchId: _batchId,
      );
    }
  }

  /// OS camera app — the only path that can reach the device's ultrawide /
  /// 0.6x on phones (e.g. Honor Y9A) where Camera2 LEGACY level hides the
  /// ultrawide from third-party apps. One shot per launch (Android/iOS
  /// constraint); we loop so the user can take many in sequence.
  Future<void> _pickFromOsCamera() async {
    try {
      while (mounted) {
        final shot = await _picker.pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.rear,
          maxWidth: ImageUploadConfig.maxWidth,
          maxHeight: ImageUploadConfig.maxHeight,
          imageQuality: ImageUploadConfig.quality,
        );
        if (shot == null) break;
        final photo = CapturedPhoto(File(shot.path));
        _reportCaptured([photo]);
        await _enqueueAll([photo]);
      }
    } catch (_) {/* user cancelled, ignore */}
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(ctx),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    children: [
                      const SizedBox(height: 8),
                      if (_loadingTags)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_tagsError != null)
                        _buildTagsError()
                      else
                        _buildTagSection(),
                      const SizedBox(height: 16),
                      _buildPickerButtons(),
                      if (_preparing) _buildPreparing(),
                      const SizedBox(height: 12),
                      if (_waiting.isNotEmpty) _buildQueueList(),
                      if (_failed.isNotEmpty) _buildFailedList(),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _buildDoneButton(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext ctx) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Add Photos',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary(context),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          color: AppTheme.textSecondary(context),
          onPressed: () => Navigator.of(ctx).pop(_anySuccess),
        ),
      ],
    );
  }

  Widget _buildTagsError() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _tagsError ?? 'Could not load tags',
              style: TextStyle(color: AppTheme.textSecondary(context)),
            ),
          ),
          TextButton(onPressed: _loadTags, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildTagSection() {
    final tags = _tags;
    if (tags == null || tags.availableTags.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'This property has no spaces yet — photos will upload to Unsorted, '
          'and you can file them into rooms later.',
          style:
              TextStyle(fontSize: 13, color: AppTheme.textSecondary(context)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Deliberately future-tense. The tag is stamped on each photo as it is
        // added, so a chip tapped after photos are already queued does NOT
        // move them — the badge on each thumbnail is what says where each one
        // is going. Labelling this "Tag this photo" invited exactly the wrong
        // order of operations: queue ten photos, pick a room, upload ten
        // untagged photos with nothing anywhere saying so.
        Text(
          'Tag for photos you add next',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary(context),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // Whatever the server lists, in the server's order. There is no
            // hard-coded room vocabulary here — the Spaces editor now offers
            // around fifty space types and the list grows without a release.
            ...tags.availableTags.map((t) => _buildTagChip(
                  label: t,
                  count: tags.tagCounts[t] ?? 0,
                  selected: _selectedTag == t,
                  onTap: () => _selectTag(t),
                )),
            _buildTagChip(
              label: 'No tag',
              count: tags.untaggedCount,
              selected: _selectedTag == null,
              onTap: () => _selectTag(null),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTagChip({
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.brand : AppTheme.surface2(context),
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppTheme.textPrimary(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Text(
                '· $count',
                style: TextStyle(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.85)
                      : AppTheme.textSecondary(context),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPickerButtons() {
    final busy = _preparing;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy ? null : _pickFromBurst,
            icon: const Icon(Icons.burst_mode, size: 18),
            label: const FittedBox(
                fit: BoxFit.scaleDown, child: Text('Multi Capture')),
            style: _pickerStyle(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy ? null : _pickFromOsCamera,
            icon: const Icon(Icons.photo_camera, size: 18),
            label:
                const FittedBox(fit: BoxFit.scaleDown, child: Text('Native')),
            style: _pickerStyle(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy ? null : _pickFromGallery,
            icon: const Icon(Icons.photo_library, size: 18),
            label:
                const FittedBox(fit: BoxFit.scaleDown, child: Text('Gallery')),
            style: _pickerStyle(),
          ),
        ),
      ],
    );
  }

  ButtonStyle _pickerStyle() => OutlinedButton.styleFrom(
        foregroundColor: AppTheme.brand,
        side: BorderSide(color: AppTheme.surface2(context)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radius)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      );

  Widget _buildQueueList() {
    final waiting = _waiting;
    final uploading = waiting.any((e) => e.state == PendingUploadState.uploading);
    final String status;
    if (uploading) {
      status = 'Uploading… ${waiting.length} to go';
    } else if (_uploader.isOffline) {
      // Never dress a queued photo up as an uploaded one. Offline means the
      // bytes are still on this phone, and the copy has to say so.
      status = '${waiting.length} waiting — no connection';
    } else {
      status = '${waiting.length} waiting to upload';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Text(
            status,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary(context)),
          ),
        ),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: waiting.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final item = waiting[i];
              final inFlight = item.state == PendingUploadState.uploading;
              final stale = _isStaleTag(item);
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    child: Image.file(item.file,
                        width: 90, height: 90, fit: BoxFit.cover),
                  ),
                  // Each photo goes up under the tag it was queued with, which
                  // is not necessarily the chip currently lit. Show it per
                  // photo, or the sheet gives no way to tell where anything is
                  // headed. Red = a tag the property no longer offers; tap to
                  // re-file that one photo.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: stale ? () => _refile(item) : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: stale
                              ? Colors.redAccent.withValues(alpha: 0.9)
                              : Colors.black54,
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(AppTheme.radius),
                            bottomRight: Radius.circular(AppTheme.radius),
                          ),
                        ),
                        child: Text(
                          stale
                              ? '${item.roomTag} — tap to re-file'
                              : (item.roomTag ?? 'Unsorted'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  if (inFlight)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(AppTheme.radius),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  if (!inFlight)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: InkWell(
                        onTap: () => _discard(item),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(2),
                          child: const Icon(Icons.close,
                              color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPreparing() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            'Preparing photos…',
            style: TextStyle(
                fontSize: 13, color: AppTheme.textSecondary(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildFailedList() {
    final failed = _failed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  "${failed.length} photo${failed.length == 1 ? '' : 's'} didn't upload",
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.redAccent),
                ),
              ),
              if (failed.length > 1)
                TextButton(
                  onPressed: () =>
                      _uploader.retryAllFor(widget.propertyId),
                  child: const Text('Retry all'),
                ),
            ],
          ),
        ),
        // The server's own message, verbatim. A rejected photo that says only
        // "failed" leaves the agent guessing at a cause the server already
        // named.
        ...failed.map(
          (f) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.surface(context),
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border:
                  Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.file(f.file,
                      width: 40, height: 40, fit: BoxFit.cover),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    f.error ?? 'Upload failed',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary(context)),
                  ),
                ),
                if (_isStaleTag(f))
                  TextButton(
                    onPressed: () => _refile(f),
                    child: const Text('Re-file'),
                  )
                else
                  TextButton(
                    onPressed: () => _uploader.retry(f),
                    child: const Text('Retry'),
                  ),
                IconButton(
                  tooltip: 'Discard',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: AppTheme.textMuted(context),
                  onPressed: () => _discard(f),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDoneButton() {
    final waiting = _waiting.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (waiting > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              // The reassurance the old flow never gave: closing this sheet is
              // safe, because nothing about the upload depends on it being open.
              'Photos keep uploading in the background — you can close this.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 12, color: AppTheme.textMuted(context)),
            ),
          ),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(_anySuccess),
            child: Text(waiting == 0 ? 'Done' : 'Done — $waiting uploading'),
          ),
        ),
      ],
    );
  }
}

/// Wrapper so a dialog can return "Unsorted" (`null`) distinctly from
/// "dismissed" (also `null` out of [showDialog]).
class _RefileChoice {
  final String? tag;
  const _RefileChoice(this.tag);
}

