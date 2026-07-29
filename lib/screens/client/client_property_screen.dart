import 'package:flutter/material.dart';
import 'package:tabler_icons/tabler_icons.dart';
import '../../utils/external_launch.dart';

import '../../models/client_models.dart';
import '../../services/api_service.dart' show ApiException;
import '../../services/client_auth_service.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../widgets/client/not_for_me_sheet.dart';
import '../../widgets/client/reaction_bar.dart';
import '../../widgets/corex/corex_card.dart';
import '../../widgets/corex/corex_chip.dart';
import '../../widgets/corex/corex_primary_button.dart';
import '../../widgets/corex/corex_scaffold.dart';
import '../../widgets/corex/corex_secondary_button.dart';

typedef ReactionChanged = void Function(String reaction, String? note);

class ClientPropertyScreen extends StatefulWidget {
  final int propertyId;
  final int? matchId;
  final String? initialReaction;
  final String? initialReactionNote;
  final ReactionChanged? onReactionChanged;

  const ClientPropertyScreen({
    super.key,
    required this.propertyId,
    this.matchId,
    this.initialReaction,
    this.initialReactionNote,
    this.onReactionChanged,
  });

  @override
  State<ClientPropertyScreen> createState() => _ClientPropertyScreenState();
}

class _ClientPropertyScreenState extends State<ClientPropertyScreen> {
  final _api = ClientAuthService();

  bool _loading = true;
  String? _error;
  ClientPropertyDetail? _property;

  String? _reaction;
  String? _reactionNote;

