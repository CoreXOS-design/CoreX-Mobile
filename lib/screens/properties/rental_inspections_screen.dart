import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../widgets/ui/content_width.dart';
import '../../models/rental_inspections.dart';
import '../../services/api_service.dart';
import '../../theme.dart';
import '../../utils/image_processing.dart';
import '../../utils/image_upload.dart';
import 'camera_info.dart';
import 'multi_capture_camera.dart';

/// The three photo-capture modes, mirroring the property gallery upload.
enum _PhotoSource { multiCapture, native, gallery }

/// Rental inspection galleries for a property. Shown only for rental listings
/// that are live on the market (gated upstream on
/// `rental_inspections_available`).
///
/// Three section types: In Inspection, Out Inspection (fixed), then each
/// custom section. Sections are collapsible cards, all collapsed by default.
/// The backend is the source of truth: every mutating call returns the full
/// structure and the screen re-renders from it — nothing is appended locally.
class RentalInspectionsScreen extends StatefulWidget {
  final int propertyId;
  final String? propertyTitle;
  final ApiService? api;

  const RentalInspectionsScreen({
    super.key,
    required this.propertyId,
    this.propertyTitle,
    this.api,
  });

  @override
  State<RentalInspectionsScreen> createState() =>
      _RentalInspectionsScreenState();
}

class _RentalInspectionsScreenState extends State<RentalInspectionsScreen> {
  late final ApiService _api = widget.api ?? ApiService();
  final ImagePicker _picker = ImagePicker();

  RentalInspections? _data;
  bool _loading = true;
  String? _error;
  bool _forbidden = false;
  bool _notEligible = false;

  /// A blocking overlay message while a mutating call is in flight (upload,
  /// save, delete). Null when idle.
  String? _busyMessage;

  /// Stable keys of the currently-expanded sections, preserved across the
  /// data refreshes that every mutation triggers.
  final Set<String> _expanded = {};

