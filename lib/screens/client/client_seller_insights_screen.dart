import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/seller_models.dart';
import '../../providers/client_session_provider.dart';
import '../../services/api_service.dart' show ApiException;
import '../../services/client_auth_service.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../widgets/corex/corex_card.dart';
import '../../widgets/corex/corex_chip.dart';
import '../../widgets/corex/corex_kpi_tile.dart';
import '../../widgets/corex/corex_scaffold.dart';
import '../auth/client/client_agency_picker_screen.dart';
import 'client_seller_common.dart';

/// The full seller dashboard for one listing — mirrors the CoreX seller live
/// page layout. Pull-to-refresh re-calls the insights endpoint.
class ClientSellerInsightsScreen extends StatefulWidget {
  final int propertyId;
  const ClientSellerInsightsScreen({super.key, required this.propertyId});

  @override
  State<ClientSellerInsightsScreen> createState() =>
      _ClientSellerInsightsScreenState();
}

class _ClientSellerInsightsScreenState
    extends State<ClientSellerInsightsScreen> {
  final _api = ClientAuthService();

  bool _loading = true;
  String? _error;
  SellerPropertyInsights? _data;

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
    final session = context.read<ClientSessionProvider>();
    try {
      final data = await _api.sellerPropertyInsights(widget.propertyId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) {
        await session.signOutLocal();
        return;
      }
      if (e.statusCode == 404) {
        // Not seller-linked (or unlinked since the list loaded) — pop to list.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This listing is no longer available')),
        );
        Navigator.of(context).pop();
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
        _error = 'Could not load this listing. Pull to retry.';
      });
    }
  }

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    return CorexScaffold(
      title: 'Listing insights',
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: t.accent,
          backgroundColor: CorexTokens.surfaceTop(context),
          onRefresh: _load,
          child: _body(),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _data == null) {
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
            child: TextButton(onPressed: _load, child: const Text('Retry')),
          ),
        ],
      );
    }

    final d = _data!;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _header(d),
        const SizedBox(height: 16),
        _performance(d.performance),
        ..._agentInsights(d.agentInsights),
        const SizedBox(height: 16),
        _feedbackSummary(d.feedbackSummary),
        ..._marketingActivity(d.marketingActivity),
        ..._comparables(d.comparables),
        ..._presentation(d.presentation),
        const SizedBox(height: 16),
        _listingStatus(d.listingStatus),
        ..._agentFooter(d.agent),
        if (d.lastRefreshedAt != null && d.lastRefreshedAt!.isNotEmpty) ...[
          const SizedBox(height: 20),
          Center(
            child: Text(
              'Last updated ${_lastUpdated(d.lastRefreshedAt!)}',
              style: TextStyle(
                fontSize: 11,
                color: CorexTokens.textTertiary(context),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // -------------------- Header --------------------

  Widget _header(SellerPropertyInsights d) {
    final p = d.property;
    final t = CorexAccentTheme.of(context);
    final title = (p.title != null && p.title!.trim().isNotEmpty)
        ? p.title!
        : (p.address ?? 'Listing');

    return CorexCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (p.thumbnail != null && p.thumbnail!.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  p.thumbnail!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: CorexTokens.surfaceTop(context),
                    child: Icon(TablerIcons.photo_off,
                        color: CorexTokens.textTertiary(context)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: CorexTokens.textPrimary(context),
                      ),
                    ),
                    if (p.address != null && p.address!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          p.address!,
                          style: TextStyle(
                            fontSize: 12,
                            color: CorexTokens.textSecondary(context),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (d.agency?.logoUrl != null &&
                  d.agency!.logoUrl!.isNotEmpty) ...[
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    d.agency!.logoUrl!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (p.priceDisplay != null && p.priceDisplay!.isNotEmpty)
            Text(
              p.priceDisplay!,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: t.accentMoney,
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              if (p.propertyType != null && p.propertyType!.isNotEmpty)
                _spec(TablerIcons.home, p.propertyType!),
              if (p.beds != null) _spec(TablerIcons.bed, '${p.beds} bd'),
              if (p.baths != null) _spec(TablerIcons.bath, '${p.baths} ba'),
              if (p.garages != null)
                _spec(TablerIcons.car, '${p.garages} garage'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _spec(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: CorexTokens.textSecondary(context)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 12, color: CorexTokens.textPrimary(context)),
          ),
        ],
      );

  // -------------------- Performance (2×2 grid) --------------------

  Widget _performance(SellerPerformance perf) {
    final tiles = <Widget>[
      CorexKpiTile(label: 'Viewings', value: '${perf.viewings ?? 0}'),
      CorexKpiTile(label: 'Days Listed', value: '${perf.daysOnMarket ?? 0}'),
      if (perf.marketValue != null)
        CorexKpiTile(
          label: 'Market Value',
          value: sellerMoney(perf.marketValue!),
          money: true,
        ),
      if (perf.areaAverage != null)
        CorexKpiTile(
          label: 'Area Average',
          value: sellerMoney(perf.areaAverage!),
          money: true,
        ),
    ];

    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: 10));
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: tiles[i]),
          const SizedBox(width: 10),
          Expanded(
            child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox(),
          ),
        ],
      ));
    }
    return Column(children: rows);
  }

  // -------------------- Agent insights --------------------

  List<Widget> _agentInsights(List<SellerAgentInsight> insights) {
    if (insights.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      _sectionTitle('Agent Insights', TablerIcons.bulb),
      const SizedBox(height: 10),
      for (final ins in insights)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: CorexCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (ins.title != null && ins.title!.isNotEmpty)
                  Text(
                    ins.title!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: CorexTokens.textPrimary(context),
                    ),
                  ),
                if (ins.reasoning != null && ins.reasoning!.isNotEmpty) ...[
                  if (ins.title != null && ins.title!.isNotEmpty)
                    const SizedBox(height: 4),
                  Text(
                    ins.reasoning!,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: CorexTokens.textSecondary(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
    ];
  }

  // -------------------- Viewing feedback summary --------------------

  Widget _feedbackSummary(SellerFeedbackSummary fb) {
    return CorexCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _inlineSectionTitle('Viewing Feedback', TablerIcons.message_2),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _miniStat(
                    '${fb.totalViewings}', 'Viewings logged'),
              ),
              Expanded(
                child: _miniStat(
                    '${fb.totalFeedbackRows}', 'Feedback notes'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: CorexTokens.textPrimary(context),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: CorexTokens.textSecondary(context),
          ),
        ),
      ],
    );
  }

  // -------------------- Marketing activity --------------------

  List<Widget> _marketingActivity(List<SellerMarketingActivity> items) {
    if (items.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      _sectionTitle('Marketing Activity', TablerIcons.speakerphone),
      const SizedBox(height: 10),
      CorexCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(color: Color(0x14FFFFFF), height: 1),
                ),
              _timelineRow(items[i]),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _timelineRow(SellerMarketingActivity item) {
    final t = CorexAccentTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            item.label ?? item.type ?? '',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: CorexTokens.textPrimary(context),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (item.date != null && item.date!.isNotEmpty)
          Text(
            _shortDate(item.date!),
            style: TextStyle(
              fontSize: 11,
              color: CorexTokens.textTertiary(context),
            ),
          ),
      ],
    );
  }

  // -------------------- Comparables --------------------

  List<Widget> _comparables(List<SellerComparable> items) {
    if (items.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      _sectionTitle('Similar Properties', TablerIcons.building_estate),
      const SizedBox(height: 10),
      for (final c in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: CorexCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.title ?? 'Comparable listing',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: CorexTokens.textPrimary(context),
                        ),
                      ),
                      if (c.suburb != null && c.suburb!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          c.suburb!,
                          style: TextStyle(
                            fontSize: 12,
                            color: CorexTokens.textSecondary(context),
                          ),
                        ),
                      ],
                      if (c.daysOnMarket != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${c.daysOnMarket} days on market',
                          style: TextStyle(
                            fontSize: 11,
                            color: CorexTokens.textTertiary(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (c.priceDisplay != null && c.priceDisplay!.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Text(
                    c.priceDisplay!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: CorexAccentTheme.of(context).accentMoney,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
    ];
  }

  // -------------------- Market presentation --------------------

  List<Widget> _presentation(SellerPresentation? pres) {
    if (pres == null) return const [];
    return [
      const SizedBox(height: 16),
      _sectionTitle('Market Presentation', TablerIcons.presentation),
      const SizedBox(height: 10),
      CorexCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(TablerIcons.file_text,
                size: 22, color: CorexAccentTheme.of(context).accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pres.title ?? 'Market presentation',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: CorexTokens.textPrimary(context),
                    ),
                  ),
                  if (pres.generatedAt != null &&
                      pres.generatedAt!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Generated ${_shortDate(pres.generatedAt!)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: CorexTokens.textSecondary(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  // -------------------- Listing status --------------------

  Widget _listingStatus(SellerListingStatus s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Listing Status', TablerIcons.checkup_list),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            CorexChip(
              label: s.published ? 'Active' : 'Unpublished',
              variant:
                  s.published ? CorexChipVariant.accent : CorexChipVariant.neutral,
            ),
            CorexChip(
              label: s.mandateActive ? 'Mandate active' : 'Review needed',
              variant: s.mandateActive
                  ? CorexChipVariant.accent
                  : CorexChipVariant.neutral,
            ),
          ],
        ),
      ],
    );
  }

  // -------------------- Agent footer --------------------

  List<Widget> _agentFooter(SellerAgent? agent) {
    if (agent == null) return const [];
    final email = agent.email;
    final phone = agent.phone;
    return [
      const SizedBox(height: 16),
      CorexCard(
        accent: true,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Questions? Contact your agent',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: CorexTokens.textPrimary(context),
              ),
            ),
            if (agent.name != null && agent.name!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                agent.name!,
                style: TextStyle(
                  fontSize: 13,
                  color: CorexTokens.textSecondary(context),
                ),
              ),
            ],
            if ((email != null && email.isNotEmpty) ||
                (phone != null && phone.isNotEmpty)) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (phone != null && phone.isNotEmpty)
                    Expanded(
                      child: _contactButton(
                        icon: TablerIcons.phone,
                        label: 'Call',
                        onTap: () => _launch('tel:$phone'),
                      ),
                    ),
                  if (phone != null &&
                      phone.isNotEmpty &&
                      email != null &&
                      email.isNotEmpty)
                    const SizedBox(width: 8),
                  if (email != null && email.isNotEmpty)
                    Expanded(
                      child: _contactButton(
                        icon: TablerIcons.mail,
                        label: 'Email',
                        onTap: () => _launch('mailto:$email'),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _contactButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final t = CorexAccentTheme.of(context);
    return Material(
      color: t.accentSoft,
      borderRadius: BorderRadius.circular(CorexTokens.radiusButton),
      child: InkWell(
        borderRadius: BorderRadius.circular(CorexTokens.radiusButton),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: t.accent),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: t.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------- Shared bits --------------------

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: CorexAccentTheme.of(context).accent),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: CorexTokens.textPrimary(context),
          ),
        ),
      ],
    );
  }

  Widget _inlineSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: CorexAccentTheme.of(context).accent),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: CorexTokens.textPrimary(context),
          ),
        ),
      ],
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _shortDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
  }

  String _lastUpdated(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return _shortDate(iso);
  }
}
