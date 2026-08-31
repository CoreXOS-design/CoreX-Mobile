/// Single source of truth for the version string the app shows and reports.
///
/// Keep [kAppVersion] and [kAppBuildNumber] in step with `version:` in
/// pubspec.yaml — that line is what Android (`flutter.versionName`) and iOS
/// (`$(FLUTTER_BUILD_NAME)`) actually stamp onto a build, so drifting here
/// means the About screen and the device-registration payload lie about which
/// build a user is on.
const String kAppVersion = '1.0.11';
const int kAppBuildNumber = 29;

/// e.g. `1.0.11 (25)` — for surfaces that want the build number too.
const String kAppVersionFull = '$kAppVersion ($kAppBuildNumber)';
