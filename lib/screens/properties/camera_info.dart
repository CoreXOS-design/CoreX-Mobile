import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme.dart';

/// Shared "how photo capture works" explainer, used by every screen that can
/// add photos (property create/edit gallery upload + rental inspections).
///
/// It must only ever pop up **once** for a user — across all those screens —
/// so the seen-flag lives behind a single shared pref key and an in-memory
/// guard prevents a double-show within one session.
const String _kCameraInfoSeenKey = 'camera_info_seen_v2';

/// In-memory latch so two near-simultaneous callers (or a rebuild) can't both
/// race past the async pref read and show the dialog twice.
bool _shownThisSession = false;

/// Shows the camera explainer the first time only. No-op afterwards. Safe to
/// call from any "add photos" entry point.
Future<void> maybeShowCameraInfo(BuildContext context) async {
  if (_shownThisSession) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kCameraInfoSeenKey) == true) {
      _shownThisSession = true;
      return;
    }
    if (!context.mounted) return;
    _shownThisSession = true;
    await CameraInfoDialog.show(context);
    await prefs.setBool(_kCameraInfoSeenKey, true);
  } catch (_) {/* never block the camera on a prefs hiccup */}
}

/// The explainer dialog, shown once per user. It's dismissible (tap outside or
/// "Got it") so it never blocks the user from getting to the camera.
class CameraInfoDialog extends StatelessWidget {
  const CameraInfoDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const CameraInfoDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
        backgroundColor: AppTheme.surface(context),
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
                title: 'Multi Capture',
                body:
                    'In-app rapid camera. Take many photos in a row, then review and confirm them all at once. Multi Capture relies on direct camera access and might not work on every device — if it fails to open or behaves oddly, use Native instead. On some devices the ultrawide (0.6x) lens is also hidden from third-party apps and won\'t appear here — Native reaches it.',
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
                    'When uploading to a property gallery, pick a tag (room/space) first so the photo is filed correctly. "No tag" sends them to Unsorted — you can re-tag later. (Rental inspection sections don\'t use tags.)',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
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
