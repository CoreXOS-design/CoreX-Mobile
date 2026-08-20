import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_version.dart';
import '../providers/branding_provider.dart';
import '../services/app_update_service.dart';
import '../utils/external_launch.dart';

/// The optional "a new version is out" nudge.
///
/// Distinct from [ForceUpdateScreen] in every way that matters: that one is a
/// terminal screen with no way out, shown when an operator has decided the
/// build must stop running. This is a dismissible dialog for a release the user
/// merely *should* take.
///
/// The app's standing UX rule is no intrusive auto-popups on launch, and this
/// stays on the right side of it by never asking twice for the same release:
/// "Later" is recorded against the build number, so it goes quiet until a
/// genuinely newer version ships. One notice per release, not one per launch.
class UpdateAvailableDialog extends StatelessWidget {
  const UpdateAvailableDialog({super.key, required this.status});

  final AppUpdateStatus status;

  /// Shows the dialog if this release hasn't already been dismissed.
  ///
  /// Returns without doing anything when there's nothing to announce, so
  /// callers can call it unconditionally.
  static Future<void> maybeShow(
    BuildContext context,
    AppUpdateStatus status,
  ) async {
    if (!status.updateAvailable) return;
    final build = status.latestBuild;
    if (build == null) return;
    if (!await AppUpdateService.shouldPromptFor(build)) return;
    if (!context.mounted) return;

    final wantsUpdate = await showDialog<bool>(
      context: context,
      // Dismissible on purpose — the whole point of the optional nudge is that
      // it is optional. A barrier tap counts as "Later".
      barrierDismissible: true,
      builder: (_) => UpdateAvailableDialog(status: status),
    );

    // Whatever the user did — Update, Later, or tapping outside — this release
    // has now been announced. Without recording it here, dismissing by barrier
    // tap would leave the prompt firing on every single launch, which is
    // precisely the nagging this feature must not become.
    await AppUpdateService.snooze(build);

    // Launched from the caller's context, not the dialog's: [launchExternal]
    // resolves a ScaffoldMessenger the moment it is called, and the dialog's
    // context is already defunct by then.
    if (wantsUpdate == true && context.mounted) {
      await launchExternal(context, status.updateUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.watch<BrandingProvider>().branding;
    final theme = Theme.of(context);

    // Prefer the marketing version if the server sent one; the build number is
    // meaningless to an agent but is a fine fallback for an internal release.
    final target = status.latestVersion?.isNotEmpty == true
        ? status.latestVersion!
        : 'build ${status.latestBuild}';

    return AlertDialog(
      icon: Icon(Icons.system_update, size: 40, color: b.button),
      title: const Text('Update available'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            status.message?.isNotEmpty == true
                ? status.message!
                : 'CoreX $target is ready to install. Update to get the '
                    'latest fixes and features.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            "You're on $kAppVersionFull",
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: b.button,
              foregroundColor: b.onButton,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            // Closes first and lets [maybeShow] open the store. Launching
            // backgrounds the app, and a dialog left open underneath is what
            // would greet them on return.
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Update now'),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Later'),
          ),
        ),
      ],
    );
  }
}
