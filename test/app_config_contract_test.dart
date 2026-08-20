import 'package:flutter_test/flutter_test.dart';

import 'package:corex_mobile/config/app_version.dart';
import 'package:corex_mobile/services/app_update_service.dart';

/// Pins the client half of the `/v1/mobile/app-config` contract.
///
/// The payloads below are the exact shapes `MobileAppConfigController` emits.
/// This is the code path that decides whether an agent is blocked out of the
/// app entirely, so the rules it enforces — fail open, 0 means off, never gate
/// without an update URL — are worth asserting against literal JSON rather
/// than trusting that two repos still agree.
///
/// [kAppBuildNumber] is the running build, so cases are written relative to it
/// and keep working across version bumps.
void main() {
  const running = kAppBuildNumber;

  const playUrl =
      'https://play.google.com/store/apps/details?id=za.co.corex_mobile';

  Map<String, dynamic> payload({
    String platform = 'android',
    int minBuild = 0,
    int latestBuild = 0,
    String? updateUrl = playUrl,
    String? latestVersion,
    String? message,
  }) =>
      {
        'platform': platform,
        'min_build': minBuild,
        'update_required': minBuild > 0 && running < minBuild,
        'update_url': updateUrl,
        'message': message,
        'latest_build': latestBuild,
        'latest_version': latestVersion,
        'update_available': latestBuild > 0 && running < latestBuild,
      };

  group('off by default', () {
    test('an all-zero payload does nothing', () {
      final s = AppUpdateService.parseConfig(payload());
      expect(s.updateRequired, isFalse);
      expect(s.updateAvailable, isFalse);
    });

    test('an unknown platform gets zeros and nulls, and is never gated', () {
      final s = AppUpdateService.parseConfig(payload(
        platform: 'web',
        updateUrl: null,
      ));
      expect(s.updateRequired, isFalse);
      expect(s.updateAvailable, isFalse);
    });
  });

  group('optional notice', () {
    test('a newer published build is announced', () {
      final s = AppUpdateService.parseConfig(payload(
        latestBuild: running + 1,
        latestVersion: '1.1.0',
      ));
      expect(s.updateAvailable, isTrue);
      expect(s.updateRequired, isFalse);
      expect(s.latestBuild, running + 1);
      expect(s.latestVersion, '1.1.0');
      expect(s.updateUrl, playUrl);
    });

    test('the running build is not announced to itself', () {
      final s = AppUpdateService.parseConfig(payload(latestBuild: running));
      expect(s.updateAvailable, isFalse);
    });

    test('a build ahead of the server is not announced', () {
      final s = AppUpdateService.parseConfig(payload(latestBuild: running - 1));
      expect(s.updateAvailable, isFalse);
    });

    test('no update URL means no notice, even with a newer build', () {
      // The iOS shape until mobile_update_url_ios is set. The server zeroes
      // latest_build itself; this asserts the client refuses independently, so
      // the rule survives a server-side regression.
      final s = AppUpdateService.parseConfig(payload(
        platform: 'ios',
        latestBuild: running + 5,
        updateUrl: null,
      ));
      expect(s.updateAvailable, isFalse,
          reason: 'an Update button that opens nothing is worse than silence');
    });

    test('an empty-string update URL is treated as absent', () {
      final s = AppUpdateService.parseConfig(payload(
        latestBuild: running + 1,
        updateUrl: '',
      ));
      expect(s.updateAvailable, isFalse);
    });
  });

  group('forced gate still wins', () {
    test('below min_build blocks, and suppresses the optional notice', () {
      final s = AppUpdateService.parseConfig(payload(
        minBuild: running + 1,
        latestBuild: running + 3,
      ));
      expect(s.updateRequired, isTrue);
      expect(s.updateAvailable, isFalse,
          reason: 'the blocking screen supersedes the dismissible dialog — '
              'showing both would let the user "Later" past a hard gate');
      expect(s.updateUrl, playUrl);
    });

    test('min_build with no URL does not block', () {
      final s = AppUpdateService.parseConfig(payload(
        platform: 'ios',
        minBuild: running + 1,
        updateUrl: null,
      ));
      expect(s.updateRequired, isFalse);
    });

    test('latest_build well above min_build is the ordinary state', () {
      // min_build at a supported floor, latest_build at the new release.
      final s = AppUpdateService.parseConfig(payload(
        minBuild: running,
        latestBuild: running + 4,
      ));
      expect(s.updateRequired, isFalse);
      expect(s.updateAvailable, isTrue);
    });
  });

  group('malformed input fails open', () {
    test('string-typed numbers still parse', () {
      final s = AppUpdateService.parseConfig({
        'min_build': '0',
        'latest_build': '${running + 1}',
        'update_url': playUrl,
      });
      expect(s.updateAvailable, isTrue);
    });

    test('missing fields entirely', () {
      final s = AppUpdateService.parseConfig(<String, dynamic>{});
      expect(s.updateRequired, isFalse);
      expect(s.updateAvailable, isFalse);
    });

    test('junk values never block anyone', () {
      final s = AppUpdateService.parseConfig({
        'min_build': 'not-a-number',
        'latest_build': null,
        'update_url': playUrl,
      });
      expect(s.updateRequired, isFalse,
          reason: 'a malformed response must never brick the app');
      expect(s.updateAvailable, isFalse);
    });
  });
}
