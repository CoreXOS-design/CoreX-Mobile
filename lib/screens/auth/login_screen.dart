import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../config/app_version.dart';
import '../../main.dart' show rootNavigatorKey;
import '../../providers/auth_provider.dart';
import '../../providers/client_session_provider.dart';
import '../../services/api_service.dart' show ApiException;
import '../../services/client_auth_service.dart';
import '../../services/security_service.dart';
import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';
import '../../widgets/corex/corex_monogram.dart';
import '../../widgets/corex/corex_primary_button.dart';
import '../../widgets/corex/corex_secondary_button.dart';
import 'client/client_agent_qr_scanner_screen.dart';
import 'client/client_auth_shared.dart';
import 'client/client_otp_screen.dart';
import 'client/client_set_password_screen.dart';

/// Unified single-button login.
///
/// Flow:
/// 1. Try AuthProvider.login (user app).
/// 2. On failure, call ClientAuthService.lookup(email):
///    - !exists → onboarding hint (ask your agency / scan agent QR)
///    - requiresOtp → push ClientOtpScreen (activation)
///    - requiresPassword → ClientAuthService.login; on success → AuthGate
///      flips to ClientHomeScreen; on fail → generic error.
///
/// Wrong-password failures all share one generic error string so the screen
/// can't be used to brute-force passwords. The unknown-email case is called
/// out separately on purpose: a new user needs to know they aren't in the
/// system yet, not that they mistyped a password.
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
  bool _autoUnlockTried = false;

  /// False on devices where fingerprint sign-in isn't offered — notably Face
  /// ID iPhones, which are excluded by product decision. Starts false so the
  /// unlock button can't flash up before the check answers.
  bool _fingerprintAvailable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    // The email is prefilled from our own store; the password is left to the
    // OS password manager via autofill — the app never keeps a copy.
    final email = await auth.readSavedEmail();
    final fingerprint = await SecurityService.instance.canUseFingerprint();
    if (!mounted) return;
    setState(() {
      if (_emailCtl.text.isEmpty) _emailCtl.text = email;
      _fingerprintAvailable = fingerprint;
    });
    // Small beat before the system sheet: local_auth needs a resumed activity,
    // and firing it in the same frame the splash hands over can have the
    // platform reject the call outright.
    await Future.delayed(const Duration(milliseconds: 300));
    await _tryBiometricUnlock(auto: true);
  }

  /// Biometrics enabled + a token still on the device → offer the system
  /// prompt. Runs once automatically when the screen opens (this is the
  /// "app reopened" sign-in), and the on-screen button re-runs it after a
  /// cancel. Anything short of success leaves the password form in charge.
  Future<void> _tryBiometricUnlock({bool auto = false}) async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    // Opt-in plus a device that offers fingerprint. The capability check is
    // what keeps Face ID iPhones out of this path entirely.
    if (!auth.canUnlockWithBiometrics || !_fingerprintAvailable) return;
    if (auto) {
      if (_autoUnlockTried) return;
      _autoUnlockTried = true;
    }
    final result = await auth.unlockWithBiometrics();
    if (!mounted || result == BiometricUnlock.success) return;
    switch (result) {
      case BiometricUnlock.sessionExpired:
        setState(() =>
            _error = 'Your session has expired. Sign in with your password.');
      case BiometricUnlock.cancelled:
        if (!auto) {
          setState(
              () => _error = 'Biometric check failed. Enter your password.');
        }
      case BiometricUnlock.success:
      case BiometricUnlock.unavailable:
        break;
    }
  }

  @override
  void dispose() {
    _emailCtl.dispose();
    _passwordCtl.dispose();
    super.dispose();
  }

  /// Closes the autofill context so the OS password manager offers to save
  /// what was just typed. Only called after the credentials are known-good —
  /// firing it on a failed attempt would offer to save a wrong password.
  void _offerToSaveCredentials() {
    TextInput.finishAutofillContext();
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
    if (ok) {
      _offerToSaveCredentials();
      // First sign-in on this device — offer fingerprint unlock for next time.
      // AuthGate handles the swap to HomeScreen underneath.
      //
      // Deliberately not gated on `mounted`: that swap disposes this State as
      // soon as login succeeds, so checking it here would drop the one-time
      // offer whenever the rebuild wins the race. Nothing below touches this
      // widget — the dialog is shown on the root navigator precisely so it can
      // outlive the screen that triggered it.
      if (auth.needsBiometricSetupPrompt) {
        await _askEnableBiometrics(auth);
      }
      return;
    }
    // Every path from here on calls setState, so the guard belongs here rather
    // than above.
    if (!mounted) return;
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
        // Truly unknown email — not a user and not a client. Guide them to get
        // onboarded rather than implying a wrong password.
        setState(() {
          _busy = false;
          _error = 'We couldn’t find that email. Ask your agency to add you, '
              'or scan your agent’s QR code to get started.';
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
      _offerToSaveCredentials();

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

      // AuthGate decides what comes next from session state — agency picker
      // (if multiple agencies and not locked) or the client home — on the next
      // frame. Nothing to push here.
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

  /// One-time offer, right after the first successful sign-in on this device.
  /// Shown on the root navigator because AuthGate is already swapping this
  /// screen out for the home shell underneath the dialog.
  ///
  /// Declining is remembered too — [AuthProvider.consumeBiometricSetupPrompt]
  /// marks the prompt as shown either way, so it never nags. Settings has the
  /// toggle for anyone who changes their mind.
  Future<void> _askEnableBiometrics(AuthProvider auth) async {
    final dialogContext = rootNavigatorKey.currentContext;
    if (dialogContext == null) {
      await auth.consumeBiometricSetupPrompt(enable: false);
      return;
    }
    final enable = await showDialog<bool>(
          context: dialogContext,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            icon: Icon(
              TablerIcons.fingerprint,
              size: 40,
              color: CorexAccentTheme.of(ctx).accent,
            ),
            title: const Text('Use your fingerprint to sign in?'),
            content: const Text(
              'Unlock CoreX with your fingerprint next time instead of typing '
              'your password.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Not now'),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(ctx).pop(true),
                icon: const Icon(TablerIcons.fingerprint, size: 18),
                label: const Text('Enable'),
              ),
            ],
          ),
        ) ??
        false;
    final enabled = await auth.consumeBiometricSetupPrompt(enable: enable);
    // Confirming can still fail (platform refusal, no enrolment, a cancel on
    // the system sheet). Say so rather than leaving them expecting a prompt
    // on the next launch that never arrives.
    if (enable && !enabled) {
      final messenger = ScaffoldMessenger.maybeOf(
        rootNavigatorKey.currentContext ?? dialogContext,
      );
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Biometric sign-in wasn’t enabled. You can turn it on in Settings.',
          ),
        ),
      );
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
    final auth = context.watch<AuthProvider>();
    final canUnlock = auth.canUnlockWithBiometrics && _fingerprintAvailable;
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
                    // Groups the two fields into one autofill context so the
                    // OS password manager treats them as a single credential
                    // — required for the "save password?" prompt fired from
                    // [_submit] to carry both.
                    child: AutofillGroup(
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
                          autofillHints: const [
                            AutofillHints.username,
                            AutofillHints.email,
                          ],
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
                        if (canUnlock) ...[
                          const SizedBox(height: 12),
                          CorexSecondaryButton(
                            label: 'Unlock with fingerprint',
                            leading: TablerIcons.fingerprint,
                            onPressed:
                                _busy ? null : () => _tryBiometricUnlock(),
                          ),
                        ],
                        const SizedBox(height: 12),
                        CorexSecondaryButton(
                          label: 'Scan agent QR',
                          leading: TablerIcons.qrcode,
                          onPressed: _busy ? null : _scanQr,
                        ),
                        const SizedBox(height: 32),
                        Text(
                          'v$kAppVersion',
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
      // The OS password manager (Google Password Manager / iCloud Keychain)
      // owns saving and filling these. CoreX itself still never writes the
      // password to its own storage.
      autofillHints: autofillHints,
      autocorrect: false,
      enableSuggestions: false,
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
