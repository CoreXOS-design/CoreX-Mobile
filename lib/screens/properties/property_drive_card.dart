import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/property_drive.dart';
import '../../services/api_service.dart';
import '../../theme.dart';
import '../../utils/app_time.dart';

/// The two things a Drive row can do with a file. Both fetch the same bytes
/// from the same gated endpoint and differ only in where they hand them off.
enum DriveRowAction {
  /// Native "save to…" dialog — Android's ACTION_CREATE_DOCUMENT, iOS's
  /// document-picker export. The agent chooses the destination folder.
  save,

  /// OS share sheet — WhatsApp, email, Drive, and so on.
  share,
}

/// The property Drive section: every file filed against this listing on the
/// web, with folder chips and a per-row download.
///
/// Read-only by design — uploading, tagging and deleting stay web-only for now,
/// so a file added on web shows up here after the next pull-to-refresh. The
/// parent owns the fetch (so the screen's existing RefreshIndicator refreshes
/// this too); this widget owns only the folder filter and download state.
///
/// The card renders in every state — loading, failed, empty, populated — the
/// same way [_contactsCard] does on the Overview screen. It must never hide
/// itself on error: a section that silently disappears reads as "this feature
/// doesn't exist" rather than "this request failed", which is exactly how a
/// missing endpoint went unnoticed.
class PropertyDriveCard extends StatefulWidget {
  /// Null while the first fetch is in flight, or when it failed.
  final PropertyDriveData? data;
  final ApiService api;
  final int propertyId;

  /// True while the initial fetch is running.
  final bool loading;

  /// Set when the fetch failed; shown with a Retry.
  final String? error;

  /// Re-runs the fetch behind the Retry button.
  final Future<void> Function()? onRetry;

  /// Called when a download proves the list is stale (404) so the parent can
  /// re-fetch. The offending row is dropped locally either way.
  final Future<void> Function()? onStale;

  const PropertyDriveCard({
    super.key,
    required this.data,
    required this.api,
    required this.propertyId,
    this.loading = false,
    this.error,
    this.onRetry,
    this.onStale,
  });

  @override
  State<PropertyDriveCard> createState() => _PropertyDriveCardState();
}

class _PropertyDriveCardState extends State<PropertyDriveCard> {
  /// Selected folder, held as a stable key rather than a [DriveFolder] instance
  /// so the selection survives a refresh that rebuilds the folder objects.
  /// Null means "All".
  String? _selectedKey;

  /// Document id → the action currently in flight for it, so the row can show
  /// a spinner in place of the button that was tapped and disable the other.
  final Map<int, DriveRowAction> _busy = {};

  /// Rows proven stale by a 404, hidden immediately so a dead file can't be
  /// tapped again while the parent re-fetches.
  final Set<int> _dropped = {};

  static String _keyFor(DriveFolder f) =>
      f.documentTypeId?.toString() ?? '__unfiled__';

  /// Resolves the selection against the *current* data. A folder that no longer
  /// exists after a refresh falls back to "All" rather than showing nothing.
  DriveFolder? get _selectedFolder {
    final key = _selectedKey;
    final data = widget.data;
    if (key == null || data == null) return null;
    for (final f in data.folders) {
      if (_keyFor(f) == key) return f;
    }
    return null;
  }

