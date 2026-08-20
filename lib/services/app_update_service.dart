import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_version.dart';
import '../config/env.dart';

/// Result of a version-gate check.
class AppUpdateStatus {
  const AppUpdateStatus({
    required this.updateRequired,
    this.updateAvailable = false,
    this.updateUrl,
    this.message,
    this.latestBuild,
    this.latestVersion,
  });

  /// The build must not be used until it is updated.
  final bool updateRequired;

  /// A newer build is published, but this one still works.
  ///
  /// Strictly weaker than [updateRequired] and never both at once — the
  /// blocking screen supersedes the optional nudge. Driven by `latest_build`,
  /// which is a separate dial from `min_build` on purpose: announcing a release
  /// and forcing one are different decisions, and conflating them means every
  /// release you tell people about is one you also brick the old build for.
  final bool updateAvailable;

  /// Where to send the user. Never null when [updateRequired] or
  /// [updateAvailable] is true — the server refuses to gate a platform it has
  /// no update URL for, and [AppUpdateService] enforces the same rule again
  /// client-side.
  final String? updateUrl;

  /// Optional operator-supplied copy shown on the blocking screen.
  final String? message;

  /// Newest published build, when the server reports one.
  final int? latestBuild;

  /// Newest published version name (e.g. `1.1.0`), for display. Optional —
  /// the prompt falls back to the build number.
  final String? latestVersion;

  static const allowed = AppUpdateStatus(updateRequired: false);
}

/// Checks this build against the server's minimum supported build.
///
/// FAILS OPEN, ALWAYS. Every error path — offline, DNS failure, 500, timeout,
/// malformed JSON — resolves to [AppUpdateStatus.allowed]. A forced-update gate
/// that blocks when it cannot reach the server turns a backend outage into
/// every agent's app being bricked simultaneously, which is a far worse
/// incident than some devices running an old build for another hour.
class AppUpdateService {
  /// Short on purpose: this runs on the cold-start path, in front of the
  /// splash screen. A slow network should delay launch by a couple of seconds
  /// at most before we give up and let the user in.
  static const Duration _timeout = Duration(seconds: 6);

  static String get _platform {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'other';
  }

  static Future<AppUpdateStatus> check() async {
    try {
      final uri = Uri.parse('${Env.apiBaseUrl}/v1/mobile/app-config').replace(
        queryParameters: {
          'platform': _platform,
          'build': '$kAppBuildNumber',
        },
      );

      final response = await http
          .get(uri, headers: {'Accept': 'application/json'}).timeout(_timeout);

      if (response.statusCode != 200) return AppUpdateStatus.allowed;

      final body = jsonDecode(response.body);
      if (body is! Map) return AppUpdateStatus.allowed;

      return parseConfig(body);
    } catch (e) {
      debugPrint('[update] check failed, allowing through: $e');
      return AppUpdateStatus.allowed;
    }
  }

  /// Turns an `/v1/mobile/app-config` payload into a verdict.
  ///
  /// Split out from [check] so the contract with the server can be tested
  /// without a network round-trip — this is the half that actually decides
  /// whether an agent gets blocked, and it is worth pinning against the exact
  /// JSON the endpoint emits.
  @visibleForTesting
  static AppUpdateStatus parseConfig(Map<dynamic, dynamic> body) {
    {
      final minBuild = int.tryParse('${body['min_build'] ?? 0}') ?? 0;
      final url = (body['update_url'] as String?)?.trim();

      // Re-derive the verdict from min_build rather than trusting the server's
      // `update_required`: that field is computed from the `build` query param,
      // and this is the one place that knows for certain which build is running.
      //
      // The URL check mirrors the server's safety rule. Blocking someone behind
      // a button that cannot open anything leaves them with no way forward at
      // all, so no URL means no gate.
      final hasUrl = url != null && url.isNotEmpty;
      final blocked = minBuild > 0 && kAppBuildNumber < minBuild && hasUrl;

      if (blocked) {
        debugPrint(
          '[update] build $kAppBuildNumber is below minimum $minBuild — blocking',
        );

        return AppUpdateStatus(
          updateRequired: true,
          updateUrl: url,
          message: (body['message'] as String?)?.trim(),
        );
      }

      // Optional nudge. Same no-URL-no-prompt rule as the hard gate: an
      // "Update now" button that opens nothing is worse than staying quiet.
      // `latest_build` absent or 0 means the operator has not announced a
      // release, which is the off position — matching how `min_build` works.
      final latestBuild = int.tryParse('${body['latest_build'] ?? 0}') ?? 0;
      if (latestBuild > kAppBuildNumber && hasUrl) {
        debugPrint(
          '[update] build $kAppBuildNumber is behind latest $latestBuild',
        );
        return AppUpdateStatus(
          updateRequired: false,
          updateAvailable: true,
          updateUrl: url,
          latestBuild: latestBuild,
          latestVersion: (body['latest_version'] as String?)?.trim(),
          // Optional operator copy for the *soft* notice, and deliberately NOT
          // `message` — that one is the forced-gate wording ("no longer
          // supported"), which would be a lie on a dismissible dialog.
          // The server does not send this field yet; until it does the dialog
          // uses its own copy, which is why reading it costs nothing.
          message: (body['update_available_message'] as String?)?.trim(),
        );
      }

      return AppUpdateStatus.allowed;
    }
  }

  /// Highest build the user has already said "Later" to.
  static const _kSnoozedBuild = 'update_prompt_snoozed_build';

  /// Whether the optional prompt may be shown for [latestBuild].
  ///
  /// The app's standing UX rule is no intrusive launch popups, and this is the
  /// clause that keeps this one honest: dismissing is remembered against the
  /// *build number*, so "Later" silences it completely until a genuinely newer
  /// release ships. It can never ask twice for the same version.
  static Future<bool> shouldPromptFor(int latestBuild) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return latestBuild > (prefs.getInt(_kSnoozedBuild) ?? 0);
    } catch (e) {
      // Can't read the snooze → don't nag. Staying quiet is the safe failure
      // for an optional prompt; the forced gate is what handles must-update.
      debugPrint('[update] snooze read failed, staying quiet: $e');
      return false;
    }
  }

  /// Records "Later" for [latestBuild] so it isn't offered again until a newer
  /// build is published.
  static Future<void> snooze(int latestBuild) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kSnoozedBuild, latestBuild);
    } catch (e) {
      debugPrint('[update] snooze write failed: $e');
    }
  }
}
