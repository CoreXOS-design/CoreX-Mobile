import 'package:flutter/material.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../services/ai_consent.dart';
import '../../theme.dart';

/// The AI data disclosure — App Store guidelines 5.1.1(i) / 5.1.2(i).
///
/// Apple requires three things before personal data reaches a third-party AI
/// service: say what is sent, say who it goes to, and get permission first.
/// [AiDisclosureBody] is the "what" and "who"; [showAiConsentSheet] is the
/// permission.
///
/// **One body, two surfaces.** The consent sheet and the Settings → Data & AI
/// screen render the same widget deliberately. Two copies of a legal disclosure
/// drift, and the version the reviewer reads is then not the version the user
/// agreed to.
///
/// **Accuracy rules for this copy.** Every claim here is checkable against the
/// backend, and must stay that way:
///   * The provider is Anthropic, and only Anthropic. `config/services.php`
///     records OpenAI's removal on 2026-07-26 with a note that CoreX runs on a
///     single AI vendor — if a second vendor is ever added, this text is wrong
///     the day it lands.
///   * Voice audio genuinely does not leave CoreX: `SpeechToTextService` posts
///     to a self-hosted faster-whisper instance on `127.0.0.1:3100`. Only the
///     resulting transcript goes to `api.anthropic.com`.
///   * Photos go to `api.anthropic.com` via `AnalysePropertyImageJob`, queued
///     by the image upload endpoint.
const String kAiProvider = 'Anthropic PBC';

/// What the user is agreeing to, rendered identically wherever it appears.
class AiDisclosureBody extends StatelessWidget {
  const AiDisclosureBody({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Paragraph(
          'CoreX uses AI for two things: turning what you say to Ellie into '
          'diary entries, and suggesting features from the photos you upload '
          'to a property.',
        ),
        SizedBox(height: 18),
        _Heading('What is sent'),
        _Bullet(
          icon: TablerIcons.message,
          text: 'The words you speak to Ellie, as text. These can include '
              'names, addresses and appointment details you mention.',
        ),
        _Bullet(
          icon: TablerIcons.photo,
          text: 'Photos you upload to a property.',
        ),
        SizedBox(height: 18),
        _Heading('Who it is sent to'),
        _Bullet(
          icon: TablerIcons.building,
          text: '$kAiProvider (Claude), the AI provider CoreX uses. They '
              'process it only to return a result and do not use it to train '
              'their models.',
        ),
        SizedBox(height: 18),
        _Heading('What is not sent'),
        _Bullet(
          icon: TablerIcons.microphone,
          text: 'Your voice recording itself. CoreX turns audio into text on '
              'its own servers — the recording never leaves CoreX.',
        ),
        _Bullet(
          icon: TablerIcons.lock,
          text: 'Your deals, commissions, contact records and documents.',
        ),
      ],
    );
  }
}

/// The one line that differs between asking and reviewing, kept next to the
/// body so the two read as one piece of copy.
class AiDisclosureFootnote extends StatelessWidget {
  final String text;
  const AiDisclosureFootnote(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.45,
          color: AppTheme.textMuted(context),
        ),
      ),
    );
  }
}

/// Asks for permission, records the answer, and reports whether the caller may
/// proceed. Returns false on dismissal — a swipe-away is not agreement.
///
/// Never call this from inside a press-and-hold gesture. A sheet cancels the
/// touch that opened it, so the press releases at ~0 ms and is discarded; that
/// exact mistake with the microphone prompt cost a 2.1(a) rejection. Resolve
/// consent on its own press, then let the next one record.
Future<bool> showAiConsentSheet(BuildContext context) async {
  final agreed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => const _AiConsentSheet(),
  );

  // Dismissed without choosing: leave the state untouched so the next attempt
  // asks again, rather than recording a refusal the user never made.
  if (agreed == null) return false;

  await AiConsent.instance.set(agreed);
  return agreed;
}

class _AiConsentSheet extends StatelessWidget {
  const _AiConsentSheet();

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.borderColor(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'AI features and your data',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(height: 14),
              const AiDisclosureBody(),
              const AiDisclosureFootnote(
                'You can change this at any time in Settings → Data & AI. '
                'With it off, Ellie voice and photo suggestions are '
                'unavailable — everything else in CoreX works as normal.',
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                  ),
                ),
                child: const Text(
                  'Agree and continue',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: AppTheme.textMuted(context),
        ),
      ),
    );
  }
}

class _Paragraph extends StatelessWidget {
  final String text;
  const _Paragraph(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        height: 1.5,
        color: AppTheme.textSecondary(context),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Bullet({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 17, color: AppTheme.textMuted(context)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
