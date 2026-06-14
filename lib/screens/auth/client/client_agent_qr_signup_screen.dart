import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/client_models.dart';
import '../../../providers/client_session_provider.dart';
import '../../../services/api_service.dart' show ApiException;
import '../../../services/client_auth_service.dart';
import '../../../theme.dart';
import '../../../widgets/ui/auth_scaffold.dart';
import '../../../widgets/ui/glow_button.dart';
import 'client_auth_shared.dart';
import 'client_otp_screen.dart';

class ClientAgentQrSignupScreen extends StatefulWidget {
  final String slug;
  const ClientAgentQrSignupScreen({super.key, required this.slug});

  @override
  State<ClientAgentQrSignupScreen> createState() =>
      _ClientAgentQrSignupScreenState();
}

class _ClientAgentQrSignupScreenState extends State<ClientAgentQrSignupScreen> {
  final _api = ClientAuthService();
  final _formKey = GlobalKey<FormState>();

  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  AgentQrAgent? _agent;
  bool _loadingAgent = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAgent();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _loadAgent() async {
    try {
      final agent = await _api.agentQrPreview(widget.slug);
      if (!mounted) return;
      setState(() {
        _agent = agent;
        _loadingAgent = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      showAuthToast(
        context,
        e.statusCode == 404 ? 'Agent QR not found' : e.message,
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      showAuthToast(context, 'Could not reach the server.');
      Navigator.of(context).pop();
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final email = _email.text.trim();
      final resp = await _api.agentQrRegister(
        slug: widget.slug,
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        phone: _phone.text.trim(),
        email: email,
        password: _password.text,
        passwordConfirmation: _confirm.text,
        deviceName: defaultDeviceName(),
      );

      // Email already belongs to a client in this agency. The server linked
      // them to the agent but withheld a token — verify ownership via OTP and
      // set a password before signing in (the normal client activation flow).
      if (resp.requiresVerification) {
        if (!mounted) return;
        showAuthToast(
          context,
          resp.message ??
              'This email is already registered. Verify it to continue.',
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ClientOtpScreen(
              email: email,
              purpose: OtpPurpose.activation,
            ),
          ),
        );
        return;
      }

      await _api.saveToken(resp.token);
      if (!mounted) return;

      final session = context.read<ClientSessionProvider>();
      await session.refreshMe();

      if (!mounted) return;
      if (resp.existing) {
        showAuthToast(
          context,
          'Welcome back — also linked to ${resp.agent.fullName}.',
        );
      }
      Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.statusCode == 429
            ? 'Too many sign-ups from this device, try again later'
            : e.statusCode == 422
                ? e.message
                : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not sign up. Check your connection.';
      });
    }
  }

  Widget _agentCard() {
    if (_loadingAgent || _agent == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: AppTheme.cardGradient(context),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          boxShadow: AppTheme.softShadow(context),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.surface2(context),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    width: 180,
                    decoration: BoxDecoration(
                      color: AppTheme.surface2(context),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 12,
                    width: 120,
                    decoration: BoxDecoration(
                      color: AppTheme.surface2(context).withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final a = _agent!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: AppTheme.softShadow(context),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppTheme.surface2(context),
            backgroundImage: a.photoUrl != null && a.photoUrl!.isNotEmpty
                ? NetworkImage(a.photoUrl!)
                : null,
            child: a.photoUrl == null || a.photoUrl!.isEmpty
                ? Text(
                    a.firstName.isNotEmpty ? a.firstName[0] : '?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary(context),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Signing up with',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  a.fullName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                if (a.agency != null)
                  Text(
                    a.agency!.name,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Create account',
      subtitle: 'Sign up with your agent to start tracking your matches.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _agentCard(),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _firstName,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.givenName],
                    decoration:
                        const InputDecoration(hintText: 'First name'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Required'
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _lastName,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.familyName],
                    decoration: const InputDecoration(hintText: 'Surname'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Required'
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: const InputDecoration(
                hintText: 'Cell phone',
                prefixIcon: Icon(Icons.phone_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                hintText: 'Email',
                prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter your email';
                if (!v.contains('@')) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                hintText: 'Password',
                prefixIcon: Icon(Icons.lock_outline_rounded, size: 20),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter a password';
                if (v.length < 8) return 'At least 8 characters';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'Confirm password',
                prefixIcon: Icon(Icons.lock_outline_rounded, size: 20),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Confirm your password';
                if (v != _password.text) return 'Passwords do not match';
                return null;
              },
            ),
            if (_error != null) AuthError(_error!),
            const SizedBox(height: 24),
            GlowButton(
              onPressed: (_busy || _loadingAgent) ? null : _submit,
              loading: _busy,
              child: const Text('Create account'),
            ),
          ],
        ),
      ),
    );
  }
}