  String _sectionKey(RentalSection s) =>
      s.isCustom ? 'custom:${s.customId}' : s.type.apiValue;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final data = await _api.getRentalInspections(widget.propertyId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } on RentalNotEligibleException {
      if (!mounted) return;
      setState(() {
        _notEligible = true;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.statusCode == 403) _forbidden = true;
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Runs a mutating call that returns the full structure, showing a blocking
  /// overlay and folding the typed failure modes into the right UI state.
  Future<void> _mutate(
    String busyMessage,
    Future<RentalInspections> Function() action,
  ) async {
    setState(() => _busyMessage = busyMessage);
    try {
      final data = await action();
      if (!mounted) return;
      setState(() {
        _data = data;
        _busyMessage = null;
      });
    } on RentalNotEligibleException {
      if (!mounted) return;
      setState(() {
        _notEligible = true;
        _busyMessage = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busyMessage = null);
      if (e.statusCode == 404) {
        // A custom section id went stale — re-fetch the truth.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That section changed — refreshing…')),
        );
        await _load();
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyMessage = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Something went wrong: $e')));
    }
  }

  // --- Actions -----------------------------------------------------------

  Future<void> _editDate(RentalSection s) async {
    final initial = _parseDate(s.date) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    await _mutate(
      'Saving date…',
      () => _api.setRentalDate(
        widget.propertyId,
        s.type,
        _formatIso(picked),
        customId: s.customId,
      ),
    );
  }

  Future<void> _clearDate(RentalSection s) async {
    await _mutate(
      'Clearing date…',
      () => _api.setRentalDate(widget.propertyId, s.type, null,
          customId: s.customId),
    );
  }

  Future<void> _addPhotos(RentalSection s) async {
    // Explain the capture modes once, ever, before the first camera use.
    await maybeShowCameraInfo(context);
    if (!mounted) return;
    final photos = await _pickImages();
    if (photos.isEmpty || !mounted) return;

    // Downscale + bake orientation into the pixels before upload, exactly as
    // the property gallery does. This is the only defence, not a precaution:
    // in-app captures arrive in a landscape buffer with no EXIF `Orientation`,
    // and the server's normaliser has nothing to distinguish those from real
    // landscape photos, so it leaves them alone. Skip this and the inspection
    // gallery renders them on their side.
    final prepared = <PreparedPhoto>[];
    for (final photo in photos) {
      prepared.add(await prepareForUpload(photo));
      if (!mounted) return;
    }

    try {
      await _mutate(
        'Uploading ${prepared.length} photo${prepared.length == 1 ? '' : 's'}…',
        () => _api.uploadRentalImages(
          widget.propertyId,
          s.type,
          prepared.map((p) => p.file).toList(),
          customId: s.customId,
        ),
      );
    } finally {
      for (final p in prepared) {
        if (!p.isTemp) continue;
        try {
          if (await p.file.exists()) await p.file.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _deletePhoto(RentalSection s, int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface(context),
        title: const Text('Delete photo'),
        content: const Text('Remove this photo? This can\'t be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _mutate(
      'Deleting…',
      () => _api.deleteRentalImage(widget.propertyId, s.type, index,
          customId: s.customId),
    );
  }

  Future<void> _addSection() async {
    final name = await _SectionNameDialog.show(context, title: 'Add section');
    if (name == null || name.isEmpty || !mounted) return;
    await _mutate(
      'Adding section…',
      () => _api.addRentalSection(widget.propertyId, name),
    );
  }

  Future<void> _renameSection(RentalSection s) async {
    if (s.customId == null) return;
    final name = await _SectionNameDialog.show(context,
        title: 'Rename section', initial: s.name);
    if (name == null || name.isEmpty || !mounted) return;
    await _mutate(
      'Renaming…',
      () => _api.renameRentalSection(widget.propertyId, s.customId!, name),
    );
  }

  /// Photo picker offering the same three capture modes as the property
  /// gallery upload — Multi Capture (in-app burst), Native (OS camera, one
  /// shot per launch, looped), and Gallery. Returns the selected files
  /// (possibly empty). Multi Capture photos carry the capture-time sensor
  /// orientation; the two `image_picker` modes can't, so they rely on the
  /// file's own EXIF tag.
  Future<List<CapturedPhoto>> _pickImages() async {
    final source = await showModalBottomSheet<_PhotoSource>(
      context: context,
      backgroundColor: AppTheme.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.burst_mode, color: AppTheme.brand),
              title: const Text('Multi Capture'),
              subtitle: const Text('In-app rapid camera (may not work on some devices)'),
              onTap: () => Navigator.of(ctx).pop(_PhotoSource.multiCapture),
            ),
            ListTile(
              leading: Icon(Icons.photo_camera, color: AppTheme.brand),
              title: const Text('Native'),
              subtitle: const Text('Your phone\'s camera app'),
              onTap: () => Navigator.of(ctx).pop(_PhotoSource.native),
            ),
            ListTile(
              leading: Icon(Icons.photo_library, color: AppTheme.brand),
              title: const Text('Gallery'),
              subtitle: const Text('Pick existing photos'),
              onTap: () => Navigator.of(ctx).pop(_PhotoSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return const [];
    try {
      switch (source) {
        case _PhotoSource.multiCapture:
          return await MultiCaptureCamera.open(context);
        case _PhotoSource.gallery:
          final picked = await _picker.pickMultiImage(
            maxWidth: ImageUploadConfig.maxWidth,
            maxHeight: ImageUploadConfig.maxHeight,
            imageQuality: ImageUploadConfig.quality,
          );
          return picked.map((x) => CapturedPhoto(File(x.path))).toList();
        case _PhotoSource.native:
          // OS camera takes one shot per launch; loop so the user can take
          // several in a row, matching the gallery upload behaviour.
          final files = <CapturedPhoto>[];
          while (mounted) {
            final shot = await _picker.pickImage(
              source: ImageSource.camera,
              preferredCameraDevice: CameraDevice.rear,
              maxWidth: ImageUploadConfig.maxWidth,
              maxHeight: ImageUploadConfig.maxHeight,
              imageQuality: ImageUploadConfig.quality,
            );
            if (shot == null) break;
            files.add(CapturedPhoto(File(shot.path)));
          }
          return files;
      }
    } catch (_) {
      return const [];
    }
  }

  void _openViewer(RentalSection s, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenImageViewer(
          images: s.images,
          initialIndex: index,
          title: s.name,
        ),
      ),
    );
  }

  // --- Build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rental Inspections'),
      ),
      body: ContentSafeArea(
        top: false,
        child: Stack(
          children: [
            _buildContent(),
            if (_busyMessage != null) _busyOverlay(_busyMessage!),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_notEligible) {
      return const _MessageState(
        icon: Icons.info_outline,
        title: 'Not available',
        message:
            'Rental inspections aren\'t available for this property anymore.',
      );
    }
    if (_forbidden) {
      return _MessageState(
        icon: Icons.lock_outline,
        title: 'You don\'t have access',
        message: _error ?? 'This property is outside your visibility scope.',
      );
    }
    if (_error != null) {
      return _MessageState(
        icon: Icons.error_outline,
        title: 'Couldn\'t load inspections',
        message: _error!,
        onRetry: _load,
      );
    }

    final data = _data!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          if ((widget.propertyTitle ?? '').isNotEmpty) ...[
            Text(
              widget.propertyTitle!,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary(context),
              ),
            ),
            const SizedBox(height: 12),
          ],
          for (final s in data.sections) ...[
            _SectionCard(
              section: s,
              expanded: _expanded.contains(_sectionKey(s)),
              onToggle: () => setState(() {
                final k = _sectionKey(s);
                _expanded.contains(k) ? _expanded.remove(k) : _expanded.add(k);
              }),
              onEditDate: () => _editDate(s),
              onClearDate: () => _clearDate(s),
              onAddPhotos: () => _addPhotos(s),
              onRename: s.isCustom ? () => _renameSection(s) : null,
              onTapImage: (i) => _openViewer(s, i),
              onDeleteImage: (i) => _deletePhoto(s, i),
              dateLabel: _formatDisplay,
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: _addSection,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add section'),
          ),
        ],
      ),
    );
  }

  Widget _busyOverlay(String message) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: AppTheme.surface(context),
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 14),
                Text(
                  message,
                  style: TextStyle(
                    color: AppTheme.textPrimary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Date helpers ------------------------------------------------------

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  DateTime? _parseDate(String? iso) =>
      iso == null ? null : DateTime.tryParse(iso);

  String _formatIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _formatDisplay(String? iso) {
    final d = _parseDate(iso);
    if (d == null) return 'No date set';
    return '${d.day} ${_months[d.month - 1]} ${d.year}';
  }
}

/// One collapsible gallery card. Collapsed by default; the parent owns the
/// expand state so it survives the data refreshes every mutation triggers.
class _SectionCard extends StatelessWidget {
  final RentalSection section;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onEditDate;
  final VoidCallback onClearDate;
  final VoidCallback onAddPhotos;
  final VoidCallback? onRename;
  final void Function(int index) onTapImage;
  final void Function(int index) onDeleteImage;
  final String Function(String? iso) dateLabel;

  const _SectionCard({
    required this.section,
    required this.expanded,
    required this.onToggle,
    required this.onEditDate,
    required this.onClearDate,
    required this.onAddPhotos,
    required this.onRename,
    required this.onTapImage,
    required this.onDeleteImage,
    required this.dateLabel,
  });

  @override
  Widget build(BuildContext context) {
    final count = section.images.length;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — tap to expand/collapse.
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(
                    section.isCustom
                        ? Icons.folder_outlined
                        : Icons.fact_check_outlined,
                    color: AppTheme.brand,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          section.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${dateLabel(section.date)} · $count photo${count == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onRename != null)
                    IconButton(
                      tooltip: 'Rename',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.edit_outlined,
                          size: 18, color: AppTheme.textMuted(context)),
                      onPressed: onRename,
                    ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppTheme.textMuted(context),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            Divider(height: 1, color: AppTheme.borderColor(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _dateRow(context),
                  const SizedBox(height: 14),
                  _grid(context),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onAddPhotos,
                      icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                      label: const Text('Add photos'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dateRow(BuildContext context) {
    final hasDate = section.date != null;
    return Row(
      children: [
        Icon(Icons.event, size: 18, color: AppTheme.textSecondary(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            dateLabel(section.date),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: hasDate
                  ? AppTheme.textPrimary(context)
                  : AppTheme.textMuted(context),
            ),
          ),
        ),
        if (hasDate)
          TextButton(
            onPressed: onClearDate,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Clear'),
          ),
        TextButton(
          onPressed: onEditDate,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(hasDate ? 'Change' : 'Set date'),
        ),
      ],
    );
  }

  Widget _grid(BuildContext context) {
    if (section.images.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          color: AppTheme.surface2(context),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        child: Column(
          children: [
            Icon(Icons.photo_outlined,
                color: AppTheme.textMuted(context), size: 28),
            const SizedBox(height: 6),
            Text(
              'No photos yet',
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary(context)),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: section.images.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemBuilder: (_, i) {
        final url = section.images[i];
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => onTapImage(i),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  child: Image.network(
                    url,
                    fit: BoxFit.cover,
                    loadingBuilder: (ctx, child, progress) =>
                        progress == null
                            ? child
                            : Container(
                                color: AppTheme.surface2(ctx),
                                child: const Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                ),
                              ),
                    errorBuilder: (ctx, _, __) => Container(
                      color: AppTheme.surface2(ctx),
                      child: Icon(Icons.broken_image_outlined,
                          color: AppTheme.textMuted(ctx)),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                onTap: () => onDeleteImage(i),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(4),
                  child: const Icon(Icons.close,
                      color: Colors.white, size: 14),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Full-screen, swipeable image viewer with prev/next.
class _FullScreenImageViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  final String title;

  const _FullScreenImageViewer({
    required this.images,
    required this.initialIndex,
    required this.title,
  });

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${widget.title} · ${_index + 1}/${widget.images.length}',
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: Image.network(
              widget.images[i],
              fit: BoxFit.contain,
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : const Center(
                      child: CircularProgressIndicator(color: Colors.white)),
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image_outlined,
                    color: Colors.white54, size: 48),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Styled name dialog for adding / renaming a custom section.
class _SectionNameDialog extends StatefulWidget {
  final String title;
  final String initial;

  const _SectionNameDialog({required this.title, this.initial = ''});

  static Future<String?> show(BuildContext context,
      {required String title, String initial = ''}) {
    return showDialog<String>(
      context: context,
      builder: (_) => _SectionNameDialog(title: title, initial: initial),
    );
  }

  @override
  State<_SectionNameDialog> createState() => _SectionNameDialogState();
}

class _SectionNameDialogState extends State<_SectionNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Section name',
        ),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Centered icon + title + message state, with an optional retry.
class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppTheme.textMuted(context)),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary(context)),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
