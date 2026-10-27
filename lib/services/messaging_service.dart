import 'dart:async';
import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_version.dart';
import '../providers/auth_provider.dart';
import '../providers/client_session_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/portal_leads_provider.dart';
import 'api_service.dart';
import 'deep_link_router.dart';
import 'rentals/rentals_http.dart';

/// Top-level (entry-point) background message handler. FCM spins up a fresh
/// isolate to run this when a data message arrives while the app is
/// backgrounded or terminated, so it must be a top-level/static function and
/// initialise Firebase before touching any Firebase API.
///
/// It is intentionally minimal: notification-type messages are surfaced by the
/// OS tray automatically. Any persistent, cross-isolate dedup (e.g. recording
/// message ids so the foreground guard can skip ones already shown in the
/// background) belongs here.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/// Wraps FCM push registration + delivery.
///
/// Lifecycle:
///   - `init()` once at app start (after `Firebase.initializeApp()`).
///   - `onLogin()` after a successful login → fetches the token and POSTs to
///     `/api/device-tokens`. Re-runs on cold start in `AuthProvider.checkAuth`.
///   - `onLogout()` before clearing the Sanctum bearer → DELETEs the token.
///   - `onTokenRefresh` is auto-wired in `init()` so OS rotations are handled.
class MessagingService {
  MessagingService._();
  static final MessagingService instance = MessagingService._();

  static const _kRegisteredTokenKey = 'fcm_registered_token_v1';

  /// Which endpoint the stored token was registered with: `staff`
  /// (`/device-tokens`) or `client` (`/client/device-tokens`). A tenant or
  /// owner is a ClientUser, not a User, so their phone has its own route.
  static const _kRegisteredAudienceKey = 'fcm_registered_audience_v1';

  final ApiService _api = ApiService();

  /// True while a tenant / owner (client) session is the active one. Decides
  /// where a rotated token is re-registered.
  bool _clientSession = false;

  /// Resolved lazily, never in a field initialiser. `FirebaseMessaging.instance`
  /// calls `Firebase.app()`, which THROWS when no default app exists — and
  /// [AuthProvider] holds a [MessagingService] as a field, so constructing it
  /// eagerly means a failed `Firebase.initializeApp()` takes down the very
  /// first widget build instead of merely disabling push. `main` catching the
  /// init error is otherwise a false comfort: the app dies one frame later.
  FirebaseMessaging get _fcm => FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  // One high-importance channel for everything CoreX posts, so the user sees a
  // single honest entry in the OS notification settings and the "send test
  // notification" button exercises the exact channel real pushes use.
  //
  // `_pushChannelId` is referenced in three places that must stay in sync:
  //   - AndroidManifest `default_notification_channel_id` (background/killed
  //     pushes, rendered by the Firebase SDK)
  //   - `FcmService::ANDROID_CHANNEL_ID` in the hfc-dash backend
  //     (app/Services/Push/FcmService.php) — that repo owns this contract
  //     string; see .ai/specs/push-notifications.md
  //   - `_showLocal` below (foreground pushes, rendered by us)
  // Importance.high is what earns the heads-up banner; IMPORTANCE_DEFAULT only
  // lands in the shade. This value MUST be 'corex_alerts' — an earlier mobile
  // change renamed it to 'corex_push' locally without checking it against the
  // backend's actual constant, silently breaking every backgrounded/terminated
  // push (they fell into FCM's auto-created default-importance fallback
  // channel instead of this one). Do not rename this again without grepping
  // the backend for the current value of ANDROID_CHANNEL_ID.
  static const _pushChannelId = 'corex_alerts';
  static const _pushChannelName = 'CoreX notifications';
  static const _pushChannelDescription =
      'New leads, appointment reminders and other CoreX alerts.';

