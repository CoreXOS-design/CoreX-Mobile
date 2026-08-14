import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_version.dart';
import '../providers/branding_provider.dart';
import '../services/app_update_service.dart';
import '../utils/external_launch.dart';

/// Terminal screen shown when this build is below the server's minimum
/// supported build.
///
/// There is deliberately no way out of it: no back button, no dismiss, no
/// "later". A soft nudge is a different feature — this screen only ever appears
/// when an operator has decided the build must not keep running, and offering
/// an escape hatch would defeat the point of raising the cutoff at all.
///
/// The one thing it must never do is strand someone. The Update button is
/// guaranteed to have somewhere to go: both [AppUpdateService] and the server
/// refuse to gate a platform with no configured update URL.
class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({super.key, required this.status});

  final AppUpdateStatus status;

  @override
  Widget build(BuildContext context) {
    final b = context.watch<BrandingProvider>().branding;
    final theme = Theme.of(context);

    return PopScope(
      // Swallows the Android system back gesture. Without this the user pops
      // straight past the gate into the app it exists to stop.
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.system_update,
                    size: 64,
                    color: b.button,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Update required',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    status.message?.isNotEmpty == true
                        ? status.message!
                        : 'This version of CoreX is no longer supported. '
                            'Update to the latest version to carry on.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodySmall?.color,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: b.button,
                        foregroundColor: b.onButton,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () =>
                          launchExternal(context, status.updateUrl),
                      child: const Text('Update now'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // The build number is the first thing anyone asks for when an
                  // agent phones in about this screen.
                  Text(
                    'Installed: $kAppVersionFull',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