  List<PropertyDocument> get _visible =>
      (widget.data?.documentsIn(_selectedFolder) ?? const [])
          .where((d) => !_dropped.contains(d.id))
          .toList();

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Anchor rect for the iOS/iPad share popover — omitting it makes the share
  /// sheet throw on iPad.
  Rect? _originFrom(BuildContext ctx) {
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Fetches the file once, then either saves it or shares it.
  ///
  /// Both paths go through the same gated endpoint, so an agent who can't
  /// download can't share either — sharing would otherwise be a one-tap way
  /// around the assistant download switch.
  Future<void> _run(
    PropertyDocument doc,
    DriveRowAction action,
    BuildContext buttonContext,
  ) async {
    if (_busy.containsKey(doc.id)) return;
    final origin = _originFrom(buttonContext);
    setState(() => _busy[doc.id] = action);
    try {
      final file = await widget.api.downloadPropertyDocument(
        widget.propertyId,
        doc.id,
        doc.originalName,
        downloadUrl: doc.downloadUrl,
      );
      if (!mounted) return;

      if (action == DriveRowAction.share) {
        await Share.shareXFiles(
          [
            XFile.fromData(
              file.bytes,
              name: file.fileName,
              mimeType: file.mimeType,
            )
          ],
          sharePositionOrigin: origin,
        );
        return;
      }

      final parts = splitFileName(file.fileName);
      final saved = await FileSaver.instance.saveAs(
        name: parts.base,
        bytes: file.bytes,
        fileExtension: parts.ext,
        includeExtension: parts.ext.isNotEmpty,
        // Drive holds any file type, so pass the server's own content type
        // through rather than guessing from a fixed enum.
        mimeType: MimeType.custom,
        customMimeType: file.mimeType ?? 'application/octet-stream',
      );
      if (!mounted) return;
      // Null/empty means the agent backed out of the save dialog — not an
      // error, and not worth a message.
      if (saved != null && saved.isNotEmpty) {
        _snack('Saved ${file.fileName}');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      _snack(e.message);
      if (e.statusCode == 404) {
        // Stale list: hide the row now, then let the parent re-fetch.
        setState(() => _dropped.add(doc.id));
        await widget.onStale?.call();
      }
    } catch (_) {
      if (!mounted) return;
      _snack("Couldn't download that file. Check your connection.");
    } finally {
      if (mounted) setState(() => _busy.remove(doc.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _body(),
        ),
      ),
    );
  }

  List<Widget> _body() {
    final data = widget.data;

    if (data == null && widget.loading) {
      return const [
        Center(
          child: Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      ];
    }

    if (data == null) {
      return [_errorState(widget.error ?? "Couldn't load files.")];
    }

    final docs = _visible;
    return [
      if (data.folders.isNotEmpty) ...[
        _folderChips(data),
        const SizedBox(height: 4),
      ],
      if (data.isEmpty)
        _emptyState('No files on this property yet.')
      else if (docs.isEmpty)
        _emptyState('No files in this folder.')
      else
        for (final d in docs) _documentRow(d),
    ];
  }

  Widget _errorState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined,
              size: 18, color: AppTheme.textMuted(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary(context)),
            ),
          ),
          if (widget.onRetry != null)
            TextButton(
              onPressed: () => widget.onRetry!(),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }

  Widget _folderChips(PropertyDriveData data) {
    final selected = _selectedKey;
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(
            label: 'All',
            count: data.documents.length,
            active: selected == null,
            onTap: () => setState(() => _selectedKey = null),
          ),
          for (final f in data.folders)
            _chip(
              label: f.label,
              count: f.count,
              active: selected == _keyFor(f),
              onTap: () => setState(() => _selectedKey = _keyFor(f)),
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required int count,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppTheme.brand : AppTheme.surface2(context),
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color:
                      active ? Colors.white : AppTheme.textPrimary(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    color: active
                        ? Colors.white.withValues(alpha: 0.85)
                        : AppTheme.textSecondary(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, color: AppTheme.textSecondary(context)),
        ),
      ),
    );
  }

  Widget _documentRow(PropertyDocument doc) {
    final meta = [
      doc.humanSize,
      doc.uploadedByName,
      relativeTime(doc.createdAt),
    ].where((s) => s != null && s.trim().isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.surface2(context),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: Icon(_iconFor(doc.kind),
                size: 20, color: _colorFor(doc.kind, context)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.originalName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppTheme.textPrimary(context)),
                ),
                if (meta.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context)),
                    ),
                  ),
              ],
            ),
          ),
          _rowActions(doc),
        ],
      ),
    );
  }

  Widget _rowActions(PropertyDocument doc) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _actionButton(
          doc,
          DriveRowAction.save,
          icon: Icons.download_rounded,
          tooltip: 'Save to device',
        ),
        _actionButton(
          doc,
          DriveRowAction.share,
          icon: Icons.ios_share_rounded,
          tooltip: 'Share',
        ),
      ],
    );
  }

  Widget _actionButton(
    PropertyDocument doc,
    DriveRowAction action, {
    required IconData icon,
    required String tooltip,
  }) {
    final busy = _busy[doc.id];

    // Spinner replaces whichever button was tapped.
    if (busy == action) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    // `can_download` gates BOTH actions: sharing fetches the same bytes from
    // the same gated endpoint, so leaving Share live would be a one-tap way
    // around the assistant download switch. It's per-row and can flip without
    // the list changing, so grey it and say why rather than let the tap 403.
    final blocked = !doc.canDownload;
    final disabled = blocked || busy != null;

    return Builder(
      builder: (btnContext) => IconButton(
        icon: Icon(icon, size: 20),
        color: AppTheme.brand,
        disabledColor: AppTheme.textMuted(context),
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
        tooltip: blocked
            ? 'Downloads are switched off for your account'
            : tooltip,
        onPressed:
            disabled ? null : () => _run(doc, action, btnContext),
      ),
    );
  }

  IconData _iconFor(DriveFileKind kind) => switch (kind) {
        DriveFileKind.pdf => Icons.picture_as_pdf_outlined,
        DriveFileKind.image => Icons.image_outlined,
        DriveFileKind.doc => Icons.description_outlined,
        DriveFileKind.sheet => Icons.table_chart_outlined,
        DriveFileKind.generic => Icons.insert_drive_file_outlined,
      };

  Color _colorFor(DriveFileKind kind, BuildContext context) =>
      switch (kind) {
        DriveFileKind.pdf => Colors.redAccent,
        DriveFileKind.image => Colors.blueAccent,
        DriveFileKind.sheet => Colors.green,
        _ => AppTheme.textSecondary(context),
      };
}
