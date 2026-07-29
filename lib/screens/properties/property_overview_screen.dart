import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/external_launch.dart';
import '../../widgets/ui/content_width.dart';
import '../../config/env.dart';
import '../../models/property_compliance.dart';
import '../../models/property_overview.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme.dart';
import 'add_contact_sheet.dart';
import 'property_edit_screen.dart';
import 'rental_inspections_screen.dart';

class PropertyOverviewScreen extends StatefulWidget {
  final int propertyId;
  final ApiService? api;

  const PropertyOverviewScreen({
    super.key,
    required this.propertyId,
    this.api,
  });

  @override
  State<PropertyOverviewScreen> createState() => _PropertyOverviewScreenState();
}

class _PropertyOverviewScreenState extends State<PropertyOverviewScreen> {
  late final ApiService _api = widget.api ?? ApiService();
  PropertyOverview? _data;
  PropertyCompliance? _compliance;
  List<PropertyContact>? _contacts;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  bool _descExpanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final d = await _api.getPropertyOverview(widget.propertyId,
          forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
      _loadComplianceAndContacts();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 403) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _error = e.message;
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

  Future<void> _open(String? url) => launchExternal(context, url);

  /// The document / FICA / photo flows live on the web — open them in an
  /// in-app browser so the agent stays inside the app.
  Future<void> _openWeb(String? url) =>
      launchExternal(context, url, mode: LaunchMode.inAppBrowserView);

  Future<void> _loadComplianceAndContacts() async {
    final results = await Future.wait([
      _api.getPropertyCompliance(widget.propertyId).then<Object?>(
          (v) => v, onError: (_) => null),
      _api.getPropertyContacts(widget.propertyId).then<Object?>(
          (v) => v, onError: (_) => null),
    ]);
    if (!mounted) return;
    setState(() {
      if (results[0] is PropertyCompliance) {
        _compliance = results[0] as PropertyCompliance;
      }
      if (results[1] is List<PropertyContact>) {
        _contacts = results[1] as List<PropertyContact>;
      }
    });
  }

  Future<void> _refreshCompliance() async {
    try {
      final c = await _api.getPropertyCompliance(widget.propertyId);
      if (mounted) setState(() => _compliance = c);
    } catch (_) {/* keep last good state */}
  }

