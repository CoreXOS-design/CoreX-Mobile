import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/client_session_provider.dart';
import '../../../services/api_service.dart' show ApiException;
import '../../../services/client_auth_service.dart';
import '../../../widgets/ui/auth_scaffold.dart';
import '../../../widgets/ui/glow_button.dart';
import 'client_auth_shared.dart';

class ClientSetPasswordScreen extends StatefulWidget {
  final String bearerToken;
  final bool isFromActivation;

  const ClientSetPasswordScreen({
    super.key,
    required this.bearerToken,
    required this.isFromActivation,
  });

  @override
  State<ClientSetPasswordScreen> createState() =>
      _ClientSetPasswordScreenState();
}

class _ClientSetPasswordScreenState extends State<ClientSetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _api = ClientAuthService();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final resp = await _api.setPassword(
        bearer: widget.bearerToken,
        password: _passwordController.text,
        passwordConfirmation: _confirmController.text,
        deviceName: defaultDeviceName(),
      );

      await _api.saveToken(resp.token);
      if (!mounted) return;

      final session = context.read<ClientSessionProvider>();
      session.applyLogin(resp);
      session.clearPasswordMustChange();

      // Return to the root: AuthGate renders the agency picker (if multiple
      // agencies and not locked) or the client home from session state.
      Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.statusCode == 422
            ? e.message
            : e.statusCode == 401
                ? 'Activation expired. Please request a new code.'
                : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save password. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: widget.isFromActivation ? 'Create password' : 'Update password',
      subtitle: widget.isFromActivation
          ? 'Choose a password you will use to sign in next time.'
          : 'Your agent set a temporary password. Pick a new one to continue.',
      showBack: widget.isFromActivation,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                hintText: 'New password',
                prefixIcon: Icon(Icons.lock_outline_rounded, size: 20),
              ),
              validator: (v) {
                if (v == null || v.length < 8) {
                  return 'At least 8 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirmController,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'Confirm password',
                prefixIcon: Icon(Icons.lock_outline_rounded, size: 20),
              ),
              validator: (v) {
                if (v != _passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            if (_error != null) AuthError(_error!),
            const SizedBox(height: 24),
            GlowButton(
              onPressed: _busy ? null : _submit,
              loading: _busy,
              child: const Text('Create password & sign in'),
            ),
          ],
        ),
      ),
    );
  }
}
