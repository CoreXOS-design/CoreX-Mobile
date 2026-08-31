/// Single source of truth for the version string the app shows and reports.
///
/// Keep [kAppVersion] and [kAppBuildNumber] in step with `version:` in
/// pubspec.yaml — that line is what Android (`flutter.versionName`) and iOS
/// (`$(FLUTTER_BUILD_NAME)`) actually stamp onto a build, so drifting here
/// means the About screen and the device-registration payload lie about which
/// build a user is on.
///
/// iOS closes a **version train** once a build on it is approved: every later
/// submission under the same [kAppVersion] is rejected outright (90186 "train
/// is closed", alongside 90062), whatever the build number. 1.0.10 died that
/// way, then 1.0.11. So a rejected iOS upload is fixed by raising
/// [kAppVersion], never by bumping [kAppBuildNumber] again — and App Store
/// Connect's lookup API cannot tell you a train is closed before you try.
const String kAppVersion = '1.0.12';
const int kAppBuildNumber = 30;

/// e.g. `1.0.12 (30)` — for surfaces that want the build number too.
const String kAppVersionFull = '$kAppVersion ($kAppBuildNumber)';
