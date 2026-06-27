import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../models/client_models.dart';
import '../../providers/client_session_provider.dart';
import '../../services/api_service.dart' show ApiException, ValidationException;
import '../../services/client_auth_service.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../widgets/corex/corex_card.dart';
import '../../widgets/corex/corex_scaffold.dart';
import '../auth/client/client_agency_picker_screen.dart';

const Color _kGiven = Color(0xFF22C55E); // affirmative green
const Color _kNo = Color(0xFFEF4444); // "do not contact me" red

/// Privacy & Consent — lets a signed-in client SEE and SET their own POPIA/CPA
/// consent in their selected agency. This is the same ledger the agent sees on
/// the web; the server is the source of truth, so every tap re-renders the
/// whole screen from the list the POST returns rather than patching locally.
class ClientConsentScreen extends StatefulWidget {
  /// Injectable for tests; production uses the default client service.
  final ClientAuthService? api;

  const ClientConsentScreen({super.key, this.api});

  @override
  State<ClientConsentScreen> createState() => _ClientConsentScreenState();
}

class _ClientConsentScreenState extends State<ClientConsentScreen> {
  late final ClientAuthService _api = widget.api ?? ClientAuthService();

  bool _loading = true;
  String? _error;
  List<ClientConsent> _consents = const [];

  // Types with an in-flight POST — their row is disabled until it resolves.
  final Set<String> _busy = <String>{};

  // Section order + headings. Channels first (the most tappable), then the
  // higher-stakes groups. Unknown groups (forward-compat) fall to the end.
  static const List<(String, String)> _groups = [
    ('channel', 'Communication channels'),
    ('marketing', 'Marketing'),
    ('compliance', 'Your data'),
  ];

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
      final result = await _api.consent();
      if (!mounted) return;
      setState(() {
        _consents = result.consents;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!await _handleAuthError(e)) return;
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.statusCode == 404
            ? "We couldn't find your contact record with this agency yet. "
                'Your agent can connect you, then you can manage consent here.'
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your consent settings. Pull to retry.';
      });
    }
  }

  /// Records [decision] (`'given'` | `'declined'` | `'clear'`) for [type].
  /// Optimistic-but-correct: update the row immediately for snappy feedback,
  /// POST, then re-render the whole screen from the returned list. On failure,
  /// revert to the previous state and toast.
  Future<void> _set(ClientConsent c, String decision) async {
    if (_busy.contains(c.type)) return;
    // No-op if tapping the already-selected state (Clear is only offered when
    // a decision exists, so this can't suppress a meaningful clear).
    if (decision == c.decision) return;
    if (decision == 'clear' && !c.isSet) return;

    final previous = _consents;
    setState(() {
      _busy.add(c.type);
      _consents = [
        for (final x in _consents)
          x.type == c.type ? x.copyWith(decision: decision) : x,
      ];
    });

    try {
      final result = await _api.setConsent(type: c.type, decision: decision);
      if (!mounted) return;
      setState(() {
        _consents = result.consents;
        _busy.remove(c.type);
      });
    } on ValidationException catch (e) {
      _revert(previous, c.type);
      _toast(e.fieldErrors.values.isNotEmpty
          ? e.fieldErrors.values.first
          : e.message);
    } on ApiException catch (e) {
      _revert(previous, c.type);
      if (!await _handleAuthError(e)) return;
      _toast(e.statusCode == 404
          ? "We couldn't find your contact record with this agency."
          : e.message);
    } catch (_) {
      _revert(previous, c.type);
      _toast('Could not save your choice. Check your connection.');
    }
  }

  void _revert(List<ClientConsent> previous, String type) {
    if (!mounted) return;
    setState(() {
      _consents = previous;
      _busy.remove(type);
    });
  }

  /// Handles 401 (sign out) and 409 (no agency selected) centrally. Returns
  /// false if it consumed the error (caller should stop), true otherwise.
  Future<bool> _handleAuthError(ApiException e) async {
    if (!mounted) return false;
    if (e.statusCode == 401) {
      await context.read<ClientSessionProvider>().signOutLocal();
      return false;
    }
    if (e.statusCode == 409) {
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ClientAgencyPickerScreen(initialPick: true),
          ),
        );
      }
      return false;
    }
    return true;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    return CorexScaffold(
      title: 'Privacy & Consent',
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
    if (_loading && _consents.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _consents.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 64),
          Icon(TablerIcons.shield_lock,
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

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        Text(
          'Choose how this agency may use your information and contact you. '
          'Your choices apply immediately and are shared with your agent.',
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: CorexTokens.textSecondary(context),
          ),
        ),
        for (final (group, heading) in _groups) ..._section(group, heading),
        ..._leftoverSections(),
      ],
    );
  }

  /// Any group the backend adds later that isn't in [_groups] still renders,
  /// titled by its raw key — we never silently drop a consent type.
  List<Widget> _leftoverSections() {
    final known = _groups.map((g) => g.$1).toSet();
    final extra = <String>{
      for (final c in _consents)
        if (!known.contains(c.group)) c.group
    };
    return [
      for (final g in extra) ..._section(g, _titleCase(g)),
    ];
  }

  List<Widget> _section(String group, String heading) {
    final rows = _consents.where((c) => c.group == group).toList();
    if (rows.isEmpty) return const [];
    return [
      const SizedBox(height: 22),
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(
          heading.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: CorexTokens.textTertiary(context),
          ),
        ),
      ),
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        _ConsentRow(
          consent: rows[i],
          isChannel: group == 'channel',
          busy: _busy.contains(rows[i].type),
          onSelect: (decision) => _set(rows[i], decision),
        ),
      ],
    ];
  }

  static String _titleCase(String s) => s.isEmpty
      ? s
      : s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');
}