  bool _descExpanded = false;
  int _imageIndex = 0;
  final _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _reaction = widget.initialReaction;
    _reactionNote = widget.initialReactionNote;
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await _api.property(widget.propertyId);
      if (!mounted) return;
      setState(() {
        _property = p;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 404 || e.statusCode == 403) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Property no longer available')),
        );
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load property.';
      });
    }
  }

  Future<void> _react(String reaction) async {
    if (widget.matchId == null) return;
    String? note = _reactionNote;
    if (reaction == 'not_interested') {
      final entered = await showNotForMeSheet(context, initialNote: note);
      if (entered == null) return;
      note = entered;
    } else {
      note = null;
    }

    final prevReaction = _reaction;
    final prevNote = _reactionNote;
    setState(() {
      _reaction = reaction;
      _reactionNote = note;
    });
    widget.onReactionChanged?.call(reaction, note);

    try {
      await _api.postFeedback(
        matchId: widget.matchId!,
        propertyId: widget.propertyId,
        reaction: reaction,
        note: note,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reaction = prevReaction;
        _reactionNote = prevNote;
      });
      if (prevReaction != null) {
        widget.onReactionChanged?.call(prevReaction, prevNote);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  Future<void> _launch(String url) => launchExternal(context, url);

  @override
  Widget build(BuildContext context) {
    return CorexScaffold(
      title: 'Property',
      body: _body(),
      bottomBar: (widget.matchId != null && _property != null)
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: ReactionBar(
                  current: _reaction,
                  onInterested: _react,
                  onSaved: _react,
                  onNotForMe: _react,
                ),
              ),
            )
          : null,
    );
  }

  Widget _body() {
    if (_loading && _property == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _property == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            _error!,
            style: TextStyle(color: CorexTokens.textSecondary(context)),
          ),
        ),
      );
    }
    final t = CorexAccentTheme.of(context);
    final p = _property!;
    final images = p.images.isNotEmpty
        ? p.images
        : (p.thumbnail != null ? [p.thumbnail!] : <String>[]);

    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (images.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(CorexTokens.radius),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      itemCount: images.length,
                      onPageChanged: (i) => setState(() => _imageIndex = i),
                      itemBuilder: (_, i) => Image.network(
                        images[i],
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: CorexTokens.surfaceTop(context),
                          child: Icon(TablerIcons.photo_off,
                              color: CorexTokens.textTertiary(context)),
                        ),
                      ),
                    ),
                    if (images.length > 1)
                      Positioned(
                        bottom: 8,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < images.length; i++)
                              Container(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: i == _imageIndex
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.45),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (p.title != null && p.title!.isNotEmpty)
            Text(
              p.title!,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: CorexTokens.textPrimary(context),
              ),
            ),
          if (p.address != null && p.address!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                p.address!,
                style: TextStyle(
                  fontSize: 13,
                  color: CorexTokens.textSecondary(context),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            p.priceDisplay ?? (p.price != null ? 'R ${_money(p.price!)}' : ''),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: t.accentMoney,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (p.beds != null) _stat(TablerIcons.bed, '${p.beds} bd'),
              if (p.baths != null) _stat(TablerIcons.bath, '${p.baths} ba'),
              if (p.garages != null)
                _stat(TablerIcons.car, '${p.garages} garage'),
              if (p.parking != null)
                _stat(TablerIcons.parking, '${p.parking} parking'),
              if (p.floorSize != null)
                _stat(TablerIcons.ruler_2, '${p.floorSize}m² floor'),
              if (p.erfSize != null)
                _stat(TablerIcons.square, '${p.erfSize}m² erf'),
            ],
          ),
          if (p.description != null && p.description!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _description(p.description!),
          ],
          if (p.features.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Features',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: CorexTokens.textPrimary(context),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: p.features.map((f) => CorexChip(label: f)).toList(),
            ),
          ],
          if (p.agent != null) ...[
            const SizedBox(height: 20),
            _agentCard(p.agent!, p.branch),
          ],
          if (p.webPreviewUrl != null && p.webPreviewUrl!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                icon: const Icon(TablerIcons.external_link, size: 16),
                label: const Text('View on web'),
                onPressed: () => _launch(p.webPreviewUrl!),
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: CorexTokens.textSecondary(context)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 13, color: CorexTokens.textPrimary(context)),
          ),
        ],
      );

  Widget _description(String desc) {
    final long = desc.length > 200;
    final visible =
        !long || _descExpanded ? desc : '${desc.substring(0, 200)}…';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          visible,
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: CorexTokens.textSecondary(context),
          ),
        ),
        if (long)
          TextButton(
            onPressed: () => setState(() => _descExpanded = !_descExpanded),
            child: Text(_descExpanded ? 'Show less' : 'Read more'),
          ),
      ],
    );
  }

  Widget _agentCard(ClientPropertyAgent agent, String? branch) {
    final t = CorexAccentTheme.of(context);
    final phone = agent.phone;
    final email = agent.email;
    final whatsappPhone = phone?.replaceAll(RegExp(r'[^0-9]'), '');

    return CorexCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: t.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.accentBorder),
                ),
                alignment: Alignment.center,
                child: Icon(TablerIcons.user, color: t.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      agent.name ?? 'Your agent',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: CorexTokens.textPrimary(context),
                      ),
                    ),
                    if (branch != null && branch.isNotEmpty)
                      Text(
                        branch,
                        style: TextStyle(
                          fontSize: 12,
                          color: CorexTokens.textSecondary(context),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (phone != null && phone.isNotEmpty) ...[
            const SizedBox(height: 14),
            CorexPrimaryButton(
              label: 'Call ${agent.name?.split(' ').first ?? 'agent'}',
              leading: TablerIcons.phone,
              onPressed: () => _launch('tel:$phone'),
            ),
          ],
          if ((whatsappPhone != null && whatsappPhone.isNotEmpty) ||
              (email != null && email.isNotEmpty)) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (whatsappPhone != null && whatsappPhone.isNotEmpty)
                  Expanded(
                    child: CorexSecondaryButton(
                      label: 'WhatsApp',
                      leading: TablerIcons.brand_whatsapp,
                      onPressed: () => _launch('https://wa.me/$whatsappPhone'),
                    ),
                  ),
                if (whatsappPhone != null &&
                    whatsappPhone.isNotEmpty &&
                    email != null &&
                    email.isNotEmpty)
                  const SizedBox(width: 8),
                if (email != null && email.isNotEmpty)
                  Expanded(
                    child: CorexSecondaryButton(
                      label: 'Email',
                      leading: TablerIcons.mail,
                      onPressed: () => _launch('mailto:$email'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _money(num n) {
    final s = n.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      buf.write(s[i]);
      if (fromEnd > 1 && (fromEnd - 1) % 3 == 0) buf.write(' ');
    }
    return buf.toString();
  }
}
