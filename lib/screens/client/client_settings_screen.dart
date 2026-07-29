import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';
import '../../widgets/ui/content_width.dart';

import '../../providers/client_matches_provider.dart';
import '../../providers/client_session_provider.dart';
import '../../providers/seller_listings_provider.dart';
import '../../services/api_service.dart' show ApiException;
import '../../services/client_auth_service.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../widgets/corex/corex_card.dart';
import '../../widgets/corex/corex_scaffold.dart';
import '../auth/client/client_agency_picker_screen.dart';

const Color _kDanger = Color(0xFFEF4444);

class ClientSettingsScreen extends StatelessWidget {
  const ClientSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<ClientSessionProvider>();
    final t = CorexAccentTheme.of(context);
    final canSwitch =
        session.agencies.length > 1 && session.client?.lockedToAgencyId == null;

    return CorexScaffold(
      title: 'Settings',
      body: ContentSafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (session.contact != null)
              CorexCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: t.accentSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.accentBorder),
                      ),
                      alignment: Alignment.center,
                      child: Icon(TablerIcons.user, color: t.accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.contact!.fullName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: CorexTokens.textPrimary(context),
                            ),
                          ),
                          Text(
                            session.client?.email ??
                                session.contact!.email ??
                                '',
                            style: TextStyle(
                              fontSize: 12,
                              color: CorexTokens.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            _SettingsRow(
              icon: TablerIcons.lock,
              label: 'Change password',
              onTap: () => showDialog(
                context: context,
                builder: (_) => const _ChangePasswordDialog(),
              ),
            ),
            const SizedBox(height: 10),
            _SettingsRow(
              icon: TablerIcons.arrows_left_right,
              label: 'Switch agency',
              enabled: canSwitch,
              onTap: canSwitch
                  ? () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ClientAgencyPickerScreen(
                              initialPick: false),
                        ),
                      )
                  : null,
            ),
            const SizedBox(height: 10),
            _SettingsRow(
              icon: TablerIcons.logout,
              label: 'Sign out',
              tint: _kDanger,
              onTap: () async {
                // Mirror the client drawer / profile sign-out: drop the
                // previous account's listings & matches before tearing down
                // the session so nothing carries into the next sign-in.
                context.read<SellerListingsProvider>().reset();
                context.read<ClientMatchesProvider>().reset();
                await context.read<ClientSessionProvider>().signOut();
                if (context.mounted) {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final Color? tint;

  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    final color = tint ?? t.accent;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: CorexCard(
        onTap: enabled ? onTap : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: tint ?? CorexTokens.textPrimary(context),
                ),
              ),
            ),
            Icon(TablerIcons.chevron_right,
                size: 18, color: CorexTokens.textTertiary(context)),
          ],
        ),
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _api = ClientAuthService();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.changePassword(
        currentPassword: _current.text,
        password: _password.text,
        passwordConfirmation: _confirm.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not change password. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Password'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password'),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
              validator: (v) =>
                  (v == null || v.length < 8) ? 'At least 8 characters' : null,
            ),
            TextFormField(
              controller: _confirm,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Confirm new password'),
              validator: (v) =>
                  v != _password.text ? 'Passwords do not match' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
