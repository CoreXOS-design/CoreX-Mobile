import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/image_cache.dart';
import '../services/image_cache_diagnostics.dart';
import '../theme.dart';

/// "12 files · 3.4 MB" for a settings row's trailing slot. Re-reads on every
/// build so a Clear from the details sheet shows up as soon as the row
/// rebuilds.
class ImageCacheSummary extends StatelessWidget {
  const ImageCacheSummary({super.key});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppTheme.textMuted(context),
    );
    return FutureBuilder<ImageCacheReport>(
      future: ImageCacheDiagnostics.inspect(),
      builder: (ctx, snap) {
        final r = snap.data;
        if (r == null) return Text('…', style: style);
        return Text(
          r.healthy ? r.summary : '${r.summary} · check',
          style: r.healthy ? style : style.copyWith(color: Colors.orangeAccent),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

/// Full report as a bottom sheet: what's on disk, whether the storage
/// plumbing works on this device, the memory cache, and the last image loads
/// that failed — plus Copy (so a tester can paste the report into a chat) and
/// Clear (to watch the cache refill from empty).
Future<void> showImageCacheDetails(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.background(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (_) => const _ImageCacheDetailsSheet(),
  );
}

class _ImageCacheDetailsSheet extends StatefulWidget {
  const _ImageCacheDetailsSheet();

  @override
  State<_ImageCacheDetailsSheet> createState() =>
      _ImageCacheDetailsSheetState();
}

class _ImageCacheDetailsSheetState extends State<_ImageCacheDetailsSheet> {
  late Future<ImageCacheReport> _report = ImageCacheDiagnostics.inspect();
  bool _clearing = false;

  Future<void> _clear() async {
    setState(() => _clearing = true);
    try {
      await ImageCacheDiagnostics.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not clear: $e')));
      }
    }
    if (!mounted) return;
    setState(() {
      _clearing = false;
      _report = ImageCacheDiagnostics.inspect();
    });
  }

  Future<void> _copy(ImageCacheReport r) async {
    final failures = r.recentFailures.isEmpty
        ? ''
        : '\nrecent failures:\n${r.recentFailures.join('\n')}';
    await Clipboard.setData(ClipboardData(text: '${r.toLogLine()}$failures'));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Report copied')));
  }

  @override
  Widget build(BuildContext context) {
    final muted =
        TextStyle(fontSize: 12, color: AppTheme.textSecondary(context));
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: FutureBuilder<ImageCacheReport>(
          future: _report,
          builder: (ctx, snap) {
            final r = snap.data;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Image cache',
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
                      'Property photos are kept on this device after the first '
                      'download so galleries open without re-fetching. Lists '
                      'and grids store small thumbnails; only photos opened '
                      'full-screen are kept at full size, and only the most '
                      'recent few dozen.',
                      style: muted,
                    ),
                  ),
                ),
                if (r == null)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      children: [
                        _row(context, 'Status',
                            r.healthy ? 'OK' : 'Needs attention',
                            warn: !r.healthy),
                        _row(context, 'Photos on disk',
                            '${r.fileCount} files · ${ImageCacheReport.formatBytes(r.fileBytes)}'),
                        _row(context, 'Of which full-size',
                            '${r.fullFileCount} files · ${ImageCacheReport.formatBytes(r.fullFileBytes)} (viewer only, keeps last ${CoreXImageCache.fullObjectCap})'),
                        _row(context, 'Cache folder',
                            r.fileDirExists ? 'present' : 'not created yet'),
                        _row(context, 'Temp storage writable',
                            r.tempWritable ? 'yes' : 'NO',
                            warn: !r.tempWritable),
                        _row(
                            context,
                            'Cache index (sqlite)',
                            r.dbExists
                                ? ImageCacheReport.formatBytes(r.dbBytes)
                                : 'not created yet'),
                        _row(context, 'In memory',
                            '${r.memImages} images · ${ImageCacheReport.formatBytes(r.memBytes)} of ${ImageCacheReport.formatBytes(r.memMaxBytes)}'),
                        if (r.error != null)
                          _row(context, 'Error', r.error!, warn: true),
                        const SizedBox(height: 8),
                        Text('Recent failed loads',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary(context))),
                        const SizedBox(height: 4),
                        if (r.recentFailures.isEmpty)
                          Text('None this session.', style: muted)
                        else
                          for (final f in r.recentFailures)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(f,
                                  style: muted.copyWith(fontSize: 11.5)),
                            ),
                        const SizedBox(height: 8),
                        Text(r.fileDir,
                            style: muted.copyWith(
                                fontSize: 10.5,
                                color: AppTheme.textMuted(context))),
                      ],
                    ),
                  ),
                if (r != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _copy(r),
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 44)),
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: const Text('Copy report'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _clearing ? null : _clear,
                            style: ElevatedButton.styleFrom(
                                minimumSize: const Size(0, 44)),
                            icon: _clearing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.delete_sweep_outlined,
                                    size: 18),
                            label: const Text('Clear cache'),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {bool warn = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5, color: AppTheme.textSecondary(context))),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color:
                    warn ? Colors.orangeAccent : AppTheme.textPrimary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
