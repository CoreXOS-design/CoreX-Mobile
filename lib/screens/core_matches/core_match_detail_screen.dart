import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/core_match.dart';
import '../../services/api_service.dart';
import '../../theme.dart';
import '../contacts/contact_show_screen.dart';
import 'core_match_edit_screen.dart';
import 'core_matches_common.dart';

class CoreMatchDetailScreen extends StatefulWidget {
  final int matchId;
  const CoreMatchDetailScreen({super.key, required this.matchId});

  @override
  State<CoreMatchDetailScreen> createState() => _CoreMatchDetailScreenState();
}

class _CoreMatchDetailScreenState extends State<CoreMatchDetailScreen> {
  final ApiService _api = ApiService();
  CoreMatchDetail? _detail;
  bool _loading = true;
  String? _error;
  bool _hideHidden = true;
  bool _showOtherAgents = false;
  bool _scopeBusy = false;

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
      final d = await _api.getCoreMatch(widget.matchId,
          showOtherAgents: _showOtherAgents);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _showOtherAgents = d.scope.showOtherAgents;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _setShowOtherAgents(bool value) async {
    if (_scopeBusy || value == _showOtherAgents) return;
    setState(() {
      _scopeBusy = true;
      _showOtherAgents = value;
    });
    try {
      final d = await _api.getCoreMatch(widget.matchId,
          showOtherAgents: value);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _showOtherAgents = d.scope.showOtherAgents;
        _scopeBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scopeBusy = false;
        _showOtherAgents = !value;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  Future<void> _changeStatus(String status) async {
    final prev = _detail;
    if (prev == null) return;
    try {
      await _api.setCoreMatchStatus(widget.matchId, status);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  Future<void> _toggleHide(int index) async {
    final d = _detail;
    if (d == null) return;
    final original = d.results[index];

    // Hiding a visible property: capture a reason first. The sheet performs
    // the API call itself so it can surface a 422 validation error inline.
    if (!original.hidden) {
      final result = await showModalBottomSheet<HidePropertyResult>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppTheme.surface(context),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusLarge),
          ),
        ),
        builder: (ctx) => _HideReasonSheet(
          api: _api,
          matchId: widget.matchId,
          propertyId: original.id,
        ),
      );
      if (result == null || !mounted) return;
      setState(() {
        d.results[index] = original.copyWith(
          hidden: result.hidden,
          hiddenReason: result.hiddenReason,
        );
      });
      return;
    }

    // Un-hiding: no prompt, no body — the stored reason is cleared.
    setState(() {
      d.results[index] = original.copyWith(hidden: false);
    });
    try {
      final result =
          await _api.toggleHideMatchProperty(widget.matchId, original.id);
      if (!mounted) return;
      setState(() {
        d.results[index] = original.copyWith(
          hidden: result.hidden,
          hiddenReason: result.hiddenReason,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        d.results[index] = original;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to toggle visibility: $e')),
      );
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete match?'),
        content: const Text('This match will be archived.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: kReactionNotInterested),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteCoreMatch(widget.matchId);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  Future<void> _edit() async {
    final d = _detail;
    if (d == null) return;
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CoreMatchEditScreen(match: d.match)),
    );
    if (updated == true) await _load();
  }

  void _openContact(int id) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ContactShowScreen(contactId: id)),
    );
  }

  Future<void> _sendWhatsApp() async {
    WhatsAppShare? preview;
    try {
      preview = await _api.previewMatchWhatsApp(widget.matchId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
      return;
    }
    if (!mounted) return;
    final controller = TextEditingController(text: preview.rendered);
    final template = preview.rendered;
    final hasPhone = preview.phone != null && preview.phone!.isNotEmpty;
    bool sending = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface(context),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Send to ${preview!.contactName ?? 'contact'}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasPhone ? 'Phone: ${preview.phone}' : 'No phone on contact',
                  style: TextStyle(
                    fontSize: 12,
                    color: hasPhone
                        ? AppTheme.textSecondary(context)
                        : kReactionNotInterested,
                  ),
                ),
                if (!hasPhone)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Add a phone number to this contact first.',
                      style: TextStyle(
                          fontSize: 12, color: kReactionNotInterested),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 8,
                  minLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'Message…',
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Reset to template'),
                    onPressed: () => controller.text = template,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.chat_rounded, size: 18),
                    label: Text(sending ? 'Sending…' : 'Send via WhatsApp'),
                    onPressed: (!hasPhone || sending)
                        ? null
                        : () async {
                            setSheetState(() => sending = true);
                            try {
                              final res = await _api.sendMatchWhatsApp(
                                  widget.matchId, controller.text);
                              if (!mounted) return;
                              Navigator.of(ctx).pop();
                              final link = res.waLink;
                              if (link != null && link.isNotEmpty) {
                                await launchUrl(Uri.parse(link),
                                    mode: LaunchMode.externalApplication);
                              }
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Logged WhatsApp send. whatsapp_count = ${res.whatsappCount}'),
                                ),
                              );
                              await _load();
                            } catch (e) {
                              if (!mounted) return;
                              setSheetState(() => sending = false);
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Failed: $e')),
                              );
                            }
                          },
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  Future<void> _openClientPage() async {
    final url = _detail?.match.shareUrl;
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No client page link available')),
      );
      return;
    }
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }

  void _statusMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface(context),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: kStatuses.map((s) {
            final selected = _detail?.match.status == s;
            return ListTile(
              leading: Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: statusColor(s), shape: BoxShape.circle),
              ),
              title: Text(s),
              trailing: selected
                  ? Icon(Icons.check_rounded, color: AppTheme.brand)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                if (!selected) _changeStatus(s);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Core Match'),
        actions: [
          IconButton(
            tooltip: _hideHidden ? 'Show hidden' : 'Hide hidden',
            icon: Icon(_hideHidden
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded),
            onPressed: () => setState(() => _hideHidden = !_hideHidden),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: AppTheme.brand,
          backgroundColor: AppTheme.surface(context),
          onRefresh: _load,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _detail == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _detail == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary(context))),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        ],
      );
    }
    final d = _detail!;
    final results = _hideHidden
        ? d.results.where((r) => !r.hidden).toList()
        : d.results;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _header(d),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.chat_rounded, size: 18),
            label: const Text('Send via WhatsApp'),
            onPressed: _sendWhatsApp,
          ),
        ),
        const SizedBox(height: 12),
        _filterChips(d.match),
        const SizedBox(height: 12),
        _actionRow(d),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'Results (${results.length})',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ),
            if (d.scope.allowCrossAgent) _scopeToggle(),
          ],
        ),
        const SizedBox(height: 8),
        if (_scopeBusy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (results.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            decoration: BoxDecoration(
              color: AppTheme.surface(context),
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: AppTheme.borderColor(context)),
            ),
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.brand.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.home_outlined,
                      color: AppTheme.brand, size: 22),
                ),
                const SizedBox(height: 10),
                Text(
                  'No results to show',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  d.results.any((r) => r.hidden)
                      ? 'Every match is hidden. Unhide a property to see it here.'
                      : 'Nothing scored 50% or higher for this match. '
                          'Adjust the filters to widen the search.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
        if (!_scopeBusy) ..._resultsWithHeaders(results, d),
      ],
    );
  }

  Widget _header(CoreMatchDetail d) {
    final c = d.contact;
    final m = d.match;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _openContact(c.id),
            child: Row(
              children: [
                Icon(Icons.person_rounded,
                    size: 16, color: AppTheme.textSecondary(context)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    c.fullName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                ),
                if (c.phone != null && c.phone!.isNotEmpty)
                  Text(
                    c.phone!,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.brand,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  m.displayName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              statusPill(m.status),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChips(CoreMatch m) {
    final chips = <String>[];
    if (m.priceMin != null || m.priceMax != null) {
      final lo = m.priceMin == null ? '' : 'R${CoreMatchSummary.fmtPrice(m.priceMin!)}';
      final hi = m.priceMax == null ? '' : 'R${CoreMatchSummary.fmtPrice(m.priceMax!)}';
      chips.add('$lo–$hi');
    }
    if (m.bedsMin != null) chips.add('${m.bedsMin}+ beds');
    if (m.bathsMin != null) chips.add('${m.bathsMin}+ baths');
    if (m.garagesMin != null) chips.add('${m.garagesMin}+ garages');
    for (final s in m.suburbs) {
      chips.add(s);
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips.map((c) => _chip(c)).toList(),
    );
  }

  Widget _scopeToggle() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _scopePill('My properties only', !_showOtherAgents,
              () => _setShowOtherAgents(false)),
          _scopePill('Include other agents', _showOtherAgents,
              () => _setShowOtherAgents(true)),
        ],
      ),
    );
  }

  Widget _scopePill(String label, bool active, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radius),
      onTap: _scopeBusy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppTheme.brand : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppTheme.textSecondary(context),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.surface2(context),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary(context),
          ),
        ),
      );

  Widget _actionRow(CoreMatchDetail d) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _actionBtn(Icons.edit_rounded, 'Edit', _edit),
        _actionBtn(Icons.tune_rounded, 'Status', _statusMenu),
        _actionBtn(Icons.person_rounded, 'Open Contact',
            () => _openContact(d.contact.id)),
        _actionBtn(Icons.open_in_new_rounded, 'Client Page', _openClientPage),
        _actionBtn(Icons.delete_outline_rounded, 'Delete', _delete,
            danger: true),
      ],
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap,
      {bool danger = false}) {
    final c = danger ? kReactionNotInterested : AppTheme.textPrimary(context);
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radius),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface(context),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: c)),
          ],
        ),
      ),
    );
  }

  /// Builds the result tiles, inserting tier section headers ("Strong
  /// matches", etc.) whenever the tier changes. Results arrive already
  /// sorted best-first by the API, so a single pass is enough. Legacy
  /// payloads with no scores fall back to a plain, header-less list.
  List<Widget> _resultsWithHeaders(
      List<CoreMatchResult> results, CoreMatchDetail d) {
    final scored = results.any((r) => r.matchScore != null);
    final widgets = <Widget>[];
    String? currentTier;
    for (final r in results) {
      final i = d.results.indexWhere((x) => x.id == r.id);
      if (scored) {
        final tier = tierLabel(r.matchTier, score: r.matchScore);
        if (tier != currentTier) {
          currentTier = tier;
          widgets.add(_tierHeader(tier));
        }
      }
      widgets.add(_resultTile(r, i));
    }
    return widgets;
  }

  Widget _tierHeader(String label) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary(context),
          ),
        ),
      );

  Widget _resultTile(CoreMatchResult r, int absoluteIndex) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            child: SizedBox(
              width: 64,
              height: 64,
              child: r.thumbnail != null && r.thumbnail!.isNotEmpty
                  ? Image.network(
                      r.thumbnail!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppTheme.surface2(context),
                        child: Icon(Icons.home_rounded,
                            color: AppTheme.textMuted(context)),
                      ),
                    )
                  : Container(
                      color: AppTheme.surface2(context),
                      child: Icon(Icons.home_rounded,
                          color: AppTheme.textMuted(context)),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        r.address ?? 'Property',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                    ),
                    if (r.matchScore != null) ...[
                      const SizedBox(width: 6),
                      matchScoreBadge(r.matchScore!, r.matchTier),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (r.beds != null) '${r.beds} bed',
                    if (r.baths != null) '${r.baths} bath',
                    if (r.garages != null) '${r.garages} garage',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (r.priceDisplay != null && r.priceDisplay!.isNotEmpty)
                      Text(
                        r.priceDisplay!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.brand,
                        ),
                      ),
                    if (r.reaction != null) ...[
                      const SizedBox(width: 8),
                      reactionBadge(r.reaction!),
                    ],
                  ],
                ),
                if (r.reactionNote != null && r.reactionNote!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      r.reactionNote!,
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: AppTheme.textMuted(context),
                      ),
                    ),
                  ),
                if (r.hidden &&
                    r.hiddenReason != null &&
                    r.hiddenReason!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.visibility_off_rounded,
                            size: 12, color: AppTheme.textMuted(context)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Hidden: ${r.hiddenReason!}',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textMuted(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: r.hidden ? 'Unhide' : 'Hide',
            icon: Icon(
              r.hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
              size: 18,
              color: AppTheme.textSecondary(context),
            ),
            onPressed: () => _toggleHide(absoluteIndex),
          ),
        ],
      ),
    );
  }
}

