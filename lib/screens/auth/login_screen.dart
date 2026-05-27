import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../providers/auth_provider.dart';
import '../../providers/client_session_provider.dart';
import '../../services/api_service.dart' show ApiException;
import '../../services/client_auth_service.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../widgets/corex/corex_monogram.dart';
import '../../widgets/corex/corex_primary_button.dart';
import '../../widgets/corex/corex_secondary_button.dart';
import 'client/client_agency_picker_screen.dart';
import 'client/client_agent_qr_scanner_screen.dart';
import 'client/client_auth_shared.dart';
import 'client/client_otp_screen.dart';
import 'client/client_set_password_screen.dart';

/// Unified single-button login.
///
/// Flow:
/// 1. Try AuthProvider.login (user app).
/// 2. On failure, call ClientAuthService.lookup(email):
///    - !exists → generic error
///    - requiresOtp → push ClientOtpScreen (activation)
///    - requiresPassword → ClientAuthService.login; on success → AuthGate
///      flips to ClientHomeScreen; on fail → generic error.
///
/// Generic error string is identical across every failure path so the screen
/// cannot be used to enumerate accounts.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _genericError = 'Email or password is incorrect.';

  final _emailCtl = TextEditingController();
  final _passwordCtl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _clientApi = ClientAuthService();

  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _activationEmail;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final saved =
          await context.read<AuthProvider>().readSavedCredentials();
      if (!mounted) return;
      if (_emailCtl.text.isEmpty) _emailCtl.text = saved.email;
      if (_passwordCtl.text.isEmpty) _passwordCtl.text = saved.password;
    });
  }

  @override
  void dispose() {
    _emailCtl.dispose();
    _passwordCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final email = _emailCtl.text.trim();
    final password = _passwordCtl.text;
    setState(() {
      _busy = true;
      _error = null;
      _activationEmail = null;
    });

    // Step 1: user app login.
    final auth = context.read<AuthProvider>();
    final ok = await auth.login(email, password);
    if (!mounted) return;
    if (ok) {
      // AuthGate handles the swap to HomeScreen.
      return;
    }
    // 401 = the email is a known user, password was wrong. Don't leak into the
    // client lookup flow — show a clear password error and stop here.
    if (auth.lastLoginStatus == 401) {
      setState(() {
        _busy = false;
        _error = 'Incorrect password.';
      });
      return;
    }

    // Step 2: not a user (or unreachable) → client lookup → routing.
    try {
      final result = await _clientApi.lookup(email);
      if (!mounted) return;

      if (!result.exists) {
        setState(() {
          _busy = false;
          _error = _genericError;
        });
        return;
      }

      if (result.requiresOtp) {
        // Pending client — surface an explicit activation prompt instead of
        // silently navigating to the OTP page (a wrong password on a pending
        // account would otherwise look like it "took them to OTP").
        setState(() {
          _busy = false;
          _activationEmail = email;
          _error = null;
        });
        return;
      }

      // Active client — sign in with the password they just typed.
      await _signInClient(email, password);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.statusCode == 429
            ? 'Too many attempts. Please try again in a minute.'
            : _genericError;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not reach the server. Check your connection.';
      });
    }
  }

  Future<void> _signInClient(String email, String password) async {
    try {
      final resp = await _clientApi.login(
        email: email,
        password: password,
        deviceName: defaultDeviceName(),
      );
      await _clientApi.saveToken(resp.token);
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

      if (resp.client.lockedToAgencyId == null &&
          resp.client.currentAgencyId == null &&
          resp.agencies.length > 1) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const ClientAgencyPickerScreen(initialPick: true),
          ),
          (r) => false,
        );
        return;
      }
      // AuthGate will flip to ClientHomeScreen on the next frame.
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.statusCode == 429
            ? 'Too many attempts. Please try again in a minute.'
            : _genericError;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not reach the server. Check your connection.';
      });
    }
  }

  void _scanQr() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ClientAgentQrScannerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: CorexTokens.pageBase(context),
        body: Container(
          decoration: BoxDecoration(gradient: CorexTokens.pageBacklight(context)),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 12),
                        const Center(child: CorexMonogram()),
                        const SizedBox(height: 24),
                        _Wordmark(accent: t.accent),
                        const SizedBox(height: 14),
                        Center(
                          child: Text(
                            'YOUR REAL ESTATE OS',
                            style: TextStyle(
                              color: CorexTokens.textSecondary(context),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        _input(
                          controller: _emailCtl,
                          hint: 'Email',
                          icon: TablerIcons.mail,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.next,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Enter your email';
                            }
                            if (!v.contains('@')) {
                              return 'Enter a valid email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _input(
                          controller: _passwordCtl,
                          hint: 'Password',
                          icon: TablerIcons.lock,
                          obscure: _obscure,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          suffix: IconButton(
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure ? TablerIcons.eye : TablerIcons.eye_off,
                              color: CorexTokens.textTertiary(context),
                              size: 20,
                            ),
                          ),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Enter your password'
                              : null,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFEF4444),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        if (_activationEmail != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            'This account hasn’t been activated yet. '
                            'Send a code to your email to set a password.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: CorexTokens.textSecondary(context),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 12),
                          CorexSecondaryButton(
                            label: 'Activate account',
                            leading: TablerIcons.mail,
                            onPressed: _busy
                                ? null
                                : () {
                                    final email = _activationEmail!;
                                    setState(() => _activationEmail = null);
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ClientOtpScreen(
                                          email: email,
                                          purpose: OtpPurpose.activation,
                                        ),
                                      ),
                                    );
                                  },
                          ),
                        ],
                        const SizedBox(height: 36),
                        CorexPrimaryButton(
                          label: 'Continue to your workspace',
                          loading: _busy,
                          onPressed: _busy ? null : _submit,
                        ),
                        const SizedBox(height: 12),
                        CorexSecondaryButton(
                          label: 'Scan agent QR',
                          leading: TablerIcons.qrcode,
                          onPressed: _busy ? null : _scanQr,
                        ),
                        const SizedBox(height: 32),
                        Text(
                          'v 2026.5.25',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: CorexTokens.textMuted(context),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboardType,
    Iterable<String>? autofillHints,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    Widget? suffix,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      style: TextStyle(color: CorexTokens.textPrimary(context), fontSize: 14),
      cursorColor: CorexAccentTheme.of(context).accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: CorexTokens.textTertiary(context)),
        prefixIcon: Icon(icon, color: CorexTokens.textTertiary(context), size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CorexTokens.radiusButton),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CorexTokens.radiusButton),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CorexTokens.radiusButton),
          borderSide: BorderSide(
            color: CorexAccentTheme.of(context).accentBorder,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  final Color accent;
  const _Wordmark({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'CoreX',
          style: TextStyle(
            color: CorexTokens.textPrimary(context),
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(width: 8),
        ShaderMask(
          shaderCallback: (rect) => LinearGradient(
            colors: [
              Color.lerp(accent, Colors.white, 0.15)!,
              accent,
            ],
          ).createShader(rect),
          child: const Text(
            'OS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
        ),
      ],
    );
  }
}
