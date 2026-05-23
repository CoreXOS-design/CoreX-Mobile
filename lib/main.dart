import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'config/env.dart';
import 'models/branding.dart';
import 'theme.dart';
import 'providers/auth_provider.dart';
import 'providers/branding_provider.dart';
import 'providers/client_session_provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/notifications_provider.dart';
import 'providers/property_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/visibility_provider.dart';
import 'screens/auth/client/client_set_password_screen.dart';
import 'screens/auth/login_choice_screen.dart';
import 'screens/client/client_home_screen.dart';
import 'screens/home_hub_screen.dart';
import 'screens/splash_screen.dart';
import 'services/client_auth_service.dart';
import 'services/messaging_service.dart';
import 'services/security_service.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Force normal (non-immersive) system UI so the Android home pill /
  // gesture bar always responds — without this, any screen that ever
  // entered immersive mode can leave the gesture bar in a stuck state.
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
    overlays: SystemUiOverlay.values,
  );
  await dotenv.load(fileName: '.env');
  // Touch Env early so dotenv reads happen on the main isolate.
  Env.apiBaseUrl;
  try {
    await Firebase.initializeApp();
    await MessagingService.instance.init(navigatorKey: rootNavigatorKey);
  } catch (e) {
    debugPrint('[firebase] init failed: $e');
  }
  await _requestInitialPermissions();
  runApp(const CoreXApp());
}

Future<void> _requestInitialPermissions() async {
  final cameraStatus = await Permission.camera.status;
  if (!cameraStatus.isGranted && !cameraStatus.isPermanentlyDenied) {
    await Permission.camera.request();
  }

  final notificationStatus = await Permission.notification.status;
  if (!notificationStatus.isGranted && !notificationStatus.isPermanentlyDenied) {
    await Permission.notification.request();
  }
}

class CoreXApp extends StatelessWidget {
  const CoreXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => BrandingProvider()
            ..restore().then((_) {
              // Pre-login pass: refresh from /v1/branding/{slug} on launch so
              // first-time users still get the right colours before signing in.
              // Post-login flows overwrite via /v1/logged-user.
            }),
        ),
        ChangeNotifierProvider(create: (_) => AuthProvider()..checkAuth()),
        ChangeNotifierProvider(
            create: (_) => ClientSessionProvider()..bootstrap()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => NotificationsProvider()),
        ChangeNotifierProvider(create: (_) => PropertyProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => VisibilityProvider()),
      ],
      child: Consumer2<ThemeProvider, BrandingProvider>(
        builder: (context, themeProvider, brandingProvider, _) {
          final Branding b = brandingProvider.branding;
          debugPrint('[branding] MaterialApp rebuild: '
              'primary=${b.button.toARGB32().toRadixString(16)}');
          return MaterialApp(
            title: 'CoreX OS',
            debugShowCheckedModeBanner: false,
            navigatorKey: rootNavigatorKey,
            theme: AppTheme.light(b),
            darkTheme: AppTheme.dark(b),
            themeMode: themeProvider.themeMode,
            home: const _InactivityGate(child: _AppBootstrap()),
          );
        },
      ),
    );
  }
}

/// Locks the session back to the LoginScreen after [_idleTimeout] of no
/// pointer activity, and again whenever the app comes back from background.
class _InactivityGate extends StatefulWidget {
  final Widget child;
  const _InactivityGate({required this.child});

  @override
  State<_InactivityGate> createState() => _InactivityGateState();
}

class _InactivityGateState extends State<_InactivityGate>
    with WidgetsBindingObserver {
  static const Duration _idleTimeout = Duration(minutes: 5);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resetTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Lock immediately when the app is backgrounded/inactive — re-entry must
    // pass the login or biometric prompt again.
    // Suppress lock-on-lifecycle while a system biometric/credential prompt
    // is showing — the prompt itself fires inactive/paused, which would
    // otherwise re-lock the session mid-authentication.
    if (SecurityService.isAuthenticating) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _lock();
    } else if (state == AppLifecycleState.resumed) {
      _resetTimer();
    }
  }

  void _resetTimer() {
    _timer?.cancel();
    _timer = Timer(_idleTimeout, _lock);
  }

  void _lock() {
    final auth = rootNavigatorKey.currentContext?.read<AuthProvider>();
    auth?.lockSession();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetTimer(),
      onPointerMove: (_) => _resetTimer(),
      child: widget.child,
    );
  }
}

class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  bool _splashDone = false;
  bool _brandingPulled = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final clientSession = context.watch<ClientSessionProvider>();
    // Splash stays up until the animation finishes AND we have a definitive
    // auth answer. The two providers are mutually exclusive (agent xor client),
    // so the moment either reports logged-in we can advance — no need to wait
    // on the other. If both come back logged-out we wait for both to settle so
    // the login screen has the correct branding state. Each provider has its
    // own 8s timeout, so the splash is bounded even if the network hangs.
    final eitherLoggedIn = auth.isLoggedIn || clientSession.isLoggedIn;
    final bothSettled = !auth.isChecking && !clientSession.isChecking;
    if (!_splashDone || (!eitherLoggedIn && !bothSettled)) {
      return SplashScreen(
        onFinished: () => setState(() => _splashDone = true),
      );
    }
    // Pull /v1/logged-user every time auth flips to logged-in (cold start
    // OR fresh login), and reset the latch on logout so the next sign-in
    // re-fetches. Failure falls back silently to cached/default branding.
    if (auth.isLoggedIn && !_brandingPulled) {
      _brandingPulled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final profile = context.read<AuthProvider>().user;
        context.read<BrandingProvider>().loadFromLoggedUser(profile: profile);
        // Refresh agent visibility on every login / cold start. Failure
        // falls back silently to own-only with no filter UI.
        context.read<VisibilityProvider>().refresh();
      });
    } else if (!auth.isLoggedIn && _brandingPulled) {
      _brandingPulled = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<VisibilityProvider>().reset();
      });
    }
    return const AuthGate();
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final clientSession = context.watch<ClientSessionProvider>();

    // Client takes precedence: a client signing in on a device that also has
    // a saved user token (rare but possible) lands on the client portal,
    // not the agent app.
    if (clientSession.isLoggedIn) {
      if (clientSession.passwordMustChange) {
        // Forced rotation — bounce to set-password before showing home.
        return FutureBuilder<String?>(
          future: ClientAuthService().getToken(),
          builder: (_, snap) {
            if (!snap.hasData || snap.data == null) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }
            return ClientSetPasswordScreen(
              bearerToken: snap.data!,
              isFromActivation: false,
            );
          },
        );
      }
      return const ClientHomeScreen();
    }

    if (auth.isLoggedIn) {
      return const HomeHubScreen();
    }
    return const LoginChoiceScreen();
  }
}
