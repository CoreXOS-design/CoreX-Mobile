import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/gallery_tags.dart';
import '../../services/api_service.dart';
import '../../services/upload_queue.dart';
import '../../theme.dart';
import '../../utils/image_processing.dart';
import '../../utils/image_upload.dart';
import 'camera_info.dart';
import 'multi_capture_camera.dart';

/// Modal bottom sheet for uploading one or more photos to a property.
///
/// On open it fetches the property's live tag list (not cached — tags change
/// as the agent edits spaces). Users pick a tag (or "No tag"), queue up
/// images from camera or gallery, then tap Upload which posts each image
/// sequentially. If the server rejects a tag (422) the sheet refreshes its
/// local tag list from the response and prompts the user to re-select.
class GalleryUploadSheet extends StatefulWidget {
  final int propertyId;
  final String? initialTag;

  const GalleryUploadSheet({
    super.key,
    required this.propertyId,
    this.initialTag,
  });

  /// Opens the sheet. Returns `true` if at least one image was uploaded
  /// successfully — the caller can use that to refresh the property detail.
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

  GalleryTagsData? _tags;
  bool _loadingTags = true;
  String? _tagsError;

  // null means "No tag"
  String? _selectedTag;

  /// All durable queue items for this property — both pending and failed.
  /// Backed by [UploadQueue] so nothing is lost when the sheet closes.
  final List<PendingUpload> _items = [];

  /// Up to this many uploads run at once — bounded so we never fire the whole
  /// batch at the server (or the radio) simultaneously.
  static const int _maxConcurrent = 3;

  /// Attempts per photo before it is marked failed (1 initial + retries).
  static const int _maxAttempts = 3;

  /// Ids currently mid-request, for the per-photo spinner.
  final Set<String> _inFlight = {};

  /// Set when a stale-tag 422 aborts the run so the summary is suppressed.
  bool _cancelBatch = false;

  /// Photos the server filed under something other than the tag we sent, as
  /// "sent → filed" strings. Populated from the 201 body, reset per batch.
  final List<String> _tagMismatches = [];

  /// True while picked photos are being downscaled/orientation-baked.
  bool _preparing = false;

  final Random _rng = Random();

  bool _uploading = false;
  int _uploadedCount = 0;
  int _targetCount = 0;
  bool _anySuccess = false;

  List<PendingUpload> get _pending =>
      _items.where((e) => e.state == PendingUploadState.pending).toList();
  List<PendingUpload> get _failed =>
      _items.where((e) => e.state == PendingUploadState.failed).toList();

