# CoreX Mobile — working notes

## Release builds

**Before every AAB build, bump the release number in [pubspec.yaml](pubspec.yaml).** No exceptions —
Google Play rejects an upload whose `versionCode` already exists, and the forced-update gate compares
build numbers, so a reused number silently breaks it.

The version line is `version: <versionName>+<buildNumber>` — e.g. `1.0.9+14`. `+14` becomes the Android
`versionCode` and the iOS build number.

- **Always** increment the build number (`+N`) by 1.
- Increment the patch/minor part of `versionName` only for a user-visible release; several builds may
  share one `versionName` (1.0.9 covered +11, +12, +13).
- Bump before running the build, not after, so the artifact carries the new number.

```
flutter build appbundle --release      # AAB for Play
flutter build apk --release            # universal APK for sideloading/testing
```

Outputs land in `build/app/outputs/bundle/release/app-release.aab` and
`build/app/outputs/flutter-apk/app-release.apk`.

Release signing comes from `android/key.properties` (gitignored). If that file is missing the build
silently falls back to the **debug** keystore and Play will reject it — verify with:

```
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk   # expect CN=CoreX OS
```

`.env` is bundled as an asset, so whatever `API_BASE_URL` it holds at build time ships in the binary.
Confirm it reads `https://corexos.co.za/api` before a store build — the fallback in
[lib/config/env.dart](lib/config/env.dart) is **staging**.
