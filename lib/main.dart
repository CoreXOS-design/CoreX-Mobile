import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'config/env.dart';
import 'models/branding.dart';
import 'theme.dart';
import 'providers/auth_provider.dart';
import 'providers/branding_provider.dart';
import 'providers/client_matches_provider.dart';
import 'providers/client_session_provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/notifications_provider.dart';
import 'providers/portal_leads_provider.dart';
import 'providers/property_provider.dart';
import 'providers/seller_listings_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/visibility_provider.dart';
import 'screens/auth/client/client_agency_picker_screen.dart';
import 'screens/auth/client/client_set_password_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/client/client_home_screen.dart';
import 'screens/force_update_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/splash_screen.dart';
import 'services/app_update_service.dart';
import 'services/client_auth_service.dart';
import 'services/messaging_service.dart';
import 'utils/app_time.dart';
import 'widgets/update_available_dialog.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Printed once the first frame has actually been rendered.
///
/// The simulator launch smoke test in `codemagic.yaml` greps for this exact
/// string, so the two have to stay in step. A live process is **not** proof of
/// a successful launch: `main` throwing before [runApp] leaves the app running
/// and showing a black screen, with no crash report — which is exactly what
/// App Review files as "crashed on launch". This is the only signal that
/// distinguishes the two.
const String kFirstFrameMarker = 'COREX_FIRST_FRAME_OK';

/// Signs the current agent out and hard-resets navigation to a fresh app root.
///
/// We can't rely on [AuthGate] reactively swapping to the login screen: the
/// bottom-nav tabs use `pushReplacement` / `pushAndRemoveUntil`, which remove
/// the original [AuthGate] route from the stack. Once that's gone, flipping
/// `isLoggedIn` to false has nothing to react to and the user is stranded on a
/// now-empty home screen. Rebuilding from a fresh [AppBootstrap] restores the
/// cold-start flow (splash → auth check → login) and re-mounts the bootstrap so
/// the next login's branding pull works again.
Future<void> logoutAndReset(BuildContext context) async {
  final branding = context.read<BrandingProvider>();
  final auth = context.read<AuthProvider>();
  branding.reset();
  await auth.logout();
  rootNavigatorKey.currentState?.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const AppBootstrap()),
    (route) => false,
  );
}

/// Cold-start sequence.
///
/// The rule here, after App Review rejected 1.0.9(15) under 2.1(a) for
/// "crashed on launch": **nothing that can fail, hang, or open a system dialog
/// runs before [runApp]**. Anything awaited ahead of the first frame is
/// invisible to the user — they see only the launch storyboard — and a plugin
/// fault, a wedged native call or a missing asset there is indistinguishable
/// from a crash. Only two things now precede [runApp]:
///
///   * `dotenv.load` — [Env] is read during the first build (AuthProvider,
///     AppUpdateService), and it is guarded so a load failure costs
///     configuration, not launch.
///   * `Firebase.initializeApp` — [AuthProvider] holds a [MessagingService],
///     so a default app has to exist by the first build. Bounded by a timeout
///     and guarded.
///
/// Everything else — FCM wiring, the notification permission prompt — is
/// deferred to [_initDeferredServices] after the first frame.
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Report framework errors instead of letting them vanish in release.
    final priorOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      debugPrint('[flutter] uncaught: ${details.exceptionAsString()}');
      priorOnError?.call(details);
    };

    // Fire-and-forget: an Android-only presentation tweak must never gate the
    // first frame on a platform-channel round trip.
    unawaited(SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    ));

    try {
      await dotenv.load(fileName: '.env');
    } catch (e) {
      // Env.* falls back on its own when dotenv never initialised. Loud in the
      // log, invisible to the user — the alternative is main() throwing before
      // runApp, which ships as a black screen.
      debugPrint('[env] .env failed to load, using defaults: $e');
    }

    // Warm the timezone DB so event times render in Africa/Johannesburg
    // regardless of the device's zone.
    initAppTime();

    try {
      await Firebase.initializeApp().timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[firebase] init failed: $e');
    }

    runApp(const CoreXApp());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint(kFirstFrameMarker);
      if (kDebugMode) unawaited(_dropFirstFrameBreadcrumb());
      unawaited(_initDeferredServices());
    });
  }, (error, stack) {
    debugPrint('[zone] uncaught: $error\n$stack');
  });
}

/// Debug-only twin of [kFirstFrameMarker], written into the app's Documents
/// directory so CI can confirm a frame rendered **without** depending on
/// stdout reaching it.
///
/// The first CI run of the smoke test captured the app's NSLog line and its
/// PID but no Dart output at all, which left "the app never rendered" and
/// "the log pipe dropped Dart's stdout" indistinguishable. A file in the app
/// container is readable via `simctl get_app_container` and involves no log
/// plumbing, so the two are now telling apart. Never runs in release.
Future<void> _dropFirstFrameBreadcrumb() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    await File('${dir.path}/$kFirstFrameMarker').writeAsString('ok');
  } catch (e) {
    debugPrint('[boot] breadcrumb failed (harmless): $e');
  }
}

