import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../models/client_models.dart';
import '../../providers/client_session_provider.dart';
import '../../screens/core_matches/core_matches_common.dart';
import '../../services/api_service.dart' show ApiException;
import '../../services/client_auth_service.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../widgets/corex/corex_card.dart';
import '../../widgets/corex/corex_chip.dart';
import '../../widgets/corex/corex_primary_button.dart';
import '../../widgets/corex/corex_scaffold.dart';
import '../auth/client/client_agency_picker_screen.dart';
import 'client_match_detail_screen.dart';
import 'client_match_edit_screen.dart';

class ClientMatchesListScreen extends StatefulWidget {
  const ClientMatchesListScreen({super.key});

  @override
  State<ClientMatchesListScreen> createState() =>
      _ClientMatchesListScreenState();
}

class _ClientMatchesListScreenState extends State<ClientMatchesListScreen> {
  final _api = ClientAuthService();

  bool _loading = true;
  String? _error;
  List<ClientMatch> _matches = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final session = context.read<ClientSessionProvider>();
    await session.refreshMe();
    if (!mounted) return;

    try {
      final result = await _api.matches();
      if (!mounted) return;
      setState(() {
        _matches = result.matches;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) {
        await session.signOutLocal();
        return;
      }
      if (e.statusCode == 409) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ClientAgencyPickerScreen(initialPick: true),
          ),
        );
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
        _error = 'Could not load matches. Pull to retry.';
      });
    }
  }

  Future<void> _createMatch() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ClientMatchEditScreen()),
    );
    if (created == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    return CorexScaffold(
      title: 'Core Matches',
      floatingActionButton: _matches.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _createMatch,
              backgroundColor: t.accent,
              foregroundColor: Colors.white,
              icon: const Icon(TablerIcons.plus),
              label: const Text('New search'),
            ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: t.accent,
          backgroundColor: CorexTokens.surfaceTop(context),
          onRefresh: _refresh,
          child: _body(),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading && _matches.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _matches.isEmpty) {
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
          const SizedBox(height: 16),
          Center(
            child: TextButton(onPressed: _refresh, child: const Text('Retry')),
          ),
        ],
      );
    }
    if (_matches.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 72),
          Icon(TablerIcons.search,
              size: 56, color: CorexTokens.textTertiary(context)),
          const SizedBox(height: 16),
          Text(
            'Tell us what you\'re looking for',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: CorexTokens.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Set up your search and we\'ll match you with properties as soon as they hit our books.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: CorexTokens.textSecondary(context),
            ),
          ),
          const SizedBox(height: 24),
          CorexPrimaryButton(
            label: 'Set up my search',
            leading: TablerIcons.adjustments_horizontal,
            onPressed: _createMatch,
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _matches.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _MatchCard(
        match: _matches[i],
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ClientMatchDetailScreen(matchId: _matches[i].id),
            ),
          );
          if (mounted) _refresh();
        },
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  final ClientMatch match;
  final VoidCallback onTap;
  const _MatchCard({required this.match, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fb = match.feedbackSummary;
    return CorexCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _title(match),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: CorexTokens.textPrimary(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              statusPill(match.status),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (match.priceMin != null || match.priceMax != null)
                CorexChip(
                  label: _priceRange(match),
                  variant: CorexChipVariant.money,
                ),
              if (match.bedsMin != null && match.bedsMin! > 0)
                CorexChip(label: '${match.bedsMin}+ beds'),
              if (match.suburb != null && match.suburb!.isNotEmpty)
                CorexChip(label: match.suburb!)
              else if (match.suburbs.isNotEmpty)
                CorexChip(label: match.suburbs.first),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _tally(
                  Icons.favorite_rounded, kReactionInterested, fb.interested),
              const SizedBox(width: 12),
              _tally(Icons.star_rounded, kReactionSaved, fb.saved),
              const SizedBox(width: 12),
              _tally(Icons.close_rounded, kReactionNotInterested,
                  fb.notInterested),
              const Spacer(),
              Text(
                _relative(
                    match.lastEngagedAt ?? match.updatedAt ?? match.createdAt),
                style: TextStyle(
                  fontSize: 11,
                  color: CorexTokens.textTertiary(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _title(ClientMatch m) {
    if (m.name != null && m.name!.trim().isNotEmpty) return m.name!;
    final lt = (m.listingType ?? '').toLowerCase();
    if (lt == 'rental') return 'Rental search';
    if (lt == 'sale') return 'Buy search';
    return 'My search';
  }

  String _priceRange(ClientMatch m) {
    String fmt(num? v) {
      if (v == null) return '';
      final n = v.toDouble();
      if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}m';
      if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}k';
      return n.toStringAsFixed(0);
    }

    final lo = fmt(m.priceMin);
    final hi = fmt(m.priceMax);
    if (lo.isEmpty && hi.isEmpty) return '';
    if (lo.isEmpty) return 'R up to $hi';
    if (hi.isEmpty) return 'R from $lo';
    return 'R $lo–$hi';
  }

  Widget _tally(IconData icon, Color color, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text('$count',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }

  String _relative(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }
}
