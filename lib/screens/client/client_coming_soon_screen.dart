import 'package:flutter/material.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../widgets/corex/corex_scaffold.dart';
import '../../widgets/corex/corex_secondary_button.dart';

/// Client-side "coming soon" placeholder. Unlike the staff [ComingSoonScreen]
/// this carries no staff bottom-nav — it's just a back-navigable page so the
/// client never leaks into staff-only navigation.
class ClientComingSoonScreen extends StatelessWidget {
  final String feature;
  const ClientComingSoonScreen({super.key, required this.feature});

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    return CorexScaffold(
      title: feature,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Spacer(),
            Icon(TablerIcons.sparkles, color: t.accent, size: 48),
            const SizedBox(height: 20),
            Text(
              feature,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CorexTokens.textPrimary(context),
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'COMING SOON',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CorexTokens.textSecondary(context),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.2,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'We\'re still building this. Check back soon.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CorexTokens.textSecondary(context),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const Spacer(),
            CorexSecondaryButton(
              label: 'Back',
              leading: TablerIcons.arrow_left,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
