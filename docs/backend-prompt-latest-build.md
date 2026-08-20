# Backend prompt — add `latest_build` to the mobile app-config endpoint

Hand this to whoever works on **hfc-dash**. The mobile side is already built and
shipped-ready; it stays completely dormant until this endpoint starts returning
`latest_build`.

---

## The prompt

> In the hfc-dash repo, extend `App\Http\Controllers\Api\V1\MobileAppConfigController`
> (served at `GET /api/v1/mobile/app-config?platform=&build=`) to support an
> **optional** update notice, alongside the existing forced-update gate.
>
> Today the endpoint only answers "what is the minimum build allowed" (`min_build`).
> The mobile app now also wants "what is the newest build published", so it can show
> a dismissible "Update available" dialog for releases that are recommended but not
> mandatory. These are deliberately two separate dials: announcing a release and
> forcing one are different decisions, and every release you tell people about must
> not also be one you brick the old build for.
>
> **Add three new `DevSetting` keys**, following exactly the same pattern as the
> existing `mobile_min_build_*` keys (settable at runtime, no deploy, no app release):
>
> - `mobile_latest_build_android` (int, default `0`)
> - `mobile_latest_build_ios` (int, default `0`)
> - `mobile_latest_version` (string, optional, e.g. `1.1.0`)
>
> **Add three fields to the JSON response:**
>
> ```json
> {
>   "platform": "android",
>   "min_build": 0,
>   "update_required": false,
>   "update_url": "https://play.google.com/store/apps/details?id=za.co.corex_mobile",
>   "message": null,
>
>   "latest_build": 20,
>   "latest_version": "1.1.0",
>   "update_available": false
> }
> ```
>
> - `latest_build` — value of `mobile_latest_build_{platform}`, `0` when unset.
> - `latest_version` — value of `mobile_latest_version`, `null` when blank. Display
>   only; the app falls back to showing the build number.
> - `update_available` — `latest_build > 0 && build > 0 && build < latest_build`.
>   Computed server-side purely so the endpoint is self-describing when curled
>   during an incident; the app re-derives the verdict itself from `latest_build`,
>   since only the client knows for certain which build is running.
>
> **Four rules that must hold — each mirrors an existing rule on this endpoint:**
>
> 1. **`latest_build = 0` means the notice is OFF.** Same off-switch semantics as
>    `min_build = 0`. Unset must never prompt anyone.
> 2. **Never announce an update for a platform with no `update_url`.** Reuse the
>    existing safety rule: if the resolved update URL is empty, zero out
>    `latest_build` the same way it already zeroes `min_build`. In practice this
>    only bites iOS, which stays inert until `mobile_update_url_ios` is set. An
>    "Update now" button that opens nothing is worse than staying quiet.
> 3. **An unrecognised or missing `platform` gets zeros for everything**, exactly as
>    it does today. A future or web client must not be nagged by a cutoff never
>    meant for it.
> 4. **Keep the endpoint unauthenticated.** Unchanged, and load-bearing — a build
>    old enough to need forcing may not be able to log in at all.
>
> Also note: `min_build` and `latest_build` are independent. It is normal and
> expected for `latest_build` to be well above `min_build` — that is the ordinary
> state (a new release is out, the old one still works). If a build is below *both*,
> the forced gate wins and the app never shows the optional dialog.
>
> **Extend `tests/Feature/Api/MobileAppConfigTest.php`** to cover:
> - `latest_build = 0` (or unset) → `update_available: false`
> - a build behind `latest_build` → `update_available: true`
> - a build equal to or ahead of `latest_build` → `update_available: false`
> - iOS with no `mobile_update_url_ios` → `latest_build` forced to `0`, even when
>   the DevSetting is set
> - an unknown platform → all zeros/nulls
> - the forced gate still taking precedence when a build is below `min_build`
>
> Update the controller's docblock with the new DevSetting keys, in the same style
> as the existing worked examples.

---

## How it's operated once shipped

```php
// Announce 1.1.0 (build 20) — dismissible notice, old builds keep working.
DevSetting::set('mobile_latest_build_android', '20');
DevSetting::set('mobile_latest_build_ios', '20');
DevSetting::set('mobile_latest_version', '1.1.0');

// Escalate to a hard block only if that release genuinely must be adopted.
DevSetting::set('mobile_min_build_android', '20');

// Emergency off-switch for either.
DevSetting::set('mobile_latest_build_android', '0');
```

`DevSetting` caches for an hour, so a change can take that long to reach clients
(`DevSetting::set` clears the key, so it's immediate on the writing node).

## What the mobile side already does

Built and tested in CoreX-Mobile — no further app work needed for this to go live:

- `lib/services/app_update_service.dart` parses `latest_build` / `latest_version`
  and re-derives `updateAvailable` against its own `kAppBuildNumber`. It enforces
  the no-URL-no-prompt rule client-side too, and **fails open/silent** on every
  error path.
- `lib/widgets/update_available_dialog.dart` is the dismissible dialog
  (Update now / Later).
- It shows **once per release**: "Later" is recorded against the build number, so
  the app never asks twice for the same version. This is what keeps it compliant
  with the app's standing "no intrusive auto-popups on launch" rule.
- It only appears once the user is past auth — never over the login screen, where
  it would collide with the biometric prompt.
- The forced-update screen always supersedes it.
- Coverage: `test/update_prompt_test.dart`.
