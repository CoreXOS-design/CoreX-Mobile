import 'dart:async';
import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/notifications_provider.dart';
import '../providers/portal_leads_provider.dart';
import 'api_service.dart';
import 'deep_link_router.dart';

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

  final ApiService _api = ApiService();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static const _testChannelId = 'corex_test';
  static const _testChannelName = 'CoreX test notifications';

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

  Future<void> init({GlobalKey<NavigatorState>? navigatorKey}) async {
    if (_initialised) return;
    _initialised = true;
    this.navigatorKey = navigatorKey;

    // Register the background/terminated message handler. Must be wired before
    // any messages arrive; the handler runs in its own isolate.
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // iOS / web foreground presentation — show the system banner instead of
    // suppressing it.
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Permission prompt on iOS (no-op on Android < 13; handled by
    // permission_handler in main.dart for Android 13+).
    await _fcm.requestPermission();

    await _initLocalNotifications();

    // Auto-register if the OS rotates the token.
    _fcm.onTokenRefresh.listen(_registerWithServer);

    // Foreground delivery — show a snackbar instead of a system banner so the
    // user notices without an OS interruption.
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // Tap on a notification while app is backgrounded.
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageTap);

    // Cold-start tap (app was killed when the push arrived).
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      // Defer to the first frame so Navigator is ready.
      WidgetsBinding.instance.addPostFrameCallback((_) => _onMessageTap(initial));
    }
  }

  Future<void> onLogin() async {
    final token = await _obtainToken();
    if (token == null) return;
    await _registerWithServer(token);
  }

  Future<void> onLogout() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kRegisteredTokenKey);
    if (token != null) {
      try {
        await _api.revokeDeviceToken(token);
        // Only forget the local record after a confirmed revoke — otherwise a
        // later retry has nothing to revoke and the server keeps targeting
        // this device.
        await prefs.remove(_kRegisteredTokenKey);
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
        await _api.revokeDeviceToken(token);
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
      await _api.registerDeviceToken(
        platform: _platform,
        token: token,
        appVersion: _appVersion,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRegisteredTokenKey, token);
    } catch (e) {
      debugPrint('[messaging] register failed: $e');
    }
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
    if (ctx == null) return;

    // Belt-and-braces: if the local user disabled push, swallow the foreground
    // presentation. The server should already be suppressing, but a stale
    // device-token or in-flight delivery can race the preference change.
    try {
      final np = Provider.of<NotificationsProvider>(ctx, listen: false);
      if (!np.localPushEnabled) return;
      // Quiet hours: outside the user's open-hours window we swallow the
      // in-app banner. Background/system-tray pushes can only be stopped by
      // the server honouring the same schedule (the app isn't running then).
      if (!np.notificationsAllowedNow) return;
    } catch (_) {
      // Fail closed: if we can't determine the user's push/quiet-hours
      // preference, suppress the banner rather than risk showing one the user
      // disabled.
      return;
    }

    final title = msg.notification?.title ?? msg.data['title']?.toString();
    final body = msg.notification?.body ?? msg.data['body']?.toString();
    if (title == null && body == null) return;

    // Storm guard: drop duplicates and cap the banner rate before doing any
    // work, so a backend re-send loop can't lock up the UI thread.
    final fingerprint = (msg.messageId?.isNotEmpty ?? false)
        ? msg.messageId!
        : '${msg.data['type']}|$title|$body';
    if (_shouldSuppressForeground(fingerprint)) return;

    final action = _resolveAction(msg.data);

    if (msg.data['type']?.toString() == 'portal_lead') {
      try {
        Provider.of<PortalLeadsProvider>(ctx, listen: false).bumpUnread();
      } catch (_) {}
    }

    final messenger = ScaffoldMessenger.of(ctx);

    // Show a banner pinned to the top of the screen (instead of a bottom
    // snackbar) with an explicit X to dismiss. Auto-dismiss after 5s to match
    // the previous behaviour.
    messenger.clearMaterialBanners();
    final controller = messenger.showMaterialBanner(
      MaterialBanner(
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null)
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            if (body != null) Text(body, style: const TextStyle(fontSize: 12)),
          ],
        ),
        leading: const Icon(Icons.notifications),
        actions: [
          if (action != null)
            TextButton(
              onPressed: () {
                messenger.hideCurrentMaterialBanner();
                DeepLinkRouter.open(ctx, action);
              },
              child: const Text('View'),
            ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Dismiss',
            onPressed: messenger.hideCurrentMaterialBanner,
          ),
        ],
      ),
    );

    // Auto-dismiss after 5 seconds if this banner is still showing. Cancel the
    // timer the moment the banner closes by any other means (the X, the View
    // action, or a replacing banner) — otherwise `controller.close()` runs
    // against an already-removed banner and throws "Bad state: No element",
    // crashing the app.
    final autoDismiss = Timer(const Duration(seconds: 5), controller.close);
    controller.closed.then((_) => autoDismiss.cancel());
  }

  void _onMessageTap(RemoteMessage msg) {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null) return;
    final action = _resolveAction(msg.data);
    if (action != null && action.isNotEmpty) {
      DeepLinkRouter.open(ctx, action);
    }
  }

  /// Resolves the best in-app route for a push payload.
  ///
  /// Event-reminder pushes carry a *generic* calendar `action_url`
  /// (`/corex/command-center/calendar`) plus the specific `event_id`. Prefer
  /// focusing the actual appointment so the tap lands on the right event rather
  /// than the bare calendar. Everything else falls back to the server-issued
  /// `action_url`, then `deep_link`.
  String? _resolveAction(Map<String, dynamic> data) {
    if (data['type']?.toString() == 'event_due_reminder') {
      final eventId = data['event_id']?.toString();
      if (eventId != null && eventId.isNotEmpty) {
        return '/corex/command-center/calendar?event=$eventId';
      }
    }
    return (data['action_url'] ?? data['deep_link'])?.toString();
  }

  Future<void> _initLocalNotifications() async {
    const android =
        AndroidInitializationSettings('ic_launcher_monochrome');
    const ios = DarwinInitializationSettings();
    await _local.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _testChannelId,
          _testChannelName,
          importance: Importance.high,
        ));
  }

  /// Fires a local system-tray notification so the user can verify that
  /// notifications surface correctly on their device.
  Future<void> sendTestNotification() async {
    await _local.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      'CoreX test notification',
      'If you can see this in your notification bar, push delivery is working.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _testChannelId,
          _testChannelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  String get _platform {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'other';
  }

  String get _appVersion => '1.0.0';
}