/// Push wiring and the notification prompt, run once the UI is on screen.
///
/// Both used to be awaited inside `main`. [MessagingService.init] blocks on
/// `requestPermission()` and `getInitialMessage()`, so the app sat on the
/// launch image until the user answered a system alert — a hang the OS and a
/// reviewer both read as a failed launch.
Future<void> _initDeferredServices() async {
  try {
    await MessagingService.instance.init(navigatorKey: rootNavigatorKey);
  } catch (e) {
    debugPrint('[messaging] init failed: $e');
  }
  try {
    await _requestInitialPermissions();
  } catch (e) {
    debugPrint('[permissions] initial request failed: $e');
  }
}

Future<void> _requestInitialPermissions() async {
  // Android only. On iOS the notification prompt is already raised by
  // `MessagingService.init` via `FirebaseMessaging.requestPermission()`;
  // asking again through permission_handler pointed a second
  // UNUserNotificationCenter authorisation request at the same alert.
  //
  // Camera is NOT requested here on either platform. Asking up front stacks a
  // second system alert on top of the notification one at cold start — iOS
  // drops queued alerts, leaving permissions in a state the user never
  // actually answered. image_picker raises the camera prompt at the point of
  // capture, which is also what the user expects.
  if (!Platform.isAndroid) return;
  final notificationStatus = await Permission.notification.status;
  if (!notificationStatus.isGranted &&
      !notificationStatus.isPermanentlyDenied) {
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
        ChangeNotifierProvider(create: (_) => PortalLeadsProvider()),
        ChangeNotifierProvider(create: (_) => PropertyProvider()),
        ChangeNotifierProvider(create: (_) => SellerListingsProvider()),
        ChangeNotifierProvider(create: (_) => ClientMatchesProvider()),
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
            home: const AppBootstrap(),
          );
        },
      ),
    );
  }
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> with WidgetsBindingObserver {
  bool _splashDone = false;
  bool _brandingPulled = false;

  /// Null until the first version check answers. The gate is only ever applied
  /// on a definite "you are below the minimum" — see [AppUpdateService], which
  /// fails open on every error path.
  AppUpdateStatus? _update;

  /// Latest optional-update answer, and a once-per-session latch for the
  /// dialog it drives.
  ///
  /// The latch matters because [_checkForUpdate] also runs on every resume:
  /// without it, every trip to another app and back would re-raise the prompt.
  /// Dismissal is remembered across launches too — see
  /// [AppUpdateService.snooze] — so this only guards the within-session case.
  AppUpdateStatus? _softUpdate;
  bool _updatePromptShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkForUpdate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check on resume so raising the cutoff catches agents who keep the app
    // open for days, rather than only those who happen to cold-start after it.
    if (state == AppLifecycleState.resumed) _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    final status = await AppUpdateService.check();
    if (!mounted) return;
    // Only ever latch ON. A check that comes back clean must not clear a gate
    // already in force: the app is unusable at that point, and flickering back
    // into it because one request failed would be worse than staying blocked.
    if (status.updateRequired) {
      setState(() => _update = status);
    } else if (status.updateAvailable && _softUpdate == null) {
      // Held until the user is actually inside the app — see the build method.
      setState(() => _softUpdate = status);
    }
  }

  /// Raises the optional update dialog once the user is past auth.
  ///
  /// Deliberately not shown on the login screen. That screen fires the
  /// biometric prompt on open, and a dialog racing the system sheet would
  /// either swallow it or bury it. Someone stuck on an old build who cannot
  /// sign in at all is what the forced gate is for.
  void _maybePromptForUpdate() {
    if (_updatePromptShown) return;
    final status = _softUpdate;
    if (status == null) return;
    _updatePromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      UpdateAvailableDialog.maybeShow(context, status);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Ahead of everything else, including auth — a build old enough to be
    // gated may not be able to log in at all.
    if (_update != null) return ForceUpdateScreen(status: _update!);

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
        context.read<ThemeProvider>().syncFromServer();
      });
    } else if (!auth.isLoggedIn && _brandingPulled) {
      _brandingPulled = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Tear down every per-user provider so the next account that signs in
        // on this device can never see the previous user's cached state.
        context.read<VisibilityProvider>().reset();
        context.read<DashboardProvider>().reset();
        context.read<NotificationsProvider>().reset();
        context.read<PortalLeadsProvider>().reset();
        context.read<PropertyProvider>().reset();
        context.read<SellerListingsProvider>().reset();
        context.read<ClientMatchesProvider>().reset();
      });
    }
    // Optional update nudge — only once the user is actually inside the app,
    // agent or client. Held back on the login screen so it can't collide with
    // the biometric prompt that fires there.
    if (eitherLoggedIn) _maybePromptForUpdate();
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
      // Show the agency picker on every app open until the client locks to a
      // specific agency. Driven entirely here so it never appears mid-flow
      // when tapping into a feature.
      if (clientSession.mustPickAgency) {
        return const ClientAgencyPickerScreen(initialPick: true);
      }
      return const ClientHomeScreen();
    }

    if (auth.isLoggedIn) {
      return const HomeScreen();
    }
    return const LoginScreen();
  }
}
