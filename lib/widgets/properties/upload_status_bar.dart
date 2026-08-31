import 'package:flutter/material.dart';

import '../../services/upload_progress.dart';
import '../../services/upload_queue.dart';
import '../../services/upload_service.dart';
import '../../theme.dart';

/// The upload queue, shown wherever the agent actually is.
///
/// ## Why this is not just the gallery banner
///
/// A pending count lived on the property gallery and nowhere else. On
/// 2026-08-31 an agent shot 18 photos, went camera → close, and never saw it:
/// he never returned to the screen the number was on. A counter on a screen
/// the agent does not go back to is not a counter. So this goes on every
/// surface that can produce photos — the camera, its review grid, the upload
/// sheet and the gallery — and whatever is on top while photos are pending
/// shows it.
///
/// It is a projection of the durable [UploadQueue] via [UploadProgress], never
/// of the host screen's own state, so the same number follows the agent across
/// navigation, survives backgrounding, and is still right after a restart.
///
/// It cannot be dismissed while work is outstanding. It disappears on its own
/// once the queue is empty and the "all done" moment has been shown.
class UploadStatusBar extends StatefulWidget {
  final int propertyId;

  /// Dark surfaces (the camera) need the light treatment.
  final bool onDark;

  /// Shows the "keep the app open" line under the bar while photos are
  /// pending. On by default; off only where the same words are already on
  /// screen from somewhere else.
  final bool showHint;

  final EdgeInsetsGeometry margin;

  const UploadStatusBar({
    super.key,
    required this.propertyId,
    this.onDark = false,
    this.showHint = true,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  @override
  State<UploadStatusBar> createState() => _UploadStatusBarState();
}

class _UploadStatusBarState extends State<UploadStatusBar> {
  final UploadProgress _progress = UploadProgress.instance;

  @override
  void initState() {
    super.initState();
    _progress.watch(widget.propertyId);
    _progress.addListener(_onChanged);
  }

  @override
  void dispose() {
    _progress.removeListener(_onChanged);
    _progress.unwatch(widget.propertyId);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final snap = _progress.snapshotFor(widget.propertyId);
    if (!snap.isVisible) return const SizedBox.shrink();

    final tint = snap.justFinished
        ? Colors.green
        : snap.remaining == 0 && snap.failed > 0
            ? Colors.redAccent
            : snap.offline
                ? Colors.orangeAccent
                : AppTheme.brand;

    final textColor =
        widget.onDark ? Colors.white : AppTheme.textPrimary(context);
    final subColor =
        widget.onDark ? Colors.white70 : AppTheme.textSecondary(context);

    return Container(
      margin: widget.margin,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: widget.onDark
            ? Colors.black.withValues(alpha: 0.55)
            : tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: tint.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _leading(snap, tint),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _headline(snap),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              if (snap.remaining == 0 && snap.failed > 0)
                TextButton(
                  onPressed: () =>
                      UploadService.instance.retryAllFor(widget.propertyId),
                  child: const Text('Retry'),
                ),
            ],
          ),
          // A bar across the batch reads faster than a number on its own —
          // an agent can see at a glance whether waiting means seconds or
          // minutes.
          if (snap.isPending && snap.fraction != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: snap.fraction,
                minHeight: 4,
                backgroundColor: tint.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(tint),
              ),
            ),
          ],
          if (snap.isPending && widget.showHint) ...[
            const SizedBox(height: 8),
            // Both halves matter. The first is the ask; the second is what
            // stops it becoming a rumour that closing the app eats photos.
            // An agent who believes that will re-shoot listings out of fear,
            // which would trade a fixed bug for a permanent tax on every
            // viewing. Nothing here may read as a threat of data loss,
            // because that is not what happens.
            Text(
              'Keep the app open until this finishes. Closing the app pauses '
              'uploading — your photos are saved and will continue next time '
              'you open CoreX.',
              style: TextStyle(fontSize: 11, height: 1.35, color: subColor),
            ),
          ],
        ],
      ),
    );
  }

  Widget _leading(UploadProgressSnapshot snap, Color tint) {
    if (snap.justFinished) {
      return Icon(Icons.check_circle, size: 18, color: tint);
    }
    if (snap.inFlight) {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(tint),
        ),
      );
    }
    if (snap.remaining == 0 && snap.failed > 0) {
      return Icon(Icons.error_outline, size: 18, color: tint);
    }
    return Icon(
      snap.offline ? Icons.cloud_off_outlined : Icons.cloud_upload_outlined,
      size: 18,
      color: tint,
    );
  }

  String _headline(UploadProgressSnapshot snap) {
    if (snap.justFinished) {
      final n = snap.total;
      return n > 0
          ? 'All $n photo${n == 1 ? '' : 's'} uploaded'
          : 'All photos uploaded';
    }
    if (snap.remaining == 0) {
      final f = snap.failed;
      return "$f photo${f == 1 ? '' : 's'} didn't upload";
    }
    if (snap.offline) {
      return '${snap.remaining} photo${snap.remaining == 1 ? '' : 's'} '
          'waiting — no connection';
    }
    if (snap.inFlight && snap.total > 0) {
      // done + 1 is the one on the wire, so the agent sees the photo being
      // worked on rather than the count of finished ones.
      final at = (snap.done + 1).clamp(1, snap.total);
      return 'Uploading $at of ${snap.total}…';
    }
    return '${snap.remaining} photo${snap.remaining == 1 ? '' : 's'} '
        'waiting to upload';
  }
}

/// Asks once before leaving a screen with photos still uploading.
///
/// Returns true when the agent chooses to leave — including when there is
/// nothing pending, so callers can gate a pop on this unconditionally.
///
/// One tap, and never a wall: an agent standing in someone's driveway
/// sometimes genuinely has to go. The point is only that they find out now
/// rather than from a half-empty gallery tomorrow.
Future<bool> confirmLeaveWithPendingUploads(
  BuildContext context,
  int propertyId,
) async {
  final snap = UploadProgress.instance.snapshotFor(propertyId);
  if (!snap.isPending) return true;
  final n = snap.remaining;

  final leave = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surface(ctx),
      title: Text(
        '$n photo${n == 1 ? '' : 's'} still uploading. Leave anyway?',
        style: TextStyle(fontSize: 17, color: AppTheme.textPrimary(ctx)),
      ),
      content: Text(
        'Your photos are saved. Uploading pauses when you leave and picks up '
        'again next time you open CoreX.',
        style: TextStyle(fontSize: 13, color: AppTheme.textSecondary(ctx)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Wait'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Leave — finish later'),
        ),
      ],
    ),
  );
  return leave ?? false;
}
