import 'package:flutter/material.dart';
import '../../models/core_match.dart';
import '../../services/api_service.dart';
import '../../theme.dart';
import '../../widgets/ui/glow_button.dart';
import '../../widgets/ui/list_row.dart';
import '../contacts/contact_show_screen.dart';
import 'core_match_detail_screen.dart';
import 'core_matches_common.dart';

class CoreMatchesListScreen extends StatefulWidget {
  const CoreMatchesListScreen({super.key});

  @override
  State<CoreMatchesListScreen> createState() => _CoreMatchesListScreenState();
}

class _CoreMatchesListScreenState extends State<CoreMatchesListScreen> {
  final ApiService _api = ApiService();
  List<CoreMatchGroup> _groups = const [];
  bool _loading = true;
  String? _error;

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
      final groups = await _api.listCoreMatches();
      if (!mounted) return;
      setState(() {
        _groups = groups;
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

  void _openMatch(int id) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CoreMatchDetailScreen(matchId: id)),
    ).then((_) => _load());
  }

  void _openContact(int id) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ContactShowScreen(contactId: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Core Matches')),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: Theme.of(context).colorScheme.primary,
          backgroundColor: AppTheme.surface(context),
          onRefresh: _load,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _groups.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _groups.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Could not load matches',
            subtitle: _error,
            action: SizedBox(
              width: 180,
              child: GlowButton(
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ),
          ),
        ],
      );
    }
    if (_groups.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          EmptyState(
            icon: Icons.favorite_rounded,
            title: 'No core matches yet',
            subtitle:
                'Create one from a contact to start tracking buyer criteria.',
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _groups.length,
      itemBuilder: (_, i) => _groupSection(_groups[i]),
    );
  }

  Widget _groupSection(CoreMatchGroup g) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: ListRow(
            icon: Icons.person_rounded,
            title: g.contact.fullName,
            subtitle: g.contact.phone?.isNotEmpty == true
                ? g.contact.phone
                : null,
            showChevron: true,
            onTap: () => _openContact(g.contact.id),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        for (final m in g.matches)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _matchTile(m),
          ),
      ],
    );
  }

  Widget _matchTile(CoreMatchSummary m) {
    final fs = m.feedbackSummary;
    return ListRow(
      icon: Icons.favorite_rounded,
      title: m.displayName,
      onTap: () => _openMatch(m.id),
      showChevron: true,
      trailing: statusPill(m.status),
      subtitle: null,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      leading: null,
    ).withFooter(
      context,
      Row(
        children: [
          _counter(kReactionInterested, fs.interested),
          const SizedBox(width: 14),
          _counter(kReactionNotInterested, fs.notInterested),
          const SizedBox(width: 14),
          _counter(kReactionSaved, fs.saved),
        ],
      ),
    );
  }

  Widget _counter(Color c, int n) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: c.withValues(alpha: 0.6),
                  blurRadius: 6,
                  spreadRadius: -1),
            ],
          ),
        ),
        const SizedBox(width: 5),
        Text(
          '$n',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary(context),
          ),
        ),
      ],
    );
  }
}

// Helper extension: wrap a ListRow with a small footer (reaction counters).
// We keep ListRow itself generic and stitch the counters underneath without
// breaking the shared widget.
extension on ListRow {
  Widget withFooter(BuildContext context, Widget footer) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: AppTheme.softShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    trailing!,
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded,
                        size: 20, color: AppTheme.textMuted(context)),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: footer,
          ),
        ],
      ),
    );
  }
}
