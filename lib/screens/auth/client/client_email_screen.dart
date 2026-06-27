import 'package:flutter/material.dart';

import '../../../services/api_service.dart' show ApiException;
import '../../../services/client_auth_service.dart';
import '../../../widgets/ui/auth_scaffold.dart';
import '../../../widgets/ui/glow_button.dart';
import 'client_otp_screen.dart';
import 'client_password_screen.dart';

// Screen 1 — email entry.
// Hits POST /v1/client-auth/lookup and routes based on the response shape.
class ClientEmailScreen extends StatefulWidget {
  const ClientEmailScreen({super.key});

  @override
  State<ClientEmailScreen> createState() => _ClientEmailScreenState();
}

class _ClientEmailScreenState extends State<ClientEmailScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _api = ClientAuthService();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _api.lookup(email);
      if (!mounted) return;
      if (!result.exists) {
        setState(() {
          _busy = false;
          _error = result.message ??
              'You are not on any agency contact list. Ask your agent to add you.';
        });
        return;
      }
      if (result.requiresOtp) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ClientOtpScreen(email: email, purpose: OtpPurpose.activation),
          ),
        );
      } else if (result.requiresPassword) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ClientPasswordScreen(email: email),
          ),
        );
      } else {
        setState(() {
          _busy = false;
          _error = result.message ??
              'Your account needs attention. Please contact your agent to continue.';
        });
        return;
      }
      if (mounted) setState(() => _busy = false);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.statusCode == 429
            ? 'Too many requests. Please slow down.'
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not reach the server. Check your connection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Welcome',
      subtitle:
          'Enter the email your agent has on file. We\'ll take you to the right next step.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _emailController,
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
            if (_error != null) AuthError(_error!),
            const SizedBox(height: 24),
            GlowButton(
              onPressed: _busy ? null : _continue,
              loading: _busy,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
