import 'package:flutter/material.dart';

import '../../models/visibility.dart';
import '../../theme/corex_accent_theme.dart';

/// Feedback for a list that is reloading *over existing rows* — the Mine → All
/// scope switch on Properties and Contacts.
///
/// The empty-list case already has a centred spinner. This is the other case:
/// the old scope's rows are still on screen while the new payload is fetched,
/// which takes a couple of seconds. A bare hairline progress bar was too easy
/// to miss over that long, so the wait is spelled out and the stale rows are
/// dimmed — see [DimWhileLoading].
class ScopeLoadingBanner extends StatelessWidget {
  final String label;

  const ScopeLoadingBanner({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    final isLight = Theme.of(context).brightness == Brightness.light;
    // The raw accent is tuned for dark surfaces; on the light tint below it
    // needs the darkened per-agency variant to stay legible.
    final ink = isLight ? t.accentText : t.accent;

    return Semantics(
      liveRegion: true,
      label: label,
      child: Container(
        width: double.infinity,
        color: t.accentSoft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(ink),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(ink),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fades and freezes a list while a reload is in flight, so stale rows don't
/// read as current. Taps are swallowed rather than routed to a row that is
/// about to be replaced out from under the finger.
class DimWhileLoading extends StatelessWidget {
  final bool loading;
  final Widget child;

  const DimWhileLoading({
    super.key,
    required this.loading,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: loading,
      child: AnimatedOpacity(
        opacity: loading ? 0.45 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: child,
      ),
    );
  }
}

/// Names the scope being fetched so a banner can say what it's waiting on
/// rather than a generic "Loading…". [noun] is the plural module name.
String scopeLoadingLabel(AgentFilter filter, String noun) => switch (filter) {
      AllAgentsFilter() => 'Loading all $noun…',
      SpecificAgentFilter() => "Loading agent's $noun…",
      _ => 'Loading your $noun…',
    };
