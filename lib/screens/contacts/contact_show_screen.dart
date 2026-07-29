import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/ui/content_width.dart';
import '../../models/contact.dart';
import '../../services/api_service.dart';
import '../../theme.dart';
import 'contact_compliance_screen.dart';
import 'edit_contact_screen.dart';
import 'new_match_screen.dart';
import 'role_picker_sheet.dart';
import '../properties/property_create_screen.dart';
import '../properties/property_overview_screen.dart';

const Color _kSuccess = Color(0xFF22C55E);

class ContactShowScreen extends StatefulWidget {
  final int contactId;
  const ContactShowScreen({super.key, required this.contactId});

  @override
  State<ContactShowScreen> createState() => _ContactShowScreenState();
}

typedef ContactDetailScreen = ContactShowScreen;

class _ContactShowScreenState extends State<ContactShowScreen> {
  final ApiService _api = ApiService();
  Contact? _contact;
  bool _loading = true;
  String? _error;
  bool _whatsappBusy = false;

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
      final c = await _api.getContact(widget.contactId);
      if (!mounted) return;
      setState(() {
        _contact = c;
        _loading = false;
      });
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

  Future<void> _whatsapp() async {
    if (_whatsappBusy) return;
    setState(() => _whatsappBusy = true);
    try {
      final res = await _api.whatsappContact(widget.contactId);
      final link = res['wa_link']?.toString();
      if (link != null && link.isNotEmpty) {
        await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
      }
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('WhatsApp failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _whatsappBusy = false);
    }
  }

  Future<void> _openEdit() async {
    final c = _contact;
    if (c == null) return;
    final updated = await Navigator.of(context).push<Contact>(
      MaterialPageRoute(builder: (_) => EditContactScreen(contact: c)),
    );
    if (updated != null && mounted) setState(() => _contact = updated);
  }

  Future<void> _addMatch() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NewMatchScreen(contactId: widget.contactId),
      ),
    );
    if (created == true) await _load();
  }

  Future<void> _addListing() async {
    final role = await showRolePickerSheet(context);
    if (role == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PropertyCreateScreen(
          linkContactId: widget.contactId,
          linkContactRole: role,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_contact?.fullName ?? 'Contact'),
        actions: _contact == null
            ? null
            : [
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _openEdit,
                ),
              ],
      ),
      body: ContentSafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    color: AppTheme.brand,
                    backgroundColor: AppTheme.surface(context),
                    onRefresh: _load,
                    child: _buildBody(),
                  ),
      ),
    );
  }

  Widget _buildBody() {
    final c = _contact!;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _header(c),
        const SizedBox(height: 16),
        _primaryAction(),
        const SizedBox(height: 8),
        _secondaryActions(),
        const SizedBox(height: 24),
        _complianceTile(),
        const SizedBox(height: 24),
        _sectionTitle('Matches'),
        const SizedBox(height: 8),
        if (c.matches.isEmpty)
          _emptySection(
            icon: Icons.search_rounded,
            heading: 'No matches yet',
            body: 'Tap + Match to capture buyer or tenant criteria.',
          )
        else
          ...c.matches.map(_matchTile),
        const SizedBox(height: 24),
        _sectionTitle('Linked Properties'),
        const SizedBox(height: 8),
        if (c.linkedProperties.isEmpty)
          _emptySection(
            icon: Icons.home_work_rounded,
            heading: 'No linked listings',
            body: 'Tap + Listing to create a property tied to this contact.',
          )
        else
          ...c.linkedProperties.map(_linkedTile),
      ],
    );
  }

  Widget _header(Contact c) {
    final hasDetails = (c.phone != null && c.phone!.isNotEmpty) ||
        (c.email != null && c.email!.isNotEmpty) ||
        (c.idNumber != null && c.idNumber!.isNotEmpty);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.brandDark,
                child: Text(
                  _initials(c.fullName),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.fullName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    if (c.contactTypeName != null &&
                        c.contactTypeName!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _pill(c.contactTypeName!, AppTheme.brand),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (hasDetails) const SizedBox(height: 12),
          if (c.phone != null && c.phone!.isNotEmpty)
            _kv(Icons.phone_rounded, c.phone!),
          if (c.email != null && c.email!.isNotEmpty)
            _kv(Icons.email_rounded, c.email!),
          if (c.idNumber != null && c.idNumber!.isNotEmpty)
            _kv(Icons.badge_rounded, c.idNumber!),
          if (c.whatsappCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  _pill('WhatsApp · ${c.whatsappCount}', _kSuccess),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'last ${c.lastContactedAt ?? '—'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _kv(IconData icon, String value) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.textSecondary(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _primaryAction() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.chat_rounded, size: 18),
        label: Text(_whatsappBusy ? 'Opening…' : 'WhatsApp'),
        onPressed: _whatsappBusy ? null : _whatsapp,
      ),
    );
  }

  Widget _secondaryActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _addMatch,
            icon: const Icon(Icons.search_rounded, size: 16),
            label: const Text('+ Match'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _addListing,
            icon: const Icon(Icons.home_work_rounded, size: 16),
            label: const Text('+ Listing'),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary(context),
        ),
      );

  Widget _emptySection({
    required IconData icon,
    required String heading,
    required String body,
  }) {
    return Container(
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
            child: Icon(icon, color: AppTheme.brand, size: 22),
          ),
          const SizedBox(height: 10),
          Text(
            heading,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _matchTile(ContactMatch m) {
    final price = (m.priceMin != null || m.priceMax != null)
        ? 'R${m.priceMin ?? '—'} – R${m.priceMax ?? '—'}'
        : null;
    final subtitle = [
      m.listingType,
      m.suburb,
      price,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  m.name?.isNotEmpty == true ? m.name! : 'Match #${m.id}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ),
              if (m.status != null && m.status!.isNotEmpty) ...[
                const SizedBox(width: 8),
                _pill(m.status!, AppTheme.brand),
              ],
            ],
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _linkedTile(ContactLinkedProperty p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          onTap: () => _openProperty(p.id),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: AppTheme.borderColor(context)),
            ),
            child: Row(
              children: [
                Icon(Icons.home_work_rounded,
                    size: 18, color: AppTheme.brand),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.address?.isNotEmpty == true
                            ? p.address!
                            : 'Property #${p.id}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      if (p.role != null && p.role!.isNotEmpty)
                        Text(
                          p.role!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppTheme.textMuted(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _complianceTile() {
    return Material(
      color: AppTheme.surface(context),
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: () {
          final c = _contact;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ContactComplianceScreen(
                contactId: widget.contactId,
                contactName: c?.fullName,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: AppTheme.borderColor(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.brand.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.verified_user_rounded,
                    color: AppTheme.brand, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Compliance',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    Text(
                      'Consent · Documents · FICA',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppTheme.textMuted(context)),
            ],
          ),
        ),
      ),
    );
  }

  void _openProperty(int id) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PropertyOverviewScreen(propertyId: id),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts.first.isNotEmpty && parts.last.isNotEmpty) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
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
            Icon(Icons.error_outline_rounded,
                size: 32, color: AppTheme.textSecondary(context)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary(context)),
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