  @override
  void initState() {
    super.initState();
    _selectedTag = widget.initialTag;
    _loadTags();
    _loadQueue();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowCameraInfo(context);
    });
  }

  /// Restore any photos left over from a previous session (sheet closed or app
  /// killed mid-upload) so the user can finish the batch.
  Future<void> _loadQueue() async {
    final items = await UploadQueue.instance.itemsFor(widget.propertyId);
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(items);
    });
  }

  /// Downscale + orientation-bake each picked photo, then add it to the durable
  /// queue. Processing runs in a background isolate so the UI stays responsive;
  /// if it fails (e.g. an undecodable format) we enqueue the original rather
  /// than drop the photo.
  ///
  /// The bake has to happen here, before the photo becomes a queue item: the
  /// server's thumbnailer drops EXIF without rotating pixels, so anything that
  /// reaches it leaning on an orientation tag lands sideways on the web.
  Future<void> _enqueueAll(List<CapturedPhoto> photos) async {
    if (photos.isEmpty) return;
    if (mounted) setState(() => _preparing = true);
    var skipped = 0;
    for (final photo in photos) {
      final prepared = await prepareForUpload(photo);
      try {
        final item = await UploadQueue.instance.enqueue(
          propertyId: widget.propertyId,
          source: prepared.file,
          roomTag: _selectedTag,
        );
        if (mounted) setState(() => _items.add(item));
      } catch (_) {
        // Couldn't copy into durable storage (e.g. storage full). Count it so
        // we can warn the user rather than losing the photo silently.
        skipped++;
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
        // Drop a pre-selected tag that is no longer valid
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

  /// Selects the tag stamped on photos added from here on, and re-tags any
  /// already-queued photo whose stored tag the property no longer offers.
  ///
  /// The re-tag half is what makes the stale-tag prompt actionable. A photo
  /// carries the tag it was queued under (see [_enqueueAll]) and nothing at
  /// drain time may overwrite it, or a chip selection that moves as the agent
  /// works through the house files older photos in the wrong room. But when the
  /// server rejects a tag as no longer on the property, that photo's stored tag
  /// is unusable: every retry re-sends it, 422s again, and re-prompts — a loop
  /// with no exit but deleting the photo, because nothing else in the sheet
  /// writes [PendingUpload.roomTag] after enqueue.
  ///
  /// Re-tagging exactly the photos whose tag is gone breaks that loop and
  /// cannot disturb a photo that is correctly filed.
  Future<void> _selectTag(String? tag) async {
    setState(() => _selectedTag = tag);
    // Not loaded yet = no basis to call anything stale. A loaded-but-EMPTY list
    // is different: it means the property has lost every space, so every tagged
    // photo in the queue really is unfilable and needs moving to Unsorted.
    final data = _tags;
    if (data == null) return;
    final available = data.availableTags;
    // Never re-tag a photo mid-request: [_uploadOne] captured its tag before
    // the attempt, so changing it here would leave the queue item disagreeing
    // with what is actually on the wire.
    final stale = _items
        .where((e) =>
            e.roomTag != null &&
            !available.contains(e.roomTag) &&
            !_inFlight.contains(e.id))
        .toList();
    if (stale.isEmpty) return;
    for (final item in stale) {
      item.roomTag = tag;
      await UploadQueue.instance.setRoomTag(item.id, tag);
    }
    if (mounted) setState(() {});
  }

  /// True when [item] is queued under a tag the property no longer offers, so
  /// uploading it as-is can only 422. Surfaced on the thumbnail.
  bool _isStaleTag(PendingUpload item) {
    final data = _tags;
    if (data == null || item.roomTag == null) return false;
    return !data.availableTags.contains(item.roomTag);
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await _picker.pickMultiImage(
        maxWidth: ImageUploadConfig.maxWidth,
        maxHeight: ImageUploadConfig.maxHeight,
        imageQuality: ImageUploadConfig.quality,
      );
      if (picked.isEmpty || !mounted) return;
      await _enqueueAll(
          picked.map((x) => CapturedPhoto(File(x.path))).toList());
    } catch (_) {
      // user cancelled, ignore
    }
  }

  Future<void> _pickFromBurst() async {
    try {
      final files = await MultiCaptureCamera.open(context);
      if (files.isEmpty || !mounted) return;
      await _enqueueAll(files);
    } catch (_) {/* user cancelled, ignore */}
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
        await _enqueueAll([CapturedPhoto(File(shot.path))]);
      }
    } catch (_) {/* user cancelled, ignore */}
  }

  Future<void> _upload() async {
    if (_uploading) return;
    final pending = _pending;
    if (pending.isEmpty) return;
    await _runBatch(pending);
  }

  /// Upload [items] through a bounded worker pool with per-photo retry. A photo
  /// leaves the queue only on a confirmed 2xx; everything else is retried or
  /// marked failed so nothing is dropped silently.
  Future<void> _runBatch(List<PendingUpload> items) async {
    if (items.isEmpty) return;
    setState(() {
      _uploading = true;
      _cancelBatch = false;
      _uploadedCount = 0;
      _targetCount = items.length;
      _tagMismatches.clear();
    });

    final queue = List<PendingUpload>.from(items);
    var next = 0;

    // The event loop is single-threaded, so reading and bumping [next] between
    // awaits is race-free — no two workers grab the same index.
    Future<void> worker() async {
      while (!_cancelBatch && next < queue.length) {
        final item = queue[next++];
        await _uploadOne(item);
      }
    }

    final workers = _maxConcurrent < queue.length ? _maxConcurrent : queue.length;
    await Future.wait(List.generate(workers, (_) => worker()));

    if (!mounted) return;
    setState(() => _uploading = false);
    _announceBatchResult();
  }

  /// Uploads a single photo with up to [_maxAttempts] tries and exponential
  /// backoff. Retries network errors, timeouts and transient non-2xx; treats
  /// 403/413 (and a stale-tag 422) as terminal.
  Future<void> _uploadOne(PendingUpload item) async {
    // The tag is whatever was selected when THIS photo was queued
    // (see [_enqueueAll]). Nothing at drain time may overwrite it: the chip
    // selection moves as the agent works through the house, and stamping the
    // current selection onto an older photo files it under the wrong room —
    // or, when the selection has been cleared, under no room at all.
    final String? sentTag = item.roomTag;
    if (mounted) setState(() => _inFlight.add(item.id));
    try {
      for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
        if (_cancelBatch) return;
        try {
          // Retries re-send the same [sentTag], so a retry can never land the
          // photo under a different room than the first attempt.
          final result = await _api.uploadPropertyImage(
              widget.propertyId, item.file, sentTag,
              clientId: item.id);
          // The 201 reports the tag the server ACTUALLY filed the photo under
          // (null = unsorted). That is the only authoritative answer, so check
          // it rather than assuming the request was honoured.
          _verifyFiledTag(sent: sentTag, result: result);
          await UploadQueue.instance.remove(item.id);
          if (!mounted) return;
          setState(() {
            _items.remove(item);
            _uploadedCount++;
            _anySuccess = true;
          });
          return;
        } on TagValidationException catch (e) {
          // Stale tag — retrying won't help. Keep the photo queued, stop the
          // whole batch, and prompt a re-select.
          await UploadQueue.instance.markPending(item.id);
          _cancelBatch = true;
          if (!mounted) return;
          setState(() {
            _tags = (_tags ?? GalleryTagsData.empty(widget.propertyId))
                .withAvailable(e.availableTags);
            _selectedTag = null;
          });
          _showSnack('Some tags are no longer available — pick a tag to '
              're-file those photos');
          return;
        } on ApiException catch (e) {
          // A 422 reaching here is a validation failure on the FILE — a tag 422
          // arrives as TagValidationException and is caught above. The same
          // bytes cannot become valid on a second attempt, so retrying only
          // delays the failure and burns the user's uplink three times over.
          final terminal = e.statusCode == 403 ||
              e.statusCode == 413 ||
              e.statusCode == 422;
          if (terminal || attempt >= _maxAttempts) {
            await UploadQueue.instance.markFailed(item.id, e.message);
            if (mounted) setState(() {});
            return;
          }
          await _backoff(attempt);
        } catch (e) {
          // Network error / socket drop — retry unless we're out of attempts.
          if (attempt >= _maxAttempts) {
            await UploadQueue.instance
                .markFailed(item.id, 'Upload failed — check your connection');
            if (mounted) setState(() {});
            return;
          }
          await _backoff(attempt);
        }
      }
    } finally {
      _inFlight.remove(item.id);
      if (mounted) setState(() {});
    }
  }

  /// Compares the tag we posted against the tag the server says it filed the
  /// photo under, from the 201 body.
  ///
  /// The server matches case- and whitespace-insensitively and stores the
  /// library's canonical casing, so "bedroom 2" coming back as "Bedroom 2" is
  /// a match, not a drift. Anything else means the photo is not where the
  /// agent put it — most importantly `filed == null`, which is the server
  /// saying "unsorted" no matter what the UI showed.
  ///
  /// Two responses carry no usable answer and must be sat out rather than read
  /// as "unsorted", or a correctly-filed photo gets reported as misfiled:
  ///
  ///  * a dedupe hit ([UploadedImage.duplicate]) — the server's fast path
  ///    answers `room_tag: null` whatever the photo was really filed under, and
  ///    that is the shape EVERY retried upload takes, so this would have cried
  ///    wolf on exactly the batches that had a rough time on the network;
  ///  * an unparseable body (empty [UploadedImage.url]) — we know nothing.
  void _verifyFiledTag(
      {required String? sent, required UploadedImage result}) {
    if (result.duplicate || result.url.isEmpty) return;
    final filed = result.roomTag;
    String norm(String? s) => (s ?? '').trim().toLowerCase();
    if (norm(sent) == norm(filed)) return;
    _tagMismatches.add(
      '${sent ?? "no tag"} → ${filed ?? "Unsorted"}',
    );
    debugPrint('Upload tag mismatch: sent room_tag=${sent ?? "(omitted)"} '
        'but server filed it under ${filed ?? "(unsorted)"}');
  }

  /// Exponential backoff (~1s, 2s, 4s) with jitter to avoid a retry stampede.
  Future<void> _backoff(int attempt) async {
    final base = 1000 * (1 << (attempt - 1));
    await Future.delayed(Duration(milliseconds: base + _rng.nextInt(500)));
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _announceBatchResult() {
    if (_cancelBatch) return; // the re-select prompt was already shown
    final failed = _failed.length;
    final pending = _pending.length;
    // A photo the server filed somewhere else is on the server but in the
    // wrong place — the upload "succeeded", so nothing else here would say so.
    // Folded into the success line rather than shown as a second snack: two
    // queued snacks make the user wait out a "3 photos uploaded" to read the
    // warning, and the warning is the half worth acting on.
    final n = _tagMismatches.length;
    final mismatch = n == 0
        ? null
        : n == 1
            ? 'filed as ${_tagMismatches.first.split(' → ').last} — check the gallery'
            : '$n filed under a different room — check the gallery';
    if (failed == 0 && pending == 0 && _uploadedCount > 0) {
      final uploaded =
          '$_uploadedCount photo${_uploadedCount == 1 ? '' : 's'} uploaded';
      _showSnack(mismatch == null ? uploaded : '$uploaded, $mismatch');
      Navigator.of(context).pop(true);
    } else if (mismatch != null) {
      _showSnack('Some photos were $mismatch');
    }
    if (failed > 0) {
      _showSnack(
          "$failed photo${failed == 1 ? '' : 's'} didn't upload — tap Retry below");
    }
  }

  Future<void> _retryFailed(PendingUpload item) async {
    if (_uploading) return;
    setState(() {
      item.state = PendingUploadState.pending;
      item.error = null;
    });
    await UploadQueue.instance.markPending(item.id);
    await _runBatch([item]);
  }

  Future<void> _retryAllFailed() async {
    if (_uploading) return;
    final failed = _failed;
    if (failed.isEmpty) return;
    for (final item in failed) {
      item.state = PendingUploadState.pending;
      item.error = null;
      await UploadQueue.instance.markPending(item.id);
    }
    if (!mounted) return;
    setState(() {});
    await _runBatch(_pending);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, _) {
            // Result already returned via explicit pops; nothing to do here.
          },
          child: Padding(
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
                      if (_pending.isNotEmpty) _buildQueueList(),
                      if (_failed.isNotEmpty) _buildFailedList(),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _buildUploadButton(),
              ],
              ),
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
            'Upload Photos',
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
      // No spaces → nothing to pick between. Still offer the "No tag" chip if
      // anything queued is carrying a tag the property no longer has: that
      // photo can only 422, and without a chip to tap there is no way to
      // re-file it and no way to finish the batch but deleting it.
      final stranded = _items.any(_isStaleTag);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stranded
                  ? 'This property has no spaces left — move these photos to '
                      'Unsorted to upload them.'
                  : 'This property has no spaces yet — photos will upload to Unsorted.',
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary(context)),
            ),
            if (stranded) ...[
              const SizedBox(height: 8),
              _buildTagChip(
                label: 'Move to Unsorted',
                // No count: the chip is an action here, not a destination, and
                // "Move to Unsorted · 12" reads as a quantity being moved.
                count: 0,
                selected: false,
                onTap: () => _selectTag(null),
              ),
            ],
          ],
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
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: (_uploading || _preparing) ? null : _pickFromBurst,
            icon: const Icon(Icons.burst_mode, size: 18),
            label: const FittedBox(
                fit: BoxFit.scaleDown, child: Text('Multi Capture')),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.brand,
              side: BorderSide(color: AppTheme.surface2(context)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius)),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: (_uploading || _preparing) ? null : _pickFromOsCamera,
            icon: const Icon(Icons.photo_camera, size: 18),
            label: const FittedBox(
                fit: BoxFit.scaleDown, child: Text('Native')),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.brand,
              side: BorderSide(color: AppTheme.surface2(context)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius)),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: (_uploading || _preparing) ? null : _pickFromGallery,
            icon: const Icon(Icons.photo_library, size: 18),
            label: const FittedBox(
                fit: BoxFit.scaleDown, child: Text('Gallery')),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.brand,
              side: BorderSide(color: AppTheme.surface2(context)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius)),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQueueList() {
    final pending = _pending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Text(
            _uploading
                ? 'Uploaded $_uploadedCount of $_targetCount…'
                : '${pending.length} selected',
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
            itemCount: pending.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final item = pending[i];
              final inFlight = _inFlight.contains(item.id);
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
                  // headed. Red = a tag the property no longer offers; tap any
                  // chip to re-file those.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
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
                        item.roomTag ?? 'Unsorted',
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
                  if (!_uploading)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: InkWell(
                        onTap: () async {
                          await UploadQueue.instance.remove(item.id);
                          if (!mounted) return;
                          setState(() => _items.remove(item));
                        },
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  "${_failed.length} photo${_failed.length == 1 ? '' : 's'} didn't upload — tap to retry",
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.redAccent),
                ),
              ),
              if (!_uploading && _failed.length > 1)
                TextButton(
                  onPressed: _retryAllFailed,
                  child: const Text('Retry all'),
                ),
            ],
          ),
        ),
        ..._failed.map(
          (f) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.surface(context),
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
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
                        fontSize: 12,
                        color: AppTheme.textSecondary(context)),
                  ),
                ),
                TextButton(
                  onPressed: _uploading ? null : () => _retryFailed(f),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUploadButton() {
    final count = _pending.length;
    final canUpload = !_uploading && !_preparing && count > 0;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: canUpload ? _upload : null,
        child: _uploading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(count == 0
                ? 'Upload'
                : 'Upload $count photo${count == 1 ? '' : 's'}'),
      ),
    );
  }
}