  // --- Foreground storm guard ---------------------------------------------
  // A backend misfire (e.g. a job re-sending the same push in a tight loop)
  // once flooded a device with foreground messages: every one buzzed and
  // replaced the banner, saturating the UI thread until the phone appeared
  // frozen. These two guards make that impossible to reproduce client-side,
  // independent of whatever the server sends.
  //
  // 1. Dedup: a message whose fingerprint was seen within [_dedupWindow] is
  //    dropped silently (handles the same push arriving repeatedly).
  // 2. Rate limit: at most [_maxBannersPerWindow] banners per
  //    [_rateLimitWindow] — a genuine burst of *distinct* notifications still
  //    can't lock up the screen.
  static const _dedupWindow = Duration(seconds: 10);
  static const _rateLimitWindow = Duration(seconds: 60);
  static const _maxBannersPerWindow = 6;

  final Map<String, DateTime> _recentFingerprints = {};
  final List<DateTime> _recentBannerTimes = [];

  /// Returns true if this message should be suppressed (duplicate or over the
  /// rate cap). Has the side effect of recording the message when it passes.
  bool _shouldSuppressForeground(String fingerprint) {
    final now = DateTime.now();

    // Dedup. Also prune expired entries so the map can't grow unbounded.
    _recentFingerprints
        .removeWhere((_, ts) => now.difference(ts) > _dedupWindow);
    final lastSeen = _recentFingerprints[fingerprint];
    if (lastSeen != null && now.difference(lastSeen) < _dedupWindow) {
      debugPrint(
          '[messaging] dedup suppressed foreground message: $fingerprint');
      _recentFingerprints[fingerprint] = now;
      return true;
    }

    // Rate limit (sliding window).
    _recentBannerTimes
        .removeWhere((ts) => now.difference(ts) > _rateLimitWindow);
    if (_recentBannerTimes.length >= _maxBannersPerWindow) {
      debugPrint('[messaging] foreground banner rate cap hit — suppressing');
      return true;
    }

    _recentFingerprints[fingerprint] = now;
    _recentBannerTimes.add(now);
    return false;
  }

  /// Set by `main.dart` before runApp so deep-links from cold-start taps know
  /// where to navigate. Foreground / warm-tap handlers grab the active context
  /// from this navigator key.
  GlobalKey<NavigatorState>? navigatorKey;

  bool _initialised = false;

  /// Completes once [init] has run, successfully or not. [onLogin] waits on it.
  ///
  /// `init` used to be awaited in `main` ahead of `runApp`, so it could not
  /// lose a race. It now runs after the first frame, which puts it alongside
  /// `AuthProvider.checkAuth` — and on iOS `getToken()` fails outright until
  /// init's `requestPermission()` has registered the app with APNs, so a
  /// cold start that got there first would silently never register a device
  /// token.
  final Completer<void> _ready = Completer<void>();

