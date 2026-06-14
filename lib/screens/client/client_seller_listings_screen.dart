import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../models/seller_models.dart';
import '../../providers/client_session_provider.dart';
import '../../services/api_service.dart' show ApiException;
import '../../services/client_auth_service.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../widgets/corex/corex_card.dart';
import '../../widgets/corex/corex_scaffold.dart';
import '../auth/client/client_agency_picker_screen.dart';
import 'client_seller_common.dart';
import 'client_seller_insights_screen.dart';

/// Opens the seller dashboard from a nav entry. Deep-links straight into the
/// insights detail when the client has exactly one listing; otherwise shows the
/// list. Callers pass the already-probed [properties] (e.g. from
/// [SellerListingsProvider]) so the common single-listing case skips a screen.
void openSellerDashboard(
    BuildContext context, List<SellerProperty> properties) {
  if (properties.length == 1) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ClientSellerInsightsScreen(propertyId: properties.first.id),
      ),
    );
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const ClientSellerListingsScreen()),
  );
}

/// "My Listings" — the seller's properties in their current agency. One card
/// per listing with thumbnail, status pill, and the two headline stats.
class ClientSellerListingsScreen extends StatefulWidget {
  const ClientSellerListingsScreen({super.key});

  @override
  State<ClientSellerListingsScreen> createState() =>
      _ClientSellerListingsScreenState();
}

class _ClientSellerListingsScreenState
    extends State<ClientSellerListingsScreen> {
  final _api = ClientAuthService();

  bool _loading = true;
  String? _error;
  List<SellerProperty> _properties = const [];

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

    try {
      final result = await _api.sellerProperties();
      if (!mounted) return;
      setState(() {
        _properties = result.properties;
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
        _error = 'Could not load your listings. Pull to retry.';
      });
    }
  }

  void _openInsights(int propertyId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientSellerInsightsScreen(propertyId: propertyId),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    return CorexScaffold(
      title: 'My Listings',
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
    if (_loading && _properties.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _properties.isEmpty) {
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
    if (_properties.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 72),
          Icon(TablerIcons.home_off,
              size: 56, color: CorexTokens.textTertiary(context)),
          const SizedBox(height: 16),
          Text(
            'No listings yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: CorexTokens.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'When your agent links you to a property as the seller, its live '
            'marketing stats will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: CorexTokens.textSecondary(context),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _properties.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _ListingCard(
        property: _properties[i],
        onTap: () => _openInsights(_properties[i].id),
      ),
    );
  }
}

class _ListingCard extends StatelessWidget {
  final SellerProperty property;
  final VoidCallback onTap;
  const _ListingCard({required this.property, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = property;
    final title = (p.title != null && p.title!.trim().isNotEmpty)
        ? p.title!
        : (p.address ?? 'Listing');

    return CorexCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Thumb(url: p.thumbnail),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
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
                    sellerStatusPill(p.status),
                  ],
                ),
                if (p.suburb != null && p.suburb!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    p.suburb!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: CorexTokens.textSecondary(context),
                    ),
                  ),
                ],
                if (p.priceDisplay != null && p.priceDisplay!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    p.priceDisplay!,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: CorexAccentTheme.of(context).accentMoney,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    _headlineStat(context, TablerIcons.eye,
                        '${p.headline.viewings ?? 0}', 'viewings'),
                    const SizedBox(width: 16),
                    _headlineStat(context, TablerIcons.calendar_stats,
                        '${p.headline.daysOnMarket ?? 0}', 'days listed'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headlineStat(
      BuildContext context, IconData icon, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: CorexTokens.textTertiary(context)),
        const SizedBox(width: 5),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: CorexTokens.textPrimary(context),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: CorexTokens.textTertiary(context),
          ),
        ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  final String? url;
  const _Thumb({this.url});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(10);
    final placeholder = Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: CorexTokens.surfaceTop(context),
        borderRadius: radius,
      ),
      child: Icon(TablerIcons.photo_off,
          size: 22, color: CorexTokens.textTertiary(context)),
    );
    if (url == null || url!.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        url!,
        width: 76,
        height: 76,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}
