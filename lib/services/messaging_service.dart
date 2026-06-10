import 'dart:async';
import 'dart:io' show Platform;
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
      } catch (e) {
        debugPrint('[messaging] revoke failed: $e');
      }
      await prefs.remove(_kRegisteredTokenKey);
    }
    try {
      await _fcm.deleteToken();
    } catch (e) {
      debugPrint('[messaging] deleteToken failed: $e');
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
      if (!Provider.of<NotificationsProvider>(ctx, listen: false)
          .localPushEnabled) {
        return;
      }
    } catch (_) {}

    final title = msg.notification?.title ?? msg.data['title']?.toString();
    final body = msg.notification?.body ?? msg.data['body']?.toString();
    if (title == null && body == null) return;

    // Storm guard: drop duplicates and cap the banner rate before doing any
    // work, so a backend re-send loop can't lock up the UI thread.
    final fingerprint = (msg.messageId?.isNotEmpty ?? false)
        ? msg.messageId!
        : '${msg.data['type']}|$title|$body';
    if (_shouldSuppressForeground(fingerprint)) return;

    final action = (msg.data['action_url'] ?? msg.data['deep_link'])
        ?.toString();

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
    final action = (msg.data['action_url'] ?? msg.data['deep_link'])
        ?.toString();
    if (action != null && action.isNotEmpty) {
      DeepLinkRouter.open(ctx, action);
    }
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
