import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tabler_icons/tabler_icons.dart';
import '../widgets/ui/content_width.dart';

import '../theme/corex_accent_theme.dart';
import '../theme/corex_tokens.dart';
import '../widgets/corex/corex_bottom_nav.dart';
import '../widgets/corex/corex_secondary_button.dart';

class ComingSoonScreen extends StatelessWidget {
  final String feature;
  final String? description;
  final CorexNavTab activeTab;

  const ComingSoonScreen({
    super.key,
    required this.feature,
    this.description,
    this.activeTab = CorexNavTab.ellie,
  });

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: CorexTokens.pageBase(context),
        bottomNavigationBar: CorexBottomNav(
          active: activeTab,
          onTap: (tab) => corexNavigateTo(context, tab, activeTab),
        ),
        body: Container(
          decoration:
              BoxDecoration(gradient: CorexTokens.pageBacklight(context)),
          child: ContentSafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(TablerIcons.arrow_left,
                          color: CorexTokens.textPrimary(context)),
                    ),
                  ),
                  // Centred when there's room, scrollable when there isn't —
                  // a fixed Spacer/Spacer sandwich overflows in landscape on
                  // short viewports.
                  Expanded(
                    child: LayoutBuilder(
                      builder: (_, c) => SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: c.maxHeight),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(TablerIcons.sparkles,
                                  color: t.accent, size: 48),
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
                              if (description != null) ...[
                                const SizedBox(height: 16),
                                Text(
                                  description!,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: CorexTokens.textSecondary(context),
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  CorexSecondaryButton(
                    label: 'Back',
                    leading: TablerIcons.arrow_left,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
