import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/portal_lead.dart';
import '../../providers/portal_leads_provider.dart';
import '../../services/api_service.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../widgets/corex/corex_card.dart';

class PortalLeadDetailScreen extends StatefulWidget {
  final int leadId;
  const PortalLeadDetailScreen({super.key, required this.leadId});

  @override
  State<PortalLeadDetailScreen> createState() => _PortalLeadDetailScreenState();
}

class _PortalLeadDetailScreenState extends State<PortalLeadDetailScreen> {
  final ApiService _api = ApiService();
  PortalLead? _lead;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final lead = await _api.getPortalLead(widget.leadId);
      if (!mounted) return;
      setState(() {
        _lead = lead;
        _loading = false;
      });
      unawaitedMarkRead();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void unawaitedMarkRead() {
    final provider = context.read<PortalLeadsProvider>();
    provider.markRead(widget.leadId);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: CorexTokens.pageBase(context),
        body: Container(
          decoration: BoxDecoration(gradient: CorexTokens.pageBacklight(context)),
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context),
                Expanded(child: _body(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(TablerIcons.arrow_left,
                  color: CorexTokens.textPrimary(context)),
            ),
            Text(
              'Lead',
              style: TextStyle(
                color: CorexTokens.textPrimary(context),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _lead == null) {
      return Center(
        child: Text(
          _error ?? 'Lead not found',
          style: TextStyle(color: CorexTokens.textSecondary(context)),
        ),
      );
    }
    final l = _lead!;
    final t = CorexAccentTheme.of(context);
    final isP24 = l.portal == 'p24';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (isP24
                          ? const Color(0xFFE11D2A)
                          : const Color(0xFF2563EB))
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  l.portalLabel,
                  style: TextStyle(
                    color: isP24
                        ? const Color(0xFFE11D2A)
                        : const Color(0xFF2563EB),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (l.leadType != null && l.leadType!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: t.accentSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    l.leadType!,
                    style: TextStyle(
                      color: t.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            l.name?.trim().isNotEmpty == true ? l.name! : '(no name)',
            style: TextStyle(
              color: CorexTokens.textPrimary(context),
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          if (l.receivedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              _formatDateTime(l.receivedAt!),
              style: TextStyle(
                color: CorexTokens.textTertiary(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          _section(context, 'Contact', [
            if (l.phone != null && l.phone!.isNotEmpty)
              _ContactRow(
                icon: TablerIcons.phone,
                label: l.phone!,
                onTap: () => _launch('tel:${l.phone}'),
                trailing: l.isWhatsapp
                    ? const _Tag(label: 'WhatsApp')
                    : null,
              ),
            if (l.email != null && l.email!.isNotEmpty)
              _ContactRow(
                icon: TablerIcons.mail,
                label: l.email!,
                onTap: () => _launch('mailto:${l.email}'),
              ),
          ]),
          const SizedBox(height: 12),
          _section(context, 'Listing', [
            if (l.listingPortalRef != null && l.listingPortalRef!.isNotEmpty)
              _ContactRow(
                icon: TablerIcons.hash,
                label: l.listingPortalRef!,
              ),
            if (l.listingTitle != null && l.listingTitle!.isNotEmpty)
              _ContactRow(
                icon: TablerIcons.building_skyscraper,
                label: l.listingTitle!,
              ),
          ]),
          if (l.message != null && l.message!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _section(context, 'Message', [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  l.message!,
                  style: TextStyle(
                    color: CorexTokens.textPrimary(context),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 12),
          _section(context, 'Status', [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                l.contactExists
                    ? 'Contact exists${l.existingAgent != null ? ' · ${l.existingAgent}' : ''}'
                    : 'New lead — no matching contact yet',
                style: TextStyle(
                  color: CorexTokens.textSecondary(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            title,
            style: TextStyle(
              color: CorexTokens.textTertiary(context),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
        CorexCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rows,
          ),
        ),
      ],
    );
  }

  Future<void> _launch(String u) async {
    final uri = Uri.tryParse(u);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  static String _formatDateTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year} · $h:$m';
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _ContactRow({
    required this.icon,
    required this.label,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: t.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: CorexTokens.textPrimary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  const _Tag({required this.label});
  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: t.moneySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: t.accentMoney,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
