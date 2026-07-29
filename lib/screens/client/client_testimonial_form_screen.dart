import 'package:flutter/material.dart';
import 'package:tabler_icons/tabler_icons.dart';
import '../../widgets/ui/content_width.dart';

import '../../models/client_models.dart';
import '../../services/api_service.dart' show ApiException, ValidationException;
import '../../services/client_auth_service.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../widgets/corex/corex_primary_button.dart';
import '../../widgets/corex/corex_scaffold.dart';

const int _kMaxBody = 5000;
const Color _kSuccess = Color(0xFF22C55E);

/// Write-a-testimonial form. The client reviews their connected agent; the
/// server attributes the agent automatically and creates the testimonial
/// unpublished, so on success we say it was "sent to your agent" rather than
/// implying it's live on the website.
///
/// Pops `true` once a testimonial has been submitted so the caller can refresh.
class ClientTestimonialFormScreen extends StatefulWidget {
  /// Prefilled into the display-name field; the client may shorten it
  /// (e.g. "Bob Buyer" → "Bob B.").
  final String? prefillName;

  /// Injectable for tests; production uses the default client service.
  final ClientAuthService? api;

  const ClientTestimonialFormScreen({super.key, this.prefillName, this.api});

  @override
  State<ClientTestimonialFormScreen> createState() =>
      _ClientTestimonialFormScreenState();
}

class _ClientTestimonialFormScreenState
    extends State<ClientTestimonialFormScreen> {
  late final ClientAuthService _api = widget.api ?? ClientAuthService();

  late final TextEditingController _body;
  late final TextEditingController _displayName;

  int? _rating;
  bool _saving = false;
  bool _done = false;
  Map<String, String> _fieldErrors = {};

  @override
  void initState() {
    super.initState();
    _body = TextEditingController()..addListener(_onBodyChanged);
    _displayName = TextEditingController(text: widget.prefillName ?? '');
  }

  @override
  void dispose() {
    _body.removeListener(_onBodyChanged);
    _body.dispose();
    _displayName.dispose();
    super.dispose();
  }

  // Drives the submit button's enabled state off the body field.
  void _onBodyChanged() => setState(() {});

  bool get _canSubmit => _body.text.trim().isNotEmpty && !_saving;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _saving = true;
      _fieldErrors = {};
    });
    try {
      await _api.submitTestimonial(ClientTestimonialInput(
        body: _body.text.trim(),
        rating: _rating,
        displayName:
            _displayName.text.trim().isEmpty ? null : _displayName.text.trim(),
      ));
      if (!mounted) return;
      setState(() {
        _saving = false;
        _done = true;
      });
    } on ValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _fieldErrors = e.fieldErrors;
      });
      if (e.fieldErrors.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = e.statusCode == 409
          ? 'Choose an agency first, then leave your review.'
          : e.statusCode == 404
              ? "We couldn't find your contact record with this agency."
              : e.message;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not submit. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CorexScaffold(
      title: _done ? 'Review sent' : 'Review your agent',
      body: ContentSafeArea(
        top: false,
        child: _done ? _successView() : _formView(),
      ),
    );
  }

  Widget _formView() {
    final bodyError = _fieldErrors['body'];
    final nameError = _fieldErrors['display_name'];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _section('Your review'),
        TextField(
          controller: _body,
          maxLines: 6,
          minLines: 4,
          maxLength: _kMaxBody,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: 'Share how your agent helped you…',
            errorText: bodyError,
          ),
        ),
        _section('Rating (optional)'),
        _stars(),
        _section('Display name (optional)'),
        TextField(
          controller: _displayName,
          maxLength: 150,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: 'Bob B.',
            helperText: 'How your name appears with the review.',
            errorText: nameError,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Your review goes to your agent for their agency to publish — it '
          "won't appear on the website until they approve it.",
          style: TextStyle(
            fontSize: 12,
            color: CorexTokens.textTertiary(context),
          ),
        ),
        const SizedBox(height: 20),
        CorexPrimaryButton(
          label: 'Send to my agent',
          leading: TablerIcons.send,
          loading: _saving,
          onPressed: _canSubmit ? _submit : null,
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _successView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(
              color: Color(0x2222C55E),
              shape: BoxShape.circle,
            ),
            child: const Icon(TablerIcons.check, color: _kSuccess, size: 40),
          ),
          const SizedBox(height: 20),
          Text(
            'Thanks — sent to your agent',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: CorexTokens.textPrimary(context),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Your agency reviews every testimonial before it goes live. "
            "We'll show it as “Submitted” until they publish it.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: CorexTokens.textSecondary(context),
            ),
          ),
          const SizedBox(height: 28),
          CorexPrimaryButton(
            label: 'Done',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 6),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: CorexTokens.textSecondary(context),
          ),
        ),
      );

  Widget _stars() {
    final t = CorexAccentTheme.of(context);
    final current = _rating ?? 0;
    return Row(
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            // Tapping the currently selected star clears the rating, since it's
            // optional and there's otherwise no way back to "no rating".
            onPressed: _saving
                ? null
                : () => setState(() => _rating = _rating == i ? null : i),
            visualDensity: VisualDensity.compact,
            icon: Icon(
              current >= i ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 34,
              color:
                  current >= i ? t.accent : CorexTokens.textTertiary(context),
            ),
          ),
        const Spacer(),
        if (_rating != null)
          TextButton(
            onPressed: _saving ? null : () => setState(() => _rating = null),
            child: const Text('Clear'),
          ),
      ],
    );
  }
}
