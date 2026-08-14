import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_version.dart';
import '../config/env.dart';

/// Result of a version-gate check.
class AppUpdateStatus {
  const AppUpdateStatus({
    required this.updateRequired,
    this.updateUrl,
    this.message,
  });

  /// The build must not be used until it is updated.
  final bool updateRequired;

  /// Where to send the user. Never null when [updateRequired] is true — the
  /// server refuses to gate a platform it has no update URL for, and
  /// [AppUpdateService] enforces the same rule again client-side.
  final String? updateUrl;

  /// Optional operator-supplied copy shown on the blocking screen.
  final String? message;

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

      final minBuild = int.tryParse('${body['min_build'] ?? 0}') ?? 0;
      final url = (body['update_url'] as String?)?.trim();

      // Re-derive the verdict from min_build rather than trusting the server's
      // `update_required`: that field is computed from the `build` query param,
      // and this is the one place that knows for certain which build is running.
      //
      // The URL check mirrors the server's safety rule. Blocking someone behind
      // a button that cannot open anything leaves them with no way forward at
      // all, so no URL means no gate.
      final blocked =
          minBuild > 0 && kAppBuildNumber < minBuild && url != null && url.isNotEmpty;

      if (!blocked) return AppUpdateStatus.allowed;

      debugPrint(
        '[update] build $kAppBuildNumber is below minimum $minBuild — blocking',
      );

      return AppUpdateStatus(
        updateRequired: true,
        updateUrl: url,
        message: (body['message'] as String?)?.trim(),
      );
    } catch (e) {
      debugPrint('[update] check failed, allowing through: $e');
      return AppUpdateStatus.allowed;
    }
  }
}
