import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/client_session_provider.dart';
import '../../../services/api_service.dart' show ApiException;
import '../../../services/client_auth_service.dart';
import '../../../widgets/ui/auth_scaffold.dart';
import '../../../widgets/ui/glow_button.dart';
import 'client_auth_shared.dart';
import 'client_otp_screen.dart';
import 'client_set_password_screen.dart';

// Screen 4 — returning client signs in with email + password.
class ClientPasswordScreen extends StatefulWidget {
  final String email;
  const ClientPasswordScreen({super.key, required this.email});

  @override
  State<ClientPasswordScreen> createState() => _ClientPasswordScreenState();
}

class _ClientPasswordScreenState extends State<ClientPasswordScreen> {
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _api = ClientAuthService();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final resp = await _api.login(
        email: widget.email,
        password: _passwordController.text,
        deviceName: defaultDeviceName(),
      );

      await _api.saveToken(resp.token);
      if (!mounted) return;

      final session = context.read<ClientSessionProvider>();
      session.applyLogin(resp);

      if (resp.client.passwordMustChange) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => ClientSetPasswordScreen(
              bearerToken: resp.token,
              isFromActivation: false,
            ),
          ),
          (r) => false,
        );
        return;
      }

      // Return to the root: AuthGate renders the agency picker (if multiple
      // agencies and not locked) or the client home from session state.
      Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.statusCode == 422
            ? 'Invalid credentials'
            : e.statusCode == 429
                ? 'Too many requests. Please slow down.'
                : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not sign in. Check your connection.';
      });
    }
  }

  Future<void> _forgot() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.forgotPassword(widget.email);
      if (!mounted) return;
      setState(() => _busy = false);
      showAuthToast(context, 'Code sent. Check your email.');
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ClientOtpScreen(
            email: widget.email,
            purpose: OtpPurpose.recovery,
          ),
        ),
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
        _error = 'Could not start recovery. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Welcome back',
      subtitle: widget.email,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(
                hintText: 'Password',
                prefixIcon: Icon(Icons.lock_outline_rounded, size: 20),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Enter your password' : null,
            ),
            if (_error != null) AuthError(_error!),
            const SizedBox(height: 24),
            GlowButton(
              onPressed: _busy ? null : _signIn,
              loading: _busy,
              child: const Text('Sign in'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _forgot,
              child: const Text('Forgot password?'),
            ),
          ],
        ),
      ),
    );
  }
}