class _ConsentRow extends StatelessWidget {
  final ClientConsent consent;
  final bool isChannel;
  final bool busy;
  final ValueChanged<String> onSelect;

  const _ConsentRow({
    required this.consent,
    required this.isChannel,
    required this.busy,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final c = consent;
    return CorexCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  c.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: CorexTokens.textPrimary(context),
                  ),
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (c.isSet)
                _ClearButton(onTap: () => onSelect('clear')),
            ],
          ),
          if (isChannel) ...[
            const SizedBox(height: 4),
            Text(
              'Tapping No stops the agency contacting you this way, right away.',
              style: TextStyle(
                fontSize: 12,
                height: 1.3,
                color: CorexTokens.textTertiary(context),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _TriState(
            decision: c.decision,
            enabled: !busy,
            onSelect: onSelect,
          ),
          const SizedBox(height: 8),
          Text(
            _statusLine(c),
            style: TextStyle(
              fontSize: 11.5,
              color: CorexTokens.textTertiary(context),
            ),
          ),
        ],
      ),
    );
  }

  static String _statusLine(ClientConsent c) {
    if (!c.isSet) return 'Not set';
    final verb = c.isGiven ? 'Allowed' : 'Declined';
    final when = _fmtDate(c.recordedAt);
    return when.isEmpty ? verb : '$verb · set on $when';
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _fmtDate(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final l = dt.toLocal();
    return '${l.day} ${_months[l.month - 1]} ${l.year}';
  }
}

/// Tri-state control: two pill buttons (Yes / No). The selected one fills with
/// its colour — green for Yes, an unmistakable red for No ("do not contact me").
class _TriState extends StatelessWidget {
  final String? decision;
  final bool enabled;
  final ValueChanged<String> onSelect;

  const _TriState({
    required this.decision,
    required this.enabled,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Pill(
            label: 'Yes',
            icon: TablerIcons.check,
            color: _kGiven,
            selected: decision == 'given',
            enabled: enabled,
            onTap: () => onSelect('given'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Pill(
            label: 'No',
            icon: TablerIcons.x,
            color: _kNo,
            selected: decision == 'declined',
            enabled: enabled,
            onTap: () => onSelect('declined'),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _Pill({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : color;
    final borderRadius = BorderRadius.circular(12);
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: selected ? color : color.withValues(alpha: 0.10),
        borderRadius: borderRadius,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: enabled ? onTap : null,
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: Border.all(
                color: selected ? color : color.withValues(alpha: 0.45),
                width: 1,
              ),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClearButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ClearButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: CorexTokens.textTertiary(context),
      ),
      child: const Text('Clear', style: TextStyle(fontSize: 12.5)),
    );
  }
}
