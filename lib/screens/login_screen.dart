import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/env.dart';
import '../models/branding.dart';
import '../theme.dart';
import '../providers/auth_provider.dart';
import '../providers/branding_provider.dart';
import '../services/api_service.dart';
import '../services/security_service.dart';
import '../widgets/ui/glow_background.dart';
import '../widgets/ui/glow_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _biometricSupported = false;
  bool _autoTried = false;

  bool? _demoEnabled;
  List<String> _demoRoles = const [];
  String? _demoBusyRole;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthProvider>();
    unawaited(context.read<BrandingProvider>().loadBySlug(Env.agencySlug));
    unawaited(_checkDemoStatus());
    final saved = await auth.readSavedCredentials();
    final supported = await SecurityService.instance.canUseBiometrics();
    if (!mounted) return;
    setState(() {
      _emailController.text = saved.email;
      _passwordController.text = saved.password;
      _biometricSupported = supported;
    });

    if (!_autoTried && auth.isLocked && auth.biometricEnabled && supported) {
      _autoTried = true;
      await auth.unlockWithBiometrics();
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkDemoStatus() async {
    try {
      final status = await ApiService().getDemoStatus();
      if (!mounted) return;
      setState(() {
        _demoEnabled = status.enabled;
        _demoRoles = status.roles;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _demoEnabled = false);
    }
  }

  Future<void> _handleDemoLogin(String role) async {
    setState(() => _demoBusyRole = role);
    final auth = context.read<AuthProvider>();
    final ok = await auth.loginAsDemo(role);
    if (!mounted) return;
    setState(() => _demoBusyRole = null);
    if (ok) {
      unawaited(
        context.read<BrandingProvider>().loadFromLoggedUser(profile: auth.user),
      );
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error ?? 'Could not start demo session')),
      );
    }
  }

  static const _demoRoleLabels = {
    'admin': 'Admin',
    'branch_manager': 'Branch Manager',
    'agent': 'Agent',
    'viewer': 'Viewer',
  };

  List<Widget> _buildDemoButtons() {
    final auth = context.watch<AuthProvider>();
    final roles = _demoRoles.isNotEmpty
        ? _demoRoles
        : _demoRoleLabels.keys.toList();
    final widgets = <Widget>[
      Text(
        'DEMO MODE',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 2.0,
          color: AppTheme.textSecondary(context),
        ),
      ),
      const SizedBox(height: 18),
    ];
    for (var i = 0; i < roles.length; i++) {
      final role = roles[i];
      final label = _demoRoleLabels[role] ?? role;
      final busy = _demoBusyRole == role;
      final disabled = _demoBusyRole != null;
      widgets.add(
        GlowButton(
          onPressed: disabled ? null : () => _handleDemoLogin(role),
          loading: busy,
          child: Text(label),
        ),
      );
      if (i != roles.length - 1) widgets.add(const SizedBox(height: 12));
    }
    if (auth.error != null) {
      widgets.add(const SizedBox(height: 16));
      widgets.add(Text(
        auth.error!,
        style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13),
      ));
    }
    return widgets;
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    if (auth.isLocked) {
      auth.lockSession();
    }

    final ok = await auth.login(
      _emailController.text.trim(),
      _passwordController.text,
    );
    if (!mounted) return;
    if (ok) {
      unawaited(
        context
            .read<BrandingProvider>()
            .loadFromLoggedUser(profile: auth.user),
      );
    }
    if (ok && auth.needsBiometricSetupPrompt) {
      await _askEnableBiometrics();
    }
    if (ok && mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Future<void> _askEnableBiometrics() async {
    final auth = context.read<AuthProvider>();
    final enable = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Enable biometric sign-in?'),
            content: const Text(
              'Use this device’s fingerprint or face unlock to sign in '
              'next time, instead of typing your password.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Not now'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Enable'),
              ),
            ],
          ),
        ) ??
        false;
    await auth.consumeBiometricSetupPrompt(enable: enable);
  }

  Future<void> _handleBiometric() async {
    final auth = context.read<AuthProvider>();
    if (auth.isLocked) {
      await auth.unlockWithBiometrics();
      return;
    }
    final ok = await SecurityService.instance.authenticate(
      reason: 'Sign in to CoreX',
    );
    if (!ok) return;
    final saved = await auth.readSavedCredentials();
    if (saved.email.isEmpty || saved.password.isEmpty) return;
    await auth.login(saved.email, saved.password);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final branding = context.watch<BrandingProvider>().branding;
    final brand = BrandColors.of(context);
    final showBiometric = _biometricSupported && auth.biometricEnabled;
    final showDemo = _demoEnabled == true;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: GlowBackground(
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
                    children: [
                      _Logo(branding: branding, tint: brand.button),
                      const SizedBox(height: 28),
                      Text(
                        auth.isLocked ? 'Welcome back' : 'CoreX OS',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      if (auth.isLocked) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Unlock to continue'.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.0,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                      ],
                      const SizedBox(height: 40),
                      if (showDemo) ..._buildDemoButtons()
                      else ...[
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [
                            AutofillHints.username,
                            AutofillHints.email
                          ],
                          style: TextStyle(
                              color: AppTheme.textPrimary(context),
                              fontWeight: FontWeight.w500),
                          decoration: const InputDecoration(
                            hintText: 'Email',
                            prefixIcon:
                                Icon(Icons.mail_outline_rounded, size: 20),
                          ),
                          validator: (v) =>
                              v == null || v.isEmpty ? 'Enter your email' : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          autofillHints: const [AutofillHints.password],
                          style: TextStyle(
                              color: AppTheme.textPrimary(context),
                              fontWeight: FontWeight.w500),
                          decoration: const InputDecoration(
                            hintText: 'Password',
                            prefixIcon:
                                Icon(Icons.lock_outline_rounded, size: 20),
                          ),
                          validator: (v) => v == null || v.isEmpty
                              ? 'Enter your password'
                              : null,
                        ),
                        if (auth.error != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            auth.error!,
                            style: const TextStyle(
                                color: Color(0xFFEF4444), fontSize: 13),
                          ),
                        ],
                        const SizedBox(height: 24),
                        GlowButton(
                          onPressed: auth.isLoading ? null : _handleLogin,
                          loading: auth.isLoading,
                          child: const Text('Sign in'),
                        ),
                        if (showBiometric) ...[
                          const SizedBox(height: 14),
                          SoftButton(
                            icon: Icons.fingerprint_rounded,
                            onPressed:
                                auth.isLoading ? null : _handleBiometric,
                            child: const Text('Use biometrics'),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CorexAssetLogo extends StatelessWidget {
  const _CorexAssetLogo();

  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/images/corex_logo.png', fit: BoxFit.contain);
}

class _Logo extends StatelessWidget {
  final Branding branding;
  final Color tint;

  const _Logo({required this.branding, required this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppTheme.brandGlow(tint, intensity: 0.28, blur: 36),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: branding.logoUrl != null
            ? Image.network(
                branding.logoUrl!,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const _CorexAssetLogo(),
              )
            : const _CorexAssetLogo(),
      ),
    );
  }
}
