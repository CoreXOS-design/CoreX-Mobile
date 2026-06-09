import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/gallery_tags.dart';
import '../../services/api_service.dart';
import '../../theme.dart';
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
      backgroundColor: AppTheme.darkBackground,
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

class _GalleryInfoDialog extends StatefulWidget {
  const _GalleryInfoDialog();

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _GalleryInfoDialog(),
    );
  }

  @override
  State<_GalleryInfoDialog> createState() => _GalleryInfoDialogState();
}

class _GalleryInfoDialogState extends State<_GalleryInfoDialog> {
  static const int _lockSeconds = 5;
  int _remaining = _lockSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canClose = _remaining <= 0;
    return PopScope(
      canPop: canClose,
      child: AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: AppTheme.brand),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'How photo upload works',
                style: TextStyle(
                  color: AppTheme.textPrimary(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _section(
                context,
                icon: Icons.burst_mode,
                title: 'Burst',
                body:
                    'In-app rapid camera. Take many photos in a row, then review and confirm them all at once. On some devices the ultrawide (0.6x) lens is hidden from third-party apps and won\'t appear here — use Native if you need it.',
              ),
              const SizedBox(height: 12),
              _section(
                context,
                icon: Icons.photo_camera,
                title: 'Native',
                body:
                    'Opens your phone\'s built-in camera app. Full access to every lens (including 0.6x) but only one photo per launch — we re-open it automatically after each shot until you back out.',
              ),
              const SizedBox(height: 12),
              _section(
                context,
                icon: Icons.photo_library,
                title: 'Gallery',
                body:
                    'Pick existing photos from your phone. You can select multiple at once.',
              ),
              const SizedBox(height: 12),
              _section(
                context,
                icon: Icons.label_outline,
                title: 'Tags',
                body:
                    'Pick a tag (room/space) before uploading so the photo is filed correctly. "No tag" sends them to Unsorted — you can re-tag later.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: canClose ? () => Navigator.of(context).pop() : null,
            child: Text(canClose ? 'Got it' : 'Got it (${_remaining}s)'),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context,
      {required IconData icon,
      required String title,
      required String body}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppTheme.brand),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary(context),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FailedUpload {
  final File file;
  final String error;
  _FailedUpload({required this.file, required this.error});
}

class _GalleryUploadSheetState extends State<GalleryUploadSheet> {
  final ApiService _api = ApiService();
  final ImagePicker _picker = ImagePicker();

  GalleryTagsData? _tags;
  bool _loadingTags = true;
  String? _tagsError;

  // null means "No tag"
  String? _selectedTag;

  final List<File> _queue = [];
  final List<_FailedUpload> _failed = [];

  bool _uploading = false;
  int _uploadedCount = 0;
  int _targetCount = 0;
  bool _anySuccess = false;

  static const String _kSeenInfoPrefKey = 'gallery_upload_info_seen_v1';

  @override
  void initState() {
    super.initState();
    _selectedTag = widget.initialTag;
    _loadTags();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowFirstRunInfo());
  }

  Future<void> _maybeShowFirstRunInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kSeenInfoPrefKey) == true) return;
      if (!mounted) return;
      await _GalleryInfoDialog.show(context);
      await prefs.setBool(_kSeenInfoPrefKey, true);
    } catch (_) {/* ignore */}
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

  Future<void> _pickFromGallery() async {
    try {
      final picked = await _picker.pickMultiImage();
      if (picked.isEmpty || !mounted) return;
      setState(() {
        _queue.addAll(picked.map((x) => File(x.path)));
      });
    } catch (_) {
      // user cancelled, ignore
    }
  }

  Future<void> _pickFromBurst() async {
    try {
      final files = await MultiCaptureCamera.open(context);
      if (files.isEmpty || !mounted) return;
      setState(() => _queue.addAll(files));
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
        );
        if (shot == null) break;
        setState(() => _queue.add(File(shot.path)));
      }
    } catch (_) {/* user cancelled, ignore */}
  }

  Future<void> _upload() async {
    if (_queue.isEmpty || _uploading) return;

    setState(() {
      _uploading = true;
      _uploadedCount = 0;
      _targetCount = _queue.length;
    });

    final toUpload = List<File>.from(_queue);
    for (final file in toUpload) {
      try {
        await _api.uploadPropertyImage(
            widget.propertyId, file, _selectedTag);
        if (!mounted) return;
        setState(() {
          _queue.remove(file);
          _uploadedCount++;
          _anySuccess = true;
        });
      } on TagValidationException catch (e) {
        if (!mounted) return;
        // The tag we were using is no longer valid. Refresh the local list
        // from the response, drop the selection, and stop the queue.
        setState(() {
          _uploading = false;
          _tags = (_tags ?? GalleryTagsData.empty(widget.propertyId))
              .withAvailable(e.availableTags);
          _selectedTag = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Some tags are no longer available — please re-select'),
          ),
        );
        return;
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() {
          _queue.remove(file);
          _failed.add(_FailedUpload(file: file, error: e.message));
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _queue.remove(file);
          _failed.add(_FailedUpload(file: file, error: e.toString()));
        });
      }
    }

    if (!mounted) return;
    setState(() => _uploading = false);

    if (_failed.isEmpty && _uploadedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '$_uploadedCount photo${_uploadedCount == 1 ? '' : 's'} uploaded')),
      );
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _retryFailed(_FailedUpload failed) async {
    setState(() => _failed.remove(failed));
    try {
      await _api.uploadPropertyImage(
          widget.propertyId, failed.file, _selectedTag);
      if (!mounted) return;
      setState(() => _anySuccess = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uploaded')),
      );
    } on TagValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _tags = (_tags ?? GalleryTagsData.empty(widget.propertyId))
            .withAvailable(e.availableTags);
        _selectedTag = null;
        _failed.add(failed);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Some tags are no longer available — please re-select')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _failed.add(
          _FailedUpload(file: failed.file, error: e.toString())));
    }
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
                      const SizedBox(height: 12),
                      if (_queue.isNotEmpty) _buildQueueList(),
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
      // No spaces yet → don't offer any tag picker. Uploads will be untagged.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'This property has no spaces yet — photos will upload to Unsorted.',
          style: TextStyle(
              fontSize: 13, color: AppTheme.textSecondary(context)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tag this photo',
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
                  onTap: () => setState(() => _selectedTag = t),
                )),
            _buildTagChip(
              label: 'No tag',
              count: tags.untaggedCount,
              selected: _selectedTag == null,
              onTap: () => setState(() => _selectedTag = null),
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
          color: selected ? AppTheme.brand : AppTheme.darkSurface2,
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
            onPressed: _uploading ? null : _pickFromBurst,
            icon: const Icon(Icons.burst_mode, size: 18),
            label: const Text('Burst'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.brand,
              side: const BorderSide(color: AppTheme.darkSurface2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _uploading ? null : _pickFromOsCamera,
            icon: const Icon(Icons.photo_camera, size: 18),
            label: const Text('Native'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.brand,
              side: const BorderSide(color: AppTheme.darkSurface2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _uploading ? null : _pickFromGallery,
            icon: const Icon(Icons.photo_library, size: 18),
            label: const Text('Gallery'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.brand,
              side: const BorderSide(color: AppTheme.darkSurface2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQueueList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Text(
            _uploading
                ? 'Uploading ${_uploadedCount + 1} of $_targetCount…'
                : '${_queue.length} selected',
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
            itemCount: _queue.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final file = _queue[i];
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    child: Image.file(file,
                        width: 90, height: 90, fit: BoxFit.cover),
                  ),
                  if (!_uploading)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: InkWell(
                        onTap: () => setState(() => _queue.removeAt(i)),
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

  Widget _buildFailedList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(
            'Failed (${_failed.length}) — tap to retry',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.redAccent),
          ),
        ),
        ..._failed.map(
          (f) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
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
                    f.error,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context)),
                  ),
                ),
                TextButton(
                  onPressed: () => _retryFailed(f),
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
    final canUpload = !_uploading && _queue.isNotEmpty;
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
            : Text(_queue.isEmpty
                ? 'Upload'
                : 'Upload ${_queue.length} photo${_queue.length == 1 ? '' : 's'}'),
      ),
    );
  }
}