  Future<void> init({GlobalKey<NavigatorState>? navigatorKey}) async {
    if (_initialised) return _ready.future;
    _initialised = true;
    this.navigatorKey = navigatorKey;
    try {
      await _init();
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  Future<void> _init() async {
    // Register the background/terminated message handler. Must be wired before
    // any messages arrive; the handler runs in its own isolate.
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // iOS / web foreground presentation — suppress the OS's automatic banner.
    // We post the notification ourselves in [_onForegroundMessage] so that the
    // user's push toggle and quiet-hours window are honoured on iOS exactly as
    // they are on Android; letting iOS auto-present would bypass both gates and
    // double up with the notification we post.
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );

    // The notification prompt is NOT raised here: it waits for sign-in
    // ([_ensurePermission] from [onLogin] / [onClientLogin]), so it never
    // appears on the login screen with no context.

    await _initLocalNotifications();

    // Auto-register if the OS rotates the token.
    _fcm.onTokenRefresh.listen(_registerWithServer);

    // Foreground delivery — FCM never renders anything itself while the app is
    // open, so we post the notification.
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // Tap on a notification while app is backgrounded.
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageTap);

    // Cold-start tap (app was killed when the push arrived).
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      // Defer to the first frame so Navigator is ready.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _onMessageTap(initial));
    }
  }

  Future<void> onLogin() async {
    _clientSession = false;
    // See [_ready]. Bounded so a Firebase init that never ran (or never
    // finished) leaves this pending forever instead of just skipping
    // registration — the caller fires it with `unawaited`.
    await _ready.future.timeout(const Duration(seconds: 20), onTimeout: () {});
    await _ensurePermission();
    final token = await _obtainToken();
    if (token == null) return;
    await _registerWithServer(token);
  }

  /// Tenant / owner sign-in (or cold start with a client token). Same as
  /// [onLogin], against the client device-token route.
  Future<void> onClientLogin() async {
    _clientSession = true;
    await _ready.future.timeout(const Duration(seconds: 20), onTimeout: () {});
    await _ensurePermission();
    final token = await _obtainToken();
    if (token == null) return;
    await _registerWithServer(token);
  }

  /// Call before the client token is cleared — the DELETE needs it.
  Future<void> onClientLogout() => onLogout();

  Future<void> _revoke(String token, String? audience) async {
    if (audience == 'client') {
      await RentalsHttp.instance.delete(RentalsAudience.tenant,
          '/client/device-tokens/${Uri.encodeComponent(token)}');
    } else {
      await _api.revokeDeviceToken(token);
    }
  }

  Future<void> onLogout() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kRegisteredTokenKey);
    final audience = prefs.getString(_kRegisteredAudienceKey);
    if (token != null) {
      try {
        await _revoke(token, audience);
        // Only forget the local record after a confirmed revoke — otherwise a
        // later retry has nothing to revoke and the server keeps targeting
        // this device.
        await prefs.remove(_kRegisteredTokenKey);
        await prefs.remove(_kRegisteredAudienceKey);
      } catch (e) {
        debugPrint('[messaging] revoke failed: $e');
      }
    }
    try {
      await _fcm.deleteToken();
    } catch (e) {
      debugPrint('[messaging] deleteToken failed: $e');
    }
  }

  /// Reflects a Push-channel toggle for *this device*. Turning push on
  /// (re)registers the FCM token so background pushes resume; turning it off
  /// revokes the token so the server stops targeting this device. The
  /// foreground gate ([NotificationsProvider.localPushEnabled]) only covers the
  /// in-app banner — without revoking the token, "Push off" still left the
  /// device receiving system-tray pushes, which read as "the toggle does
  /// nothing".
  Future<void> setPushEnabled(bool enabled) async {
    if (enabled) {
      final token = await _obtainToken();
      if (token != null) await _registerWithServer(token);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kRegisteredTokenKey) ?? await _obtainToken();
    if (token != null) {
      try {
        await _revoke(
            token,
            prefs.getString(_kRegisteredAudienceKey) ??
                (_clientSession ? 'client' : 'staff'));
        // Only drop the local record on a confirmed revoke so a failed call
        // can still be retried instead of silently leaving the device
        // registered server-side.
        await prefs.remove(_kRegisteredTokenKey);
      } catch (e) {
        debugPrint('[messaging] revoke (push off) failed: $e');
      }
    }
  }

  Future<void> _registerWithServer(String token) async {
    try {
      if (_clientSession) {
        await RentalsHttp.instance
            .post(RentalsAudience.tenant, '/client/device-tokens', body: {
          'platform': _platform,
          'token': token,
          'app_version': _appVersion,
        });
      } else {
        await _api.registerDeviceToken(
          platform: _platform,
          token: token,
          appVersion: _appVersion,
        );
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRegisteredTokenKey, token);
      await prefs.setString(
          _kRegisteredAudienceKey, _clientSession ? 'client' : 'staff');
    } catch (e) {
      debugPrint('[messaging] register failed: $e');
    }
  }

  /// True when this phone blocks CoreX notifications. Settings screens show
  /// a plain explanation with a way to the system settings while it is.
  final ValueNotifier<bool> notificationsBlocked = ValueNotifier(false);

  /// Asks for the notification permission once someone is signed in. A
  /// decision already made is not asked again; a "no" given just now gets
  /// one explanation, never a repeat on later launches.
  Future<void> _ensurePermission() async {
    try {
      bool granted;
      var askedNow = false;
      if (Platform.isAndroid) {
        var status = await Permission.notification.status;
        if (!status.isGranted && !status.isPermanentlyDenied) {
          askedNow = true;
          status = await Permission.notification.request();
        }
        granted = status.isGranted;
      } else {
        // iOS: always called — getToken() fails until requestPermission()
        // has registered with APNs (see [_ready]). It only prompts while
        // undecided.
        final before = await _fcm.getNotificationSettings();
        askedNow =
            before.authorizationStatus == AuthorizationStatus.notDetermined;
        final after = await _fcm.requestPermission();
        granted = after.authorizationStatus == AuthorizationStatus.authorized ||
            after.authorizationStatus == AuthorizationStatus.provisional;
      }
      notificationsBlocked.value = !granted;
      if (!granted && askedNow) _explainBlocked();
    } catch (e) {
      debugPrint('[messaging] permission check failed: $e');
    }
  }

  /// Re-reads the permission without prompting — after a visit to the
  /// system settings, say.
  Future<void> refreshPermissionStatus() async {
    try {
      if (Platform.isAndroid) {
        notificationsBlocked.value =
            !(await Permission.notification.status).isGranted;
      } else {
        final s = (await _fcm.getNotificationSettings()).authorizationStatus;
        notificationsBlocked.value = s == AuthorizationStatus.denied;
      }
    } catch (_) {}
  }

  void _explainBlocked() {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(const SnackBar(
      duration: Duration(seconds: 8),
      content: Text(
          'Notifications are off, so alerts (like a new fault or a reply) '
          "won't reach this phone. You can turn them on in Settings."),
      action: SnackBarAction(label: 'Settings', onPressed: openAppSettings),
    ));
  }

  Future<String?> _obtainToken() async {
    try {
      return await _fcm.getToken();
    } catch (e) {
      debugPrint('[messaging] getToken failed: $e');
      return null;
    }
  }

  void _onForegroundMessage(RemoteMessage msg) {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null) {
      debugPrint(
          '[messaging] foreground message dropped: no navigator context (id=${msg.messageId})');
      return;
    }

    // Belt-and-braces: if the local user disabled push, swallow the foreground
    // presentation. The server should already be suppressing, but a stale
    // device-token or in-flight delivery can race the preference change.
    // A Push Test Lab send (`test` = "1") ignores the person's settings on the
    // server; do the same here, or a test made outside open hours to an open
    // app looks like a failed delivery. Dedup + rate limit below still apply.
    final isTest = msg.data['test']?.toString() == '1';
    if (!isTest) {
      try {
        final np = Provider.of<NotificationsProvider>(ctx, listen: false);
        if (!np.localPushEnabled) {
          debugPrint(
              '[messaging] foreground message dropped: localPushEnabled=false (id=${msg.messageId})');
          return;
        }
        // Quiet hours: outside the user's open-hours window we swallow the
        // in-app banner. Background/system-tray pushes can only be stopped by
        // the server honouring the same schedule (the app isn't running then).
        if (!np.notificationsAllowedNow) {
          debugPrint(
              '[messaging] foreground message dropped: outside open hours (id=${msg.messageId})');
          return;
        }
      } catch (e) {
        // Fail closed: if we can't determine the user's push/quiet-hours
        // preference, suppress the banner rather than risk showing one the user
        // disabled.
        debugPrint(
            '[messaging] foreground message dropped: prefs lookup failed: $e (id=${msg.messageId})');
        return;
      }
    }

    final title = msg.notification?.title ?? msg.data['title']?.toString();
    final body = msg.notification?.body ?? msg.data['body']?.toString();
    if (title == null && body == null) {
      debugPrint(
          '[messaging] foreground message dropped: no title/body (id=${msg.messageId})');
      return;
    }

    // Storm guard: drop duplicates and cap the banner rate before doing any
    // work, so a backend re-send loop can't lock up the UI thread.
    final fingerprint = (msg.messageId?.isNotEmpty ?? false)
        ? msg.messageId!
        : '${msg.data['type']}|$title|$body';
    if (_shouldSuppressForeground(fingerprint)) return; // logged inside

    final action = resolveAction(msg.data);

    // A test from the Push Test Lab is shown and opens like a real one, but
    // never counts towards a badge.
    if (!isTest && msg.data['type']?.toString() == 'portal_lead') {
      try {
        Provider.of<PortalLeadsProvider>(ctx, listen: false).bumpUnread();
      } catch (_) {}
    }

    // Post a real OS notification rather than an in-app banner.
    //
    // This used to show a MaterialBanner, on the reasoning that an agent who
    // already has the app open shouldn't be interrupted by the OS. In practice
    // that made a foreground lead *invisible*: the banner vanished after 5s and
    // left nothing behind, so an agent who was on another screen — or simply
    // not looking — had no shade entry and no badge to come back to, and
    // reported the push as never delivered. A real notification peeks, persists
    // in the shade, and survives being missed.
    unawaited(_showLocal(
      id: fingerprint.hashCode & 0x7fffffff,
      title: title,
      body: body,
      payload: action,
      urgent: msg.data['severity']?.toString() == 'warning',
    ));
  }

  /// Posts a notification through [_pushChannelId] and returns once the OS has
  /// accepted it. Tapping it routes through [_onLocalNotificationTap].
  ///
  /// [urgent] (`severity` = warning: an emergency fault, something needing
  /// attention) posts at max priority in the danger colour and, on iOS, as
  /// time-sensitive.
  Future<void> _showLocal({
    required int id,
    String? title,
    String? body,
    String? payload,
    bool urgent = false,
  }) async {
    try {
      await _local.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _pushChannelId,
            _pushChannelName,
            channelDescription: _pushChannelDescription,
            importance: Importance.high,
            priority: urgent ? Priority.max : Priority.high,
            color: urgent ? const Color(0xFFDC2626) : null,
            // Lead bodies carry a name plus a property reference and routinely
            // overflow one line; collapsed they truncate to uselessness.
            styleInformation:
                body == null ? null : BigTextStyleInformation(body),
          ),
          iOS: DarwinNotificationDetails(
              interruptionLevel:
                  urgent ? InterruptionLevel.timeSensitive : null),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('[messaging] local notification failed: $e');
    }
  }

  /// Tap handler for notifications *we* posted (foreground deliveries). Pushes
  /// rendered by the OS while backgrounded come back through
  /// [FirebaseMessaging.onMessageOpenedApp] instead.
  void _onLocalNotificationTap(NotificationResponse response) {
    _openTapped(response.payload);
  }

  void _onMessageTap(RemoteMessage msg) {
    _openTapped(resolveAction(msg.data));
  }

  /// A tapped push's route, held while nobody is signed in (cold start still
  /// restoring the session, locked, or signed out) and opened by
  /// [openPendingTap] once someone is.
  String? _pendingTap;

  void _openTapped(String? action) {
    if (action == null || action.isEmpty) return;
    final ctx = navigatorKey?.currentContext;
    if (ctx == null || !_signedIn(ctx)) {
      _pendingTap = action;
      return;
    }
    DeepLinkRouter.open(ctx, action, fromPush: true);
  }

  /// Called by the app shell whenever it has someone signed in and past the
  /// sign-in screens; opens a push tapped before that.
  void openPendingTap() {
    final action = _pendingTap;
    if (action == null) return;
    final ctx = navigatorKey?.currentContext;
    if (ctx == null || !_signedIn(ctx)) return;
    _pendingTap = null;
    DeepLinkRouter.open(ctx, action, fromPush: true);
  }

  static bool _signedIn(BuildContext ctx) {
    try {
      if (Provider.of<AuthProvider>(ctx, listen: false).isLoggedIn) {
        return true;
      }
      final client = Provider.of<ClientSessionProvider>(ctx, listen: false);
      return client.isLoggedIn &&
          !client.passwordMustChange &&
          !client.mustPickAgency;
    } catch (_) {
      return false;
    }
  }

  /// Resolves the best in-app route for a push payload.
  ///
  /// Event-reminder pushes carry a *generic* calendar `action_url`
  /// (`/corex/command-center/calendar`) plus the specific `event_id`. Prefer
  /// focusing the actual appointment so the tap lands on the right event rather
  /// than the bare calendar. Everything else falls back to the server-issued
  /// `action_url`, then `deep_link`.
  @visibleForTesting
  static String? resolveAction(Map<String, dynamic> data) {
    // Tenant / owner rentals push: `subject_type` + `subject_id` name the
    // record. Encoded as an app-internal URI so the foreground (payload) and
    // background (RemoteMessage) tap paths both reach [DeepLinkRouter].
    if (data['type']?.toString() == 'rental') {
      final type = data['subject_type']?.toString() ?? '';
      final id = data['subject_id']?.toString() ?? '';
      if (type.isNotEmpty && id.isNotEmpty) {
        final audience = data['audience']?.toString() ?? '';
        return Uri(
          scheme: 'corex-rental',
          host: audience.isEmpty ? 'client' : audience,
          pathSegments: [type, id],
        ).toString();
      }
      // No record named: nothing to open (they stay on Home).
      return null;
    }
    final target = data['target']?.toString() ?? '';
    final targetId = data['target_id']?.toString() ?? '';
    // New-lead and appointment-reminder pushes share the `target` contract
    // but aren't rentals — they must not fall into the rentals branch below,
    // which would land them on Home or the notifications list. The ids from
    // the type-specific fields cover a payload without `target`.
    final leadId = target == 'portal_lead' && targetId.isNotEmpty
        ? targetId
        : (data['type']?.toString() == 'portal_lead'
            ? data['portal_lead_id']?.toString()
            : null);
    if (leadId != null && leadId.isNotEmpty) return '/portal-leads/$leadId';
    final eventId = target == 'calendar_event' && targetId.isNotEmpty
        ? targetId
        : (data['type']?.toString() == 'event_due_reminder'
            ? data['event_id']?.toString()
            : null);
    if (eventId != null && eventId.isNotEmpty) {
      return '/corex/command-center/calendar?event=$eventId';
    }
    // Agent rentals push: `target` + `target_id` name the app screen
    // (fault, work_order, job_card, lease_notice, lease, inspection,
    // application). Takes precedence over `action_url`, which is the web page.
    if (target.isNotEmpty && targetId.isNotEmpty) {
      return Uri(
        scheme: 'corex-rental',
        host: 'agent',
        pathSegments: [target, targetId],
      ).toString();
    }
    final url = (data['action_url'] ?? data['deep_link'])?.toString();
    // An agent alert (`event_key`) with no target and no link: the
    // notifications list. A link the app has no screen for lands there too
    // (DeepLinkRouter.open fromPush).
    if ((url == null || url.isEmpty) &&
        (data['event_key']?.toString() ?? '').isNotEmpty) {
      return DeepLinkRouter.notificationsLink;
    }
    return url;
  }

  Future<void> _initLocalNotifications() async {
    const android = AndroidInitializationSettings('ic_launcher_monochrome');
    const ios = DarwinInitializationSettings();
    await _local.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );
    // Create the channel up front rather than lazily on first notification:
    // the Firebase SDK renders background pushes without going through Dart at
    // all, so if this channel doesn't already exist by then Android silently
    // substitutes its own default-importance fallback and the heads-up banner
    // is lost. Creating an existing channel is a no-op, and note that a
    // channel's importance is immutable once created — raising it later
    // requires a new id.
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _pushChannelId,
          _pushChannelName,
          description: _pushChannelDescription,
          importance: Importance.high,
        ));
  }

  /// Fires a local system-tray notification so the user can verify that
  /// notifications surface correctly on their device. Deliberately posted
  /// through the same channel as real pushes — a test on its own channel can
  /// pass while every real notification is muted or silenced.
  Future<void> sendTestNotification() async {
    await _showLocal(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: 'CoreX test notification',
      body:
          'If you can see this in your notification bar, push delivery is working.',
    );
  }

  String get _platform {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'other';
  }

  String get _appVersion => kAppVersion;
}
