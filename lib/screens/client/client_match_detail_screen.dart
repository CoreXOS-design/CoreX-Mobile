import 'package:flutter/material.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../models/client_models.dart';
import '../../screens/core_matches/core_matches_common.dart';
import '../../services/api_service.dart' show ApiException;
import '../../services/client_auth_service.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../widgets/client/client_property_card.dart';
import '../../widgets/client/not_for_me_sheet.dart';
import '../../widgets/corex/corex_chip.dart';
import '../../widgets/corex/corex_scaffold.dart';
import '../../widgets/corex/corex_secondary_button.dart';
import 'client_match_edit_screen.dart';
import 'client_property_screen.dart';

class ClientMatchDetailScreen extends StatefulWidget {
  final int matchId;
  const ClientMatchDetailScreen({super.key, required this.matchId});

  @override
  State<ClientMatchDetailScreen> createState() =>
      _ClientMatchDetailScreenState();
}

class _ClientMatchDetailScreenState extends State<ClientMatchDetailScreen> {
  final _api = ClientAuthService();

  bool _loading = true;
  String? _error;
  ClientMatchDetail? _detail;
  bool _hideRejected = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _api.matchDetail(widget.matchId);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 403) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("This match isn't yours")),
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
        _error = 'Could not load match. Pull to retry.';
      });
    }
  }

  Future<void> _edit() async {
    final d = _detail;
    if (d == null) return;
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ClientMatchEditScreen(existing: d.match),
      ),
    );
    if (updated == true) await _load();
  }

  void _openProperty(ClientMatchResult r) {
    // Fire-and-forget view ping.
    _api.postView(matchId: widget.matchId, propertyId: r.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientPropertyScreen(
          propertyId: r.id,
          matchId: widget.matchId,
          initialReaction: r.reaction,
          initialReactionNote: r.reactionNote,
          onReactionChanged: (reaction, note) {
            _applyReactionLocal(r.id, reaction, note);
          },
        ),
      ),
    );
  }

  void _applyReactionLocal(int propertyId, String reaction, String? note) {
    final d = _detail;
    if (d == null) return;
    final idx = d.results.indexWhere((x) => x.id == propertyId);
    if (idx < 0) return;
    setState(() {
      d.results[idx] = d.results[idx].copyWith(
        reaction: reaction,
        reactionNote: note,
        clearReactionNote: reaction != 'not_interested',
      );
      _detail = ClientMatchDetail(
        match: _bumpFeedback(d.match, d.results),
        results: d.results,
      );
    });
  }

  ClientMatch _bumpFeedback(ClientMatch m, List<ClientMatchResult> rs) {
    int i = 0, n = 0, s = 0;
    for (final r in rs) {
      switch (r.reaction) {
        case 'interested':
          i++;
          break;
        case 'not_interested':
          n++;
          break;
        case 'saved':
          s++;
          break;
      }
    }
    return ClientMatch(
      id: m.id,
      name: m.name,
      status: m.status,
      listingType: m.listingType,
      createdAt: m.createdAt,
      updatedAt: m.updatedAt,
      lastEngagedAt: DateTime.now().toIso8601String(),
      feedbackSummary: ClientFeedbackSummary(
          interested: i, notInterested: n, saved: s),
      category: m.category,
      propertyType: m.propertyType,
      priceMin: m.priceMin,
      priceMax: m.priceMax,
      bedsMin: m.bedsMin,
      bathsMin: m.bathsMin,
      garagesMin: m.garagesMin,
      suburb: m.suburb,
      suburbs: m.suburbs,
      mustHaveFeatures: m.mustHaveFeatures,
      notes: m.notes,
    );
  }

  Future<void> _react(ClientMatchResult r, String reaction) async {
    String? note;
    if (reaction == 'not_interested') {
      final entered = await showNotForMeSheet(context,
          initialNote: r.reactionNote);
      if (entered == null) return; // cancelled
      note = entered;
    }

    final original = r;
    _applyReactionLocal(r.id, reaction, note);

    try {
      await _api.postFeedback(
        matchId: widget.matchId,
        propertyId: r.id,
        reaction: reaction,
        note: note,
      );
    } catch (e) {
      if (!mounted) return;
      // Rollback on error.
      _applyReactionLocal(
          original.id, original.reaction ?? '', original.reactionNote);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    return CorexScaffold(
      title: _detail?.match.name ?? 'My match',
      actions: [
        IconButton(
          tooltip: _hideRejected ? 'Show rejected' : 'Hide rejected',
          icon: Icon(
            _hideRejected ? TablerIcons.eye_off : TablerIcons.eye,
            color: CorexTokens.textPrimary(context),
          ),
          onPressed: _detail == null
              ? null
              : () => setState(() => _hideRejected = !_hideRejected),
        ),
        IconButton(
          tooltip: 'Edit search',
          icon: Icon(TablerIcons.adjustments_horizontal,
              color: CorexTokens.textPrimary(context)),
          onPressed: _detail == null ? null : _edit,
        ),
      ],
      body: RefreshIndicator(
        color: t.accent,
        backgroundColor: CorexTokens.surfaceTop(context),
        onRefresh: _load,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading && _detail == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _detail == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 64),
          Icon(TablerIcons.alert_circle,
              size: 48, color: CorexTokens.textTertiary(context)),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: CorexTokens.textSecondary(context)),
          ),
        ],
      );
    }

    final d = _detail!;
    final m = d.match;
    final visible = _hideRejected
        ? d.results.where((r) => r.reaction != 'not_interested').toList()
        : d.results;
    final total = d.results.length;
    final fb = m.feedbackSummary;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                m.name ?? 'My match',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: CorexTokens.textPrimary(context),
                ),
              ),
            ),
            statusPill(m.status),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${fb.interested}/$total interested',
          style: TextStyle(
            fontSize: 12,
            color: CorexTokens.textSecondary(context),
          ),
        ),
        const SizedBox(height: 10),
        _filterChips(m),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(TablerIcons.eye_off,
                size: 16, color: CorexTokens.textSecondary(context)),
            const SizedBox(width: 6),
            Text(
              'Hide rejected',
              style: TextStyle(
                  fontSize: 13, color: CorexTokens.textSecondary(context)),
            ),
            const Spacer(),
            Switch(
              value: _hideRejected,
              activeTrackColor: CorexAccentTheme.of(context).accent,
              onChanged: (v) => setState(() => _hideRejected = v),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                Icon(TablerIcons.search_off,
                    size: 48, color: CorexTokens.textTertiary(context)),
                const SizedBox(height: 12),
                Text(
                  'No properties match yet',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: CorexTokens.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Try widening your filters.',
                  style: TextStyle(
                    fontSize: 13,
                    color: CorexTokens.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 200,
                  child: CorexSecondaryButton(
                    label: 'Edit search',
                    leading: TablerIcons.adjustments_horizontal,
                    onPressed: _edit,
                  ),
                ),
              ],
            ),
          )
        else
          ...visible.map((r) => ClientPropertyCard(
                result: r,
                onTap: () => _openProperty(r),
                onReact: (reaction) => _react(r, reaction),
              )),
      ],
    );
  }

  Widget _filterChips(ClientMatch m) {
    final chips = <String>[];
    if (m.priceMin != null || m.priceMax != null) {
      String fmt(num? v) {
        if (v == null) return '';
        final n = v.toDouble();
        if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}m';
        if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}k';
        return n.toStringAsFixed(0);
      }
      final lo = fmt(m.priceMin);
      final hi = fmt(m.priceMax);
      chips.add(
          lo.isEmpty ? 'R up to $hi' : (hi.isEmpty ? 'R from $lo' : 'R $lo–$hi'));
    }
    if (m.bedsMin != null && m.bedsMin! > 0) chips.add('${m.bedsMin}+ beds');
    if (m.bathsMin != null && m.bathsMin! > 0) chips.add('${m.bathsMin}+ baths');

    final subs = m.suburbs;
    if (subs.isNotEmpty) {
      if (subs.length <= 2) {
        chips.addAll(subs);
      } else {
        chips.add(subs[0]);
        chips.add(subs[1]);
        chips.add('+${subs.length - 2}');
      }
    } else if (m.suburb != null && m.suburb!.isNotEmpty) {
      chips.add(m.suburb!);
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips
          .map((c) => GestureDetector(
                onTap: _edit,
                child: CorexChip(label: c),
              ))
          .toList(),
    );
  }
}
