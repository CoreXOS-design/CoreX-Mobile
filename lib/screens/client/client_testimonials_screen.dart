import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';
import '../../widgets/ui/content_width.dart';

import '../../models/client_models.dart';
import '../../providers/client_session_provider.dart';
import '../../services/api_service.dart' show ApiException;
import '../../services/client_auth_service.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../widgets/corex/corex_card.dart';
import '../../widgets/corex/corex_primary_button.dart';
import '../../widgets/corex/corex_scaffold.dart';
import '../../widgets/ui/status_chip.dart';
import '../auth/client/client_agency_picker_screen.dart';
import 'client_testimonial_form_screen.dart';

const Color _kLive = Color(0xFF22C55E);

/// The reviews the signed-in client has written about their agent, with an
/// entry point to leave a new one. Statuses make the publish flow honest:
/// "Submitted" (awaiting the agency) vs "Live on website".
class ClientTestimonialsScreen extends StatefulWidget {
  /// Injectable for tests; production uses the default client service.
  final ClientAuthService? api;

  const ClientTestimonialsScreen({super.key, this.api});

  @override
  State<ClientTestimonialsScreen> createState() =>
      _ClientTestimonialsScreenState();
}

class _ClientTestimonialsScreenState extends State<ClientTestimonialsScreen> {
  late final ClientAuthService _api = widget.api ?? ClientAuthService();

  bool _loading = true;
  String? _error;
  List<ClientTestimonial> _testimonials = const [];

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
    try {
      final result = await _api.testimonials();
      if (!mounted) return;
      setState(() {
        _testimonials = result.testimonials;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) {
        await context.read<ClientSessionProvider>().signOutLocal();
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
        _error = e.statusCode == 404
            ? "We couldn't find your contact record with this agency yet. "
                'Your agent can connect you, then you can leave a review.'
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your reviews. Pull to retry.';
      });
    }
  }

  Future<void> _leaveTestimonial() async {
    final session = context.read<ClientSessionProvider>();
    final prefill = session.contact?.fullName.isNotEmpty == true
        ? session.contact!.fullName
        : null;
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ClientTestimonialFormScreen(prefillName: prefill),
      ),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks — sent to your agent')),
      );
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    return CorexScaffold(
      title: 'Review your agent',
      floatingActionButton: _testimonials.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _leaveTestimonial,
              backgroundColor: t.accent,
              foregroundColor: Colors.white,
              icon: const Icon(TablerIcons.plus),
              label: const Text('New review'),
            ),
      body: ContentSafeArea(
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
    if (_loading && _testimonials.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _testimonials.isEmpty) {
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
    if (_testimonials.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 72),
          Icon(TablerIcons.quote,
              size: 56, color: CorexTokens.textTertiary(context)),
          const SizedBox(height: 16),
          Text(
            'Had a great experience?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: CorexTokens.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Leave a testimonial about your agent. They review every one, and '
            'can choose to feature it on their website.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: CorexTokens.textSecondary(context),
            ),
          ),
          const SizedBox(height: 24),
          CorexPrimaryButton(
            label: 'Leave a testimonial',
            leading: TablerIcons.pencil,
            onPressed: _leaveTestimonial,
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _testimonials.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _TestimonialCard(testimonial: _testimonials[i]),
    );
  }
}

class _TestimonialCard extends StatelessWidget {
  final ClientTestimonial testimonial;
  const _TestimonialCard({required this.testimonial});

  @override
  Widget build(BuildContext context) {
    final t = testimonial;
    return CorexCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (t.rating != null && t.rating! > 0) ...[
            _stars(context, t.rating!),
            const SizedBox(height: 10),
          ],
          Text(
            t.body,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: CorexTokens.textPrimary(context),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _meta(t),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: CorexTokens.textTertiary(context),
                  ),
                ),
              ),
              if (t.published) ...[
                const SizedBox(width: 8),
                _statusChip(),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _meta(ClientTestimonial t) {
    final date = _fmtDate(t.createdAt);
    final name = t.displayName;
    if (name != null && name.isNotEmpty && date.isNotEmpty) {
      return '$name · $date';
    }
    return name?.isNotEmpty == true ? name! : date;
  }

  Widget _statusChip() => const StatusChip(
        label: 'Live on website',
        color: _kLive,
        icon: TablerIcons.world,
        dense: true,
      );

  Widget _stars(BuildContext context, int rating) {
    final accent = CorexAccentTheme.of(context).accent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 18,
            color: i <= rating ? accent : CorexTokens.textTertiary(context),
          ),
      ],
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _fmtDate(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final local = dt.toLocal();
    return '${local.day} ${_months[local.month - 1]} ${local.year}';
  }
}