  Future<void> _sendToMarket() async {
    setState(() => _sending = true);
    try {
      final c = await _api.sendToMarket(widget.propertyId);
      if (!mounted) return;
      setState(() {
        _compliance = c;
        _sending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Property sent to market.')),
      );
      _load(forceRefresh: true);
    } on MarketingBlockedException catch (e) {
      if (!mounted) return;
      setState(() {
        _compliance = e.report;
        _sending = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send to market.')),
      );
    }
  }

  Future<void> _addContact() async {
    final added = await AddContactSheet.show(
      context,
      propertyId: widget.propertyId,
      api: _api,
    );
    if (added && mounted) {
      // Linking a seller + their FICA affects the fica_sellers gate.
      await Future.wait([
        _api.getPropertyContacts(widget.propertyId).then(
            (v) => mounted ? setState(() => _contacts = v) : null,
            onError: (_) {}),
        _refreshCompliance(),
      ]);
    }
  }

  Future<void> _unlinkContact(PropertyContact c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unlink contact'),
        content: Text(
            'Remove ${c.fullName} from this property? This only removes the link — the contact is kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Unlink')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _api.deletePropertyContact(widget.propertyId, c.id);
      if (!mounted) return;
      await Future.wait([
        _api.getPropertyContacts(widget.propertyId).then(
            (v) => mounted ? setState(() => _contacts = v) : null,
            onError: (_) {}),
        _refreshCompliance(),
      ]);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Overview'),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      PropertyEditScreen(propertyId: widget.propertyId),
                ),
              );
              if (mounted) _load(forceRefresh: true);
            },
          ),
        ],
      ),
      body: ContentSafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: () => _load(forceRefresh: true))
                : RefreshIndicator(
                    onRefresh: () => _load(forceRefresh: true),
                    child: _buildBody(_data!),
                  ),
      ),
    );
  }

  Widget _buildBody(PropertyOverview p) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _hero(p),
        const SizedBox(height: 16),
        _atAGlance(p),
        const SizedBox(height: 16),
        if (_compliance != null) ...[
          _sectionTitle('Compliance'),
          const SizedBox(height: 8),
          _complianceCard(_compliance!),
          const SizedBox(height: 16),
        ],
        // Rental inspection galleries — live rentals only. Gate strictly on
        // the server flag; never derive eligibility here.
        if (p.rentalInspectionsAvailable) ...[
          _sectionTitle('Inspections'),
          const SizedBox(height: 8),
          _inspectionsCard(p),
          const SizedBox(height: 16),
        ],
        _sectionTitle('Contacts'),
        const SizedBox(height: 8),
        _contactsCard(),
        const SizedBox(height: 16),
        if ((p.description ?? '').isNotEmpty) ...[
          _sectionTitle('Description'),
          _description(p.description!),
          const SizedBox(height: 16),
        ],
        if ((p.livePreviewUrl ?? '').isNotEmpty) ...[
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open Live Preview'),
              onPressed: () => _open(p.livePreviewUrl),
            ),
          ),
          const SizedBox(height: 16),
        ],
        _sectionTitle('Where this listing is published'),
        const SizedBox(height: 8),
        _portalLinksBlock(p.portalLinks),
        const SizedBox(height: 16),
        if (p.agent != null || p.secondAgent != null) ...[
          _sectionTitle(p.secondAgent != null ? 'Listing Agents' : 'Listing Agent'),
          const SizedBox(height: 8),
          if (p.agent != null)
            _contactCard(p.agent!,
                roleLabel: p.secondAgent != null ? 'Lead agent' : null),
          if (p.secondAgent != null) ...[
            if (p.agent != null) const SizedBox(height: 8),
            _contactCard(p.secondAgent!, roleLabel: 'Co-agent'),
          ],
          const SizedBox(height: 16),
        ],
        if (p.owner != null) ...[
          _sectionTitle('Owner'),
          const SizedBox(height: 8),
          _contactCard(p.owner!, onTap: p.owner!.id != null ? () {} : null),
          const SizedBox(height: 16),
        ],
        if ((p.virtualTourUrl ?? '').isNotEmpty) ...[
          _sectionTitle('Virtual Tour'),
          const SizedBox(height: 8),
          _virtualTourCard(p.virtualTourUrl!),
          const SizedBox(height: 16),
        ],
        _sectionTitle('Key dates'),
        const SizedBox(height: 8),
        _keyDatesGrid(p.keyDates),
      ],
    );
  }

  Widget _hero(PropertyOverview p) {
    final hasImage = (p.coverImage ?? '').isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          color: AppTheme.surface2(context),
          image: hasImage
              ? DecorationImage(
                  image: NetworkImage(p.coverImage!),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                      Colors.black.withValues(alpha: 0.35), BlendMode.darken),
                )
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if ((p.status ?? '').isNotEmpty) _statusPill(p.status!),
                  const Spacer(),
                  if (p.daysOnMarket != null)
                    _chip('${p.daysOnMarket} days on market'),
                ],
              ),
              const Spacer(),
              Text(
                p.title ?? 'Untitled',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                [p.suburb, p.city].where((e) => (e ?? '').isNotEmpty).join(', '),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                p.priceDisplay ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPill(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.brand,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _atAGlance(PropertyOverview p) {
    final items = <String>[];
    if (p.beds != null) items.add('${p.beds} Beds');
    if (p.baths != null) items.add('${p.baths} Baths');
    if (p.garages != null) items.add('${p.garages} Garages');
    if ((p.sizeM2 ?? '').isNotEmpty) items.add('${p.sizeM2} m² floor');
    if ((p.erfSizeM2 ?? '').isNotEmpty) items.add('${p.erfSizeM2} m² erf');
    if (p.photosCount != null) items.add('${p.photosCount} Photos');
    if ((p.mandateType ?? '').isNotEmpty) items.add('${p.mandateType} mandate');

    if (items.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            Text(items[i],
                style: TextStyle(
                  color: AppTheme.textSecondary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                )),
            if (i < items.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('·',
                    style: TextStyle(color: AppTheme.textMuted(context))),
              ),
          ],
        ],
      ),
    );
  }

  Widget _description(String text) {
    const limit = 220;
    final isLong = text.length > limit;
    final shown = !isLong || _descExpanded ? text : '${text.substring(0, limit).trimRight()}…';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(shown,
            style: TextStyle(
                color: AppTheme.textPrimary(context),
                fontSize: 14,
                height: 1.4)),
        if (isLong)
          TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: AppTheme.brand,
            ),
            onPressed: () =>
                setState(() => _descExpanded = !_descExpanded),
            child: Text(_descExpanded ? 'Show less' : 'Read more'),
          ),
      ],
    );
  }

  /// Renders the canonical, ordered [PortalLink] list. We iterate — never
  /// hardcode or filter on `portal` — so a new portal the backend adds shows
  /// up automatically with no app change. Live entries are tappable; entries
  /// that aren't published yet render greyed (not hidden) so the agent can see
  /// where they can still syndicate.
  Widget _portalLinksBlock(List<PortalLink> links) {
    final anyLive = links.any((l) => l.isLive);

    // Nothing live anywhere: lead with a small directive state. Still list the
    // (greyed) portals beneath it when we know the targets.
    if (links.isEmpty || !anyLive) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.cloud_off,
                      size: 18, color: AppTheme.textMuted(context)),
                  const SizedBox(width: 8),
                  Text('Not yet published to any portal',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary(context),
                      )),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                "This listing isn't live anywhere yet — open Syndication on the desktop to publish.",
                style: TextStyle(
                    color: AppTheme.textSecondary(context), fontSize: 13),
              ),
              if (links.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...links.map(_portalLinkCard),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      children: links.map(_portalLinkCard).toList(),
    );
  }

  /// Icon is chosen from the stable `portal` key ONLY, with a generic fallback
  /// for any key we've never seen — so unknown/future portals still render.
  IconData _portalIcon(String portal) {
    switch (portal) {
      case 'website':
        return Icons.language;
      case 'hfc_premium':
        return Icons.star_rounded;
      case 'private_property':
        return Icons.home_work_outlined;
      case 'property24':
        return Icons.public;
      default:
        return Icons.link; // generic fallback for unknown/future portals
    }
  }

  /// The agency/company display name from the logged-in user, walking the few
  /// shapes the profile payload uses. Returns null when unavailable.
  String? _companyName() {
    final user = context.read<AuthProvider>().user;
    if (user == null) return null;
    final candidates = <dynamic>[
      user['agency_name'],
      (user['agency'] is Map) ? (user['agency'] as Map)['name'] : null,
      (user['user'] is Map && (user['user'] as Map)['agency'] is Map)
          ? ((user['user'] as Map)['agency'] as Map)['name']
          : null,
    ];
    for (final c in candidates) {
      if (c is String && c.trim().isNotEmpty) return c.trim();
    }
    return null;
  }

  /// Label to show for a portal row. For the company website we prefer the
  /// actual company name over the generic server label ("Company Website");
  /// everything else uses the server-provided label verbatim.
  String _portalLabel(PortalLink p) {
    if (p.portal == 'website') {
      final name = _companyName();
      if (name != null && name.isNotEmpty) return name;
    }
    return p.label;
  }

  Widget _portalLinkCard(PortalLink p) {
    final live = p.isLive;
    final label = _portalLabel(p);
    final muted = AppTheme.textMuted(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        // Open the exact url we were given — never build a portal URL here.
        // Greyed/not-published rows have no tap.
        onTap: live ? () => _open(p.url) : null,
        child: Opacity(
          opacity: live ? 1 : 0.55,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.surface2(context),
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                  ),
                  child: Icon(_portalIcon(p.portal),
                      color: live ? AppTheme.brand : muted, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary(context),
                          )),
                      const SizedBox(height: 2),
                      if (live)
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Live',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text('View on $label',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.brand,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        )
                      else
                        Text('Not published',
                            style: TextStyle(fontSize: 12, color: muted)),
                      if ((p.ref ?? '').isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text('Ref ${p.ref}',
                            style: TextStyle(fontSize: 11, color: muted)),
                      ],
                    ],
                  ),
                ),
                Icon(live ? Icons.open_in_new : Icons.lock_outline,
                    size: 16, color: muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _contactCard(ContactRef c, {VoidCallback? onTap, String? roleLabel}) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _avatar(c),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (roleLabel != null)
                      Text(
                        roleLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    Text(
                      c.name,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary(context)),
                    ),
                    if ((c.phone ?? '').isNotEmpty)
                      InkWell(
                        onTap: () => _open('tel:${c.phone}'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(Icons.phone,
                                  size: 14, color: AppTheme.brand),
                              const SizedBox(width: 6),
                              Text(c.phone!,
                                  style: TextStyle(
                                      color: AppTheme.brand,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                    if ((c.email ?? '').isNotEmpty)
                      InkWell(
                        onTap: () => _open('mailto:${c.email}'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(Icons.email_outlined,
                                  size: 14, color: AppTheme.brand),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(c.email!,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: AppTheme.brand,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13)),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar(ContactRef c) {
    if ((c.photoUrl ?? '').isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Image.network(c.photoUrl!,
            width: 48, height: 48, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _initialsAvatar(c.name)),
      );
    }
    return _initialsAvatar(c.name);
  }

  Widget _initialsAvatar(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
            ? parts.first.isEmpty
                ? '?'
                : parts.first[0].toUpperCase()
            : '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppTheme.surface2(context),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(initials,
          style: TextStyle(
              color: AppTheme.textPrimary(context),
              fontWeight: FontWeight.w700)),
    );
  }

  /// Entry point into the rental inspection galleries. Only ever rendered
  /// when the server's `rental_inspections_available` flag is true.
  Widget _inspectionsCard(PropertyOverview p) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => RentalInspectionsScreen(
                propertyId: widget.propertyId,
                propertyTitle: p.title,
                api: _api,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.surface2(context),
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                ),
                child: Icon(Icons.fact_check_outlined,
                    color: AppTheme.brand, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Rental Inspections',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary(context))),
                    const SizedBox(height: 2),
                    Text('In, out & custom inspection galleries',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary(context))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 20, color: AppTheme.textMuted(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _virtualTourCard(String url) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: () => _open(url),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.threesixty, color: AppTheme.brand),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Virtual Tour',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary(context))),
              ),
              Icon(Icons.open_in_new,
                  size: 16, color: AppTheme.textMuted(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keyDatesGrid(KeyDates kd) {
    final tiles = [
      _KeyDateTile('Listed', kd.listed),
      _KeyDateTile('Expires', kd.expires),
      _KeyDateTile('Loaded', _relative(kd.loaded)),
      _KeyDateTile('Modified', _relative(kd.modified)),
    ];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.6,
      children: tiles
          .map((t) => Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(t.label,
                          style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary(context),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4)),
                      const SizedBox(height: 4),
                      Text(t.value ?? '—',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary(context))),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }

  String? _relative(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final l = dt.toLocal();
    return '${l.day} ${months[l.month - 1]} ${l.year}';
  }

  /// Some gate actions route to fixed web flows rather than the backend's
  /// `action_url`. The authority/mandate gate opens the e-sign creator for
  /// this property; the seller-FICA gate opens the FICA creator.
  String? _overrideActionUrl(String gateKey) {
    // Derive the web host from the configured API base (strip the trailing
    // `/api`) so these flows follow staging/production automatically and are
    // always HTTPS — never a hardcoded cleartext host. The backend's own
    // `action_url` is preferred over this (see _gateRow); this is the fallback
    // for gates the backend doesn't return an action for.
    final webBase = Env.apiBaseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    switch (gateKey) {
      case 'authority_to_market':
        return '$webBase/docuperfect/esign/create'
            '?property_id=${widget.propertyId}&template_type=mandate';
      case 'fica_sellers':
        return '$webBase/corex/compliance/fica/create';
      default:
        return null;
    }
  }

  ComplianceNextAction? _actionFor(PropertyCompliance c, String gateKey) {
    // Map a gate to its matching next_action. The backend keys the action by
    // label text, so fall back to a fuzzy contains-match on the gate label.
    final label = complianceGateLabel(gateKey);
    for (final a in c.nextActions) {
      final l = a.label.toLowerCase();
      if (gateKey == 'photos' && l.contains('photo')) return a;
      if (gateKey == 'fica_sellers' && l.contains('fica')) return a;
      if (gateKey == 'authority_to_market' &&
          (l.contains('authority') ||
              l.contains('mandate') ||
              l.contains('market'))) {
        return a;
      }
      if (gateKey == 'details_complete' &&
          (l.contains('detail') || l.contains('listing'))) {
        return a;
      }
      if (l.contains(label.toLowerCase())) return a;
    }
    return null;
  }

  Widget _ficaBadge(String? status, bool passed) {
    final color = passed ? Colors.green : Colors.orange;
    final text = passed
        ? 'FICA approved'
        : 'FICA ${(status ?? 'pending').replaceAll('_', ' ')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _roleBadge(String? role) {
    if (role == null || role.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.brand.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(role,
          style: TextStyle(
              color: AppTheme.brand,
              fontSize: 11,
              fontWeight: FontWeight.w700)),
    );
  }

  Widget _complianceCard(PropertyCompliance c) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _statusBadge(c),
            const SizedBox(height: 12),
            if (c.isLive)
              _liveBanner(c)
            else ...[
              for (final gate in c.checklist) _gateRow(c, gate),
              if (c.photos != null) ...[
                const SizedBox(height: 10),
                _photosChip(c.photos!),
              ],
              if (c.blockedBy.isNotEmpty) ...[
                const SizedBox(height: 14),
                _blockedByList(c.blockedBy),
              ],
            ],
            if (c.sellers.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Sellers',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary(context))),
              const SizedBox(height: 6),
              for (final s in c.sellers) _sellerRow(s),
            ],
            if (!c.isLive) ...[
              ..._extraActions(c),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send, size: 18),
                  label: const Text('Send Authority to Market'),
                  onPressed:
                      (c.ready && !_sending) ? _sendToMarket : null,
                ),
              ),
              if (!c.ready)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Resolve the items above to enable sending to market.',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context)),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _liveBanner(PropertyCompliance c) {
    final date = _fmtDate(c.snapshotAt);
    final by = (c.snapshottedBy ?? '').trim();
    final headline = date.isEmpty ? 'Live' : 'Live · Sent to market on $date';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                ),
                if (by.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'by $by',
                      style: TextStyle(
                          color: AppTheme.textSecondary(context),
                          fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Overall status pill — LIVE (green) / READY (blue) / BLOCKED (orange).
  /// Falls back to the derived state when the server omits `status`.
  Widget _statusBadge(PropertyCompliance c) {
    final status =
        (c.status ?? (c.isLive ? 'LIVE' : (c.ready ? 'READY' : 'BLOCKED')))
            .toUpperCase();
    late final Color color;
    late final IconData icon;
    switch (status) {
      case 'LIVE':
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case 'READY':
        color = Colors.blue;
        icon = Icons.task_alt;
        break;
      default:
        color = Colors.orange;
        icon = Icons.error_outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(status,
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }

  /// The "what's blocking go-live" summary list.
  Widget _blockedByList(List<String> reasons) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.block, size: 16, color: Colors.orange),
              const SizedBox(width: 6),
              Text('Blocking go-live',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary(context))),
            ],
          ),
          const SizedBox(height: 6),
          for (final r in reasons)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ',
                      style: TextStyle(color: AppTheme.textSecondary(context))),
                  Expanded(
                    child: Text(r,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textSecondary(context))),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Next-action buttons the server returned that aren't already surfaced
  /// inline on a specific failing gate (e.g. "Send Marketing Pack"). Each
  /// deep-links via its `action_url`.
  List<Widget> _extraActions(PropertyCompliance c) {
    if (c.nextActions.isEmpty) return const [];
    final consumed = <ComplianceNextAction>{};
    for (final gate in c.checklist) {
      if (gate.passed) continue;
      final a = _actionFor(c, gate.key);
      if (a != null) consumed.add(a);
    }
    final extras = c.nextActions
        .where((a) => !consumed.contains(a) && a.actionUrl.isNotEmpty)
        .toList();
    if (extras.isEmpty) return const [];
    return [
      const SizedBox(height: 14),
      Text('Next actions',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary(context))),
      for (final a in extras)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.open_in_new, size: 15),
              label: Text(a.label.isEmpty ? 'Open' : a.label),
              onPressed: () => _openWeb(a.actionUrl),
            ),
          ),
        ),
    ];
  }

  Widget _gateRow(PropertyCompliance c, ComplianceGate gate) {
    final action = gate.passed ? null : _actionFor(c, gate.key);
    final overrideUrl = gate.passed ? null : _overrideActionUrl(gate.key);
    // Prefer the backend's own action_url (authoritative, correct per
    // environment); fall back to the locally-derived HTTPS web flow only when
    // the backend didn't supply one.
    final actionUrl = action?.actionUrl ?? overrideUrl;
    final actionLabel = action?.label ??
        (gate.key == 'authority_to_market'
            ? 'Send mandate for signature'
            : gate.key == 'fica_sellers'
                ? 'Start seller FICA'
                : 'Resolve');
    final color = gate.passed ? Colors.green : Colors.orange;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                  gate.passed
                      ? Icons.check_circle
                      : Icons.error_outline,
                  size: 18,
                  color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      complianceGateLabel(gate.key),
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary(context)),
                    ),
                    if (gate.detail.isNotEmpty)
                      Text(gate.detail,
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary(context))),
                  ],
                ),
              ),
            ],
          ),
          if (actionUrl != null && actionUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 6),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.open_in_new, size: 15),
                label: Text(actionLabel),
                onPressed: () => _openWeb(actionUrl),
              ),
            ),
        ],
      ),
    );
  }

  Widget _photosChip(CompliancePhotos p) {
    final ok = p.passed;
    final color = ok ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_library_outlined, size: 14, color: color),
          const SizedBox(width: 6),
          Text('${p.count}/${p.required} photos',
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _sellerRow(ComplianceSeller s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary(context))),
                if ((s.role ?? '').isNotEmpty)
                  Text(s.role!,
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context))),
              ],
            ),
          ),
          _ficaBadge(s.ficaStatus, s.ficaPassed),
        ],
      ),
    );
  }

  Widget _contactsCard() {
    final contacts = _contacts;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (contacts == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child:
                          CircularProgressIndicator(strokeWidth: 2)),
                ),
              )
            else if (contacts.isEmpty)
              Text('No contacts linked yet.',
                  style:
                      TextStyle(color: AppTheme.textSecondary(context)))
            else
              for (var i = 0; i < contacts.length; i++) ...[
                if (i > 0) const Divider(height: 18),
                _propertyContactRow(contacts[i]),
              ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('Add contact'),
                onPressed: _addContact,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _propertyContactRow(PropertyContact c) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(c.fullName,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary(context))),
                  ),
                  const SizedBox(width: 8),
                  _roleBadge(c.role ?? c.type),
                ],
              ),
              if ((c.phone ?? '').isNotEmpty)
                InkWell(
                  onTap: () => _open('tel:${c.phone}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Icon(Icons.phone, size: 14, color: AppTheme.brand),
                      const SizedBox(width: 6),
                      Text(c.phone!,
                          style: TextStyle(
                              color: AppTheme.brand,
                              fontWeight: FontWeight.w500,
                              fontSize: 13)),
                    ]),
                  ),
                ),
              if ((c.email ?? '').isNotEmpty)
                InkWell(
                  onTap: () => _open('mailto:${c.email}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Icon(Icons.email_outlined,
                          size: 14, color: AppTheme.brand),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(c.email!,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppTheme.brand,
                                fontWeight: FontWeight.w500,
                                fontSize: 13)),
                      ),
                    ]),
                  ),
                ),
              if ((c.ficaStatus ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _ficaBadge(c.ficaStatus,
                      c.ficaStatus?.toLowerCase() == 'approved'),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Unlink',
          icon: Icon(Icons.link_off,
              size: 18, color: AppTheme.textMuted(context)),
          onPressed: () => _unlinkContact(c),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary(context),
            )),
      );
}

class _KeyDateTile {
  final String label;
  final String? value;
  _KeyDateTile(this.label, this.value);
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 40, color: AppTheme.textMuted(context)),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary(context))),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
