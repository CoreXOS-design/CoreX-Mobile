import 'package:flutter/material.dart';

import '../models/branding.dart';
import '../services/ai_consent.dart';
import '../theme.dart';
import '../widgets/ai/ai_disclosure.dart';
import '../widgets/ui/content_width.dart';

/// Settings → Data & AI. The reviewable, revocable half of the AI consent
/// requirement (App Store 5.1.1(i) / 5.1.2(i)).
///
/// Permission that can only be given and never withdrawn isn't permission, and
/// a reviewer looking for the disclosure needs somewhere obvious to find it
/// after the first-run sheet is gone. Same [AiDisclosureBody] as the sheet, so
/// what is reviewed here is exactly what was agreed to there.
class AiDataScreen extends StatelessWidget {
  const AiDataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final consent = AiConsent.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Data & AI')),
      body: ContentSafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: ListenableBuilder(
            listenable: consent,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ConsentCard(
                  granted: consent.granted,
                  onChanged: (value) => consent.set(value),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: AppTheme.cardGradient(context),
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    boxShadow: AppTheme.softShadow(context),
                  ),
                  child: const AiDisclosureBody(),
                ),
                const AiDisclosureFootnote(
                  'Turning this off stops CoreX sending anything further to '
                  'its AI provider. Ellie voice and photo suggestions stop '
                  'working; the rest of CoreX is unaffected. Results produced '
                  'before you turned it off stay on your properties until you '
                  'remove them.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConsentCard extends StatelessWidget {
  final bool granted;
  final ValueChanged<bool> onChanged;

  const _ConsentCard({required this.granted, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: AppTheme.softShadow(context),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Allow AI features',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  granted
                      ? 'Ellie voice and photo suggestions are on.'
                      : 'Ellie voice and photo suggestions are off.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: granted,
            activeTrackColor: brand.button,
            activeThumbColor: Colors.white,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