/// CoreX-styled slide-up sheet that asks the agent why they're hiding a
/// property from a Core Match. Performs the hide API call itself so a 422
/// validation error is shown inline. Pops with a [HidePropertyResult] on
/// success, or `null` on cancel.
class _HideReasonSheet extends StatefulWidget {
  final ApiService api;
  final int matchId;
  final int propertyId;

  const _HideReasonSheet({
    required this.api,
    required this.matchId,
    required this.propertyId,
  });

  @override
  State<_HideReasonSheet> createState() => _HideReasonSheetState();
}

class _HideReasonSheetState extends State<_HideReasonSheet> {
  static const int _minChars = 3;
  static const int _maxChars = 500;

  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => _controller.text.trim().length >= _minChars;

  Future<void> _confirm() async {
    if (!_valid || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.api.toggleHideMatchProperty(
        widget.matchId,
        widget.propertyId,
        reason: _controller.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on ValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.fieldErrors['reason'] ?? e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Failed to hide property. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle.
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.borderColor(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Icon(Icons.visibility_off_rounded,
                  size: 20, color: AppTheme.textPrimary(context)),
              const SizedBox(width: 8),
              Text(
                'Hide property',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Why are you hiding this property from this match?',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_busy,
            minLines: 3,
            maxLines: 5,
            maxLength: _maxChars,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Add a reason (at least $_minChars characters)',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: (_valid && !_busy) ? _confirm : null,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Hide property'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
