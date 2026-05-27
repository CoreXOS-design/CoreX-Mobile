# CoreX Mobile Redesign — Login + Home + Coming-Soon

**Spec date:** 2026-05-25
**Branch:** `feature/mobile-redesign-2026-05-25`
**Author:** Claude (Phase 2 spec, awaiting approval)

---

## 1. Overview & scope

Replace the existing two-button login chooser and the simple Quick-Access home hub with the agreed v3 mockup: a polished login screen and a six-section cockpit home, plus a single shared coming-soon screen for any feature route that does not yet exist.

**In scope**
- `LoginScreen` (replaces [lib/screens/auth/login_choice_screen.dart](lib/screens/auth/login_choice_screen.dart))
- `HomeScreen` (replaces [lib/screens/home_hub_screen.dart](lib/screens/home_hub_screen.dart) — file deleted, `AuthGate` swapped)
- `ComingSoonScreen` (one screen, parameterised by `feature`)
- Eleven `Corex*` widgets in `lib/widgets/corex/`
- Per-agency theming pipeline: extend `Branding` with a new `money` color sourced from the API; reuse `branding.button` as the accent
- New ThemeExtension `CorexAccentTheme` exposing accent + money + their derived soft/glow/border tints, wired into `ThemeData.extensions`
- Tabler icon package added
- Widget tests covering screens + the per-agency theming proof

**Out of scope**
- Backend migration adding `colors.money` to `/api/v1/branding/{slug}` and `/api/v1/logged-user` — companion prompt, separate PR
- Real implementations of any module behind a coming-soon route (Today's existing screen is wired live; everything else routes to ComingSoon)
- Profile / Me screen — existing [lib/screens/profile_screen.dart](lib/screens/profile_screen.dart) stays, /me tab routes to it
- Light theme support for the new screens (mobile spec already permits this; both screens are dark-themed per mockup, light theme defers)
- Replacing [lib/screens/main_tabs_screen.dart](lib/screens/main_tabs_screen.dart) — Today tab still uses the existing TodayScreen pushed from the bottom nav

---

## 2. Key decisions (from Phase 1 review)

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | `accent` reuses existing `branding.button` | Single source of truth; the API field already drives every per-agency surface |
| 2 | `HomeHubScreen` is deleted; `AuthGate` returns `HomeScreen` directly | One home, not two |
| 3 | CoreX widgets use radius `14` (overrides `AppTheme.radius = 18` for this redesign only) | Matches the v3 mockup exactly |
| 4 | Add `tabler_icons: ^1.7.0` | Visual fidelity to the mockup |
| 5 | Branch: `feature/mobile-redesign-2026-05-25` | Off `main` |
| 6 | No "agency · branch" strip — just `agency.name` | API does not surface a branch concept |
| 7 | Only `money` is new; `accent` derives from `branding.button` | One new backend field, not two |
| 8 | Use `.withValues(alpha:)` everywhere | Codebase already migrated ([theme.dart:71-97](lib/theme.dart#L71)) |
| 9 | Provider 6.x; Navigator 1.0 `MaterialPageRoute` | Matches existing conventions; no go_router migration |

---

## 3. Platform-fixed tokens — `lib/theme/corex_tokens.dart`

A new file. Pure platform constants — these are **never** tenant-themed.

```dart
class CorexTokens {
  static const pageBase      = Color(0xFF0A0F1C);
  static const pageTopTint   = Color(0xFF16243F);
  static const surfaceTop    = Color(0xFF1B2440);
  static const surfaceBase   = Color(0xFF131A2A);
  static const textPrimary   = Color(0xFFF5F7FB);
  static const textSecondary = Color(0xFF8B9AB5);
  static const textTertiary  = Color(0xFF5C6B85);
  static const textMuted     = Color(0xFF3D4660);
  static const successDelta  = Color(0xFF6BD968);

  static const radius        = 14.0;
  static const radiusButton  = 12.0;
}
```

---

## 4. Agency-driven `CorexAccentTheme`

### 4.1 Model changes (`lib/models/branding.dart`)

Add `money` to `Branding` with a sensible default and JSON parser:

```dart
class Branding {
  final String? logoUrl;
  final Color sidebar;
  final Color icon;
  final Color defaultColor;
  final Color button;
  final Color money;   // NEW

  static const Branding fallback = Branding(
    sidebar: Color(0xFF0EA5E9),
    icon: Color(0xFF0EA5E9),
    defaultColor: Color(0xFF0B2A4A),
    button: Color(0xFF0EA5E9),
    money: Color(0xFFE8B86D),   // NEW
  );

  factory Branding.fromJson(Map<String, dynamic> json) {
    final colors = (json['colors'] as Map?) ?? const {};
    return Branding(
      logoUrl: json['logo_url'] as String?,
      sidebar: _parseHex(colors['sidebar'], fallback.sidebar),
      icon: _parseHex(colors['icon'], fallback.icon),
      defaultColor: _parseHex(colors['default'], fallback.defaultColor),
      button: _parseHex(colors['button'], fallback.button),
      money: _parseHex(colors['money'], fallback.money),  // NEW; safe fallback
    );
  }
}
```

`BrandColors` ThemeExtension gains a matching `money` field, copyWith/lerp updated.

### 4.2 `CorexAccentTheme` — `lib/theme/corex_accent_theme.dart`

A thin ThemeExtension that exposes accent + money along with the derived alpha steps used across every CoreX widget. It reads from `Branding`, never holds raw hex.

```dart
@immutable
class CorexAccentTheme extends ThemeExtension<CorexAccentTheme> {
  final Color accent;       // = branding.button
  final Color accentMoney;  // = branding.money

  const CorexAccentTheme({required this.accent, required this.accentMoney});

  factory CorexAccentTheme.fromBranding(Branding b) =>
      CorexAccentTheme(accent: b.button, accentMoney: b.money);

  factory CorexAccentTheme.defaults() =>
      CorexAccentTheme.fromBranding(Branding.fallback);

  Color get accentSoft   => accent.withValues(alpha: 0.15);
  Color get accentGlow   => accent.withValues(alpha: 0.25);
  Color get accentBorder => accent.withValues(alpha: 0.40);
  Color get moneySoft    => accentMoney.withValues(alpha: 0.15);
  Color get moneyGlow    => accentMoney.withValues(alpha: 0.30);

  static CorexAccentTheme of(BuildContext context) =>
      Theme.of(context).extension<CorexAccentTheme>() ?? CorexAccentTheme.defaults();

  @override CorexAccentTheme copyWith({Color? accent, Color? accentMoney}) =>
      CorexAccentTheme(
        accent: accent ?? this.accent,
        accentMoney: accentMoney ?? this.accentMoney,
      );

  @override CorexAccentTheme lerp(ThemeExtension<CorexAccentTheme>? other, double t) {
    if (other is! CorexAccentTheme) return this;
    return CorexAccentTheme(
      accent: Color.lerp(accent, other.accent, t)!,
      accentMoney: Color.lerp(accentMoney, other.accentMoney, t)!,
    );
  }
}
```

### 4.3 Wiring

`AppTheme._buildTheme` ([theme.dart:310-313](lib/theme.dart#L310)) already pushes `BrandColors.fromBranding(branding)` into `extensions`. Add a second entry:

```dart
extensions: <ThemeExtension<dynamic>>[
  BrandColors.fromBranding(branding),
  CorexAccentTheme.fromBranding(branding),  // NEW
],
```

The existing `Consumer2<ThemeProvider, BrandingProvider>` in [main.dart:84](lib/main.dart#L84) already rebuilds `MaterialApp` when branding changes — no additional plumbing.

---

## 5. Depth recipes

Recipes below are the canonical translations of the mockup's visual depth. Each `Corex*` widget composes from these — none of them inline new hex values.

### 5.1 Ambient page backlight
```dart
Container(
  decoration: const BoxDecoration(
    gradient: RadialGradient(
      center: Alignment(0, -1),
      radius: 1.1,
      colors: [CorexTokens.pageTopTint, CorexTokens.pageBase],
      stops: [0, 0.55],
    ),
  ),
  child: ...,
)
```

### 5.2 CorexCard (default)
- Gradient `surfaceTop → surfaceBase`
- `BorderRadius.circular(14)`
- Inner 1 px-tall white@5% highlight (Stack overlay, positioned top, height 1)
- Bottom seat shadow: `BoxShadow(color: black@30%, offset: (0,1), blurRadius: 0)`

### 5.3 CorexCard accent variant — adds
```dart
border: Border(left: BorderSide(color: accent.accent, width: 2)),
boxShadow: [
  BoxShadow(color: accent.accentGlow, offset: Offset(-10, 0),
            blurRadius: 24, spreadRadius: -10),
  BoxShadow(color: Colors.black.withValues(alpha: 0.30),
            offset: const Offset(0, 1), blurRadius: 0),
],
```

### 5.4 CorexPrimaryButton
```dart
gradient: LinearGradient(
  begin: Alignment.topCenter, end: Alignment.bottomCenter,
  colors: [
    Color.lerp(accent.accent, Colors.white, 0.08)!,
    Color.lerp(accent.accent, Colors.black, 0.08)!,
  ],
),
borderRadius: BorderRadius.circular(12),
boxShadow: [
  BoxShadow(color: accent.accentGlow, offset: Offset(0, 12),
            blurRadius: 28, spreadRadius: -10),
],
// + Stack: 1 px white@25% top line + 1 px black@15% bottom line for catch-light.
```

### 5.5 CorexEllieTeaser
```dart
border: Border.all(color: accent.accentSoft, width: 1),
boxShadow: [BoxShadow(color: accent.accentGlow, blurRadius: 28)],
gradient: LinearGradient(colors: [CorexTokens.surfaceTop, CorexTokens.surfaceBase], ...),
```

### 5.6 Money text
```dart
TextStyle(
  color: accent.accentMoney,
  shadows: [Shadow(color: accent.moneyGlow, blurRadius: 10)],
)
```

---

## 6. Widget inventory — `lib/widgets/corex/`

| Widget | File | Public API |
|---|---|---|
| `CorexCard` | `corex_card.dart` | `{Widget child, bool accent = false, EdgeInsets padding, VoidCallback? onTap}` |
| `CorexPrimaryButton` | `corex_primary_button.dart` | `{required String label, required VoidCallback? onPressed, IconData? leading}` |
| `CorexSecondaryButton` | `corex_secondary_button.dart` | `{required String label, required VoidCallback? onPressed, IconData? leading}` |
| `CorexKpiTile` | `corex_kpi_tile.dart` | `{required String label, required String value, String? delta, bool money = false}` |
| `CorexEllieTeaser` | `corex_ellie_teaser.dart` | `{required VoidCallback onTap}` |
| `CorexTodayFocus` | `corex_today_focus.dart` | `{String? thumbnailUrl, required String address, required List<String> chips, VoidCallback? onTap}` |
| `CorexChip` | `corex_chip.dart` | `{required String label, CorexChipVariant variant = neutral}` enum: `accent \| money \| neutral` |
| `CorexModuleTile` | `corex_module_tile.dart` | `{required IconData icon, required String label, bool dot = false, required VoidCallback onTap}` |
| `CorexBottomNav` | `corex_bottom_nav.dart` | `{required CorexNavTab active, required ValueChanged<CorexNavTab> onTap}` enum: home, today, calendar, ellie, me |
| `CorexMonogram` | `corex_monogram.dart` | no params (renders the C-mark with accent gradient + glow) |
| `CorexAppBar` | `corex_app_bar.dart` | `{required String userInitials, int unreadBadge = 0, VoidCallback? onMenuTap, VoidCallback? onBellTap, VoidCallback? onAvatarTap}` — implements `PreferredSizeWidget` |

All eleven widgets pull their accent/money from `CorexAccentTheme.of(context)`. None of them accept a raw `Color` argument for the accent.

---

## 7. Screens

### 7.1 `LoginScreen` — `lib/screens/auth/login_screen.dart`
Replaces [login_choice_screen.dart](lib/screens/auth/login_choice_screen.dart). `AuthGate` returns `LoginScreen` when logged out. **One unified login** — no user/client chooser. The user enters email + password and the backend decides which app they belong in.

Layout (single screen, no separate email step):
1. SafeArea + ambient backlight container
2. `CorexMonogram`
3. "CoreX OS" wordmark with `ShaderMask` accent on " OS"
4. 32 px accent line
5. Tracked-caps tagline
6. `Email` input (themed `TextField`, `keyboardType: emailAddress`, `textInputAction: next`)
7. `Password` input (`obscureText: true`, `textInputAction: done`, submit on enter)
8. `CorexPrimaryButton(label: 'Continue to your workspace')` — triggers `_submit()`
9. `CorexSecondaryButton(label: 'Scan agent QR', leading: TablerIcons.qrcode)` → `ClientAgentQrScannerScreen`
10. Spacer
11. Version stamp `v 2026.5.25` in `CorexTokens.textMuted`

#### Unified `_submit()` flow

Pseudocode (real implementation in Phase 3 inside a new `UnifiedAuthService` or extension on `AuthProvider`):

```
1. Validate email format + non-empty password locally. Generic error if invalid.
2. POST /api/v1/auth/identify { email }
   → returns { kind: 'user' | 'client_active' | 'client_pending' | 'unknown' }
3. switch (kind):
   case 'user':
     await AuthProvider.login(email, password)
     on success → AuthGate flips to HomeScreen automatically
     on 401 → show generic "Email or password is incorrect" inline error
   case 'client_active':
     await ClientAuthService.login(email, password)
     on success → AuthGate flips to ClientHomeScreen automatically
     on 401 → generic error
     if response signals passwordMustChange → AuthGate handles set-password
   case 'client_pending':
     await ClientAuthService.startOtp(email)
     push ClientOtpScreen(email: email, nextStep: 'set_password')
     on OTP success → push ClientSetPasswordScreen(isFromActivation: true)
     on completion → ClientSessionProvider lights up → AuthGate → ClientHomeScreen
   case 'unknown':
     show the SAME generic error ("Email or password is incorrect")
     never reveal whether the email exists
4. Any network failure → generic toast, no crash, button re-enabled.
```

**Generic-error rule:** the message is identical for invalid-email, wrong-password, unknown-account, and locked-account. The only screen that diverges is the OTP path, which intentionally surfaces "Verify your email to finish setting up your account" — that text appears *only* after the backend has confirmed `client_pending`, so it cannot be used as an enumeration oracle for users that have already activated.

StatusBar: light icons via `SystemUiOverlayStyle.light`.

#### Backend contract — `/api/v1/auth/identify`
**New endpoint** required (companion backend prompt):
- `POST /api/v1/auth/identify` body `{ "email": "..." }`
- Returns 200 with `{ "kind": "user" | "client_active" | "client_pending" | "unknown" }`
- **MUST** always return 200 with `unknown` (never 404) so the response time and shape don't leak existence.
- **MUST** be rate-limited (Laravel `throttle:10,1` minimum).
- **MUST NOT** include any other field (no name, no agency hint).

If the backend can't ship the identify endpoint in time, the Phase 3 fallback is to attempt user login first, fall back to client login on 401-with-`user_not_found`, fall back to OTP-start on 401-with-`client_pending`. Slower (up to 3 round-trips), correct, ships independently. Flag this in Phase 3.

### 7.2 `HomeScreen` — `lib/screens/home/home_screen.dart`
Replaces `HomeHubScreen` ([home_hub_screen.dart](lib/screens/home_hub_screen.dart)). `AuthGate` ([main.dart:255](lib/main.dart#L255)) swaps to `HomeScreen`. The `HomeHubScreen` file is deleted.

Layout, top-to-bottom:
1. `CorexAppBar` — hamburger | "CoreX OS" wordmark (OS in accent gradient) | bell with dot | avatar with `AuthProvider.userName` initials
2. **Agency context strip** — `agency.name` only (no branch). Read from `BrandingProvider` or the logged-user payload.
3. **Greeting block** — "Good {timeOfDay}, {firstName}." + business pulse line built from real provider data: pending signatures, FICA in-review, viewings today. Any count that's unavailable is omitted; never render `0`.
4. `CorexEllieTeaser` — tap → `ComingSoonScreen(feature: 'Ellie')`
5. **3-up KPI strip** — `CorexKpiTile(label: 'Mandates', …)`, `CorexKpiTile(label: 'FICA', …)`, `CorexKpiTile(label: 'May GCI', …, money: true)`. Values pulled from `DashboardProvider`; missing → `'—'`.
6. `CorexTodayFocus` — currently active property, or a quiet "No focus set today" placeholder card.
7. **Workspace** section header + "All →" `TextButton` (routes to `RealEstateHubScreen`)
8. **3×2 module grid** — Properties, Contacts, FICA (dot if pending > 0), E-sign, Commission, Training (see §8)
9. `CorexBottomNav(active: home)`

StatusBar: light. `SafeArea` wrap.

### 7.3 `ComingSoonScreen` — `lib/screens/coming_soon_screen.dart`
```dart
class ComingSoonScreen extends StatelessWidget {
  final String feature;
  final String? description;
  const ComingSoonScreen({super.key, required this.feature, this.description});
  ...
}
```
- Ambient backlight
- Centered Tabler `sparkles` icon at 48 px in `accent.accent`
- Feature name (28 sp, w700)
- "COMING SOON" tracked caps in textSecondary
- Optional description in textSecondary (max 2 lines)
- Bottom: `CorexSecondaryButton(label: 'Back', leading: TablerIcons.arrow_left)` → `Navigator.pop`

---

## 8. Navigation & module routing matrix

Routes are `MaterialPageRoute` (Navigator 1.0 — no go_router introduced).

| Trigger | Destination | Args |
|---|---|---|
| `AuthGate` logged out | `LoginScreen` | — |
| `AuthGate` logged in | `HomeScreen` | — |
| Bottom nav: Home | (stay) | — |
| Bottom nav: Today | existing `TodayScreen` ([lib/screens/today/today_screen.dart](lib/screens/today/today_screen.dart)) | — |
| Bottom nav: Calendar | existing `CalendarScreen` ([lib/screens/calendar_screen.dart](lib/screens/calendar_screen.dart)) | — |
| Bottom nav: Ellie | `ComingSoonScreen` | `feature: 'Ellie', description: 'Your AI assistant for CoreX'` |
| Bottom nav: Me | existing `ProfileScreen` ([lib/screens/profile_screen.dart](lib/screens/profile_screen.dart)) | — |
| Ellie teaser tap | `ComingSoonScreen` | `feature: 'Ellie', …` |
| Module: Properties | existing `PropertyListScreen` | — |
| Module: Contacts | existing `ContactsListScreen` | — |
| Module: FICA | `ComingSoonScreen` | `feature: 'FICA'` (no dedicated screen yet — there's only [contact_compliance_screen.dart](lib/screens/contacts/contact_compliance_screen.dart) which is per-contact) |
| Module: E-sign | `ComingSoonScreen` | `feature: 'E-sign'` |
| Module: Commission | `ComingSoonScreen` | `feature: 'Commission'` |
| Module: Training | `ComingSoonScreen` | `feature: 'Training'` |
| Workspace "All →" | existing `RealEstateHubScreen` | — |

Today/Calendar/Profile use their existing implementations. Bottom-nav taps push them as full routes (consistent with current Navigator-1.0 conventions in the codebase).

---

## 9. API contract — companion backend prompt

**Required** for the redesign to look right per-agency. Until shipped, defaults (money = `#E8B86D`) are used and the UI still works.

### 9.1 `/api/v1/branding/{slug}` and `/api/v1/logged-user` (branding block)

Both endpoints already return:
```json
{
  "logo_url": "...",
  "colors": {
    "sidebar": "#…",
    "icon": "#…",
    "default": "#…",
    "button": "#…"
  }
}
```

**Required additions:**
```json
{
  "colors": {
    "money": "#E8B86D"   // NEW — nullable; null falls back to platform default
  }
}
```

That is, **one new field**: `colors.money`. No change to the existing four.

### 9.3 `POST /api/v1/auth/identify` (NEW)

Required for the unified single-button login (§7.1).

- Body: `{ "email": "..." }`
- Always 200. Body: `{ "kind": "user" | "client_active" | "client_pending" | "unknown" }`
- Constant-time response shape — never 404, never any field beyond `kind`.
- Rate-limited (`throttle:10,1` minimum).

Backend prompt to ship alongside:
1. Route + controller `AuthIdentifyController@__invoke`
2. Resolve order: users table first → clients table; if client row exists but `password` is null/`activated_at` is null → `client_pending`; else `client_active`.
3. Any other path → `unknown`.
4. Add request log entry (email hash + result `kind`) for fraud monitoring; never log raw email.

### 9.2 Backend prompt (separate PR — do NOT implement in this PR)
1. Migration: `add_money_color_to_agencies` — nullable string column `money` on the agencies table.
2. Seed agency_id=1 (HFC) with `#E8B86D`.
3. Expose `money` on the AgencyResource / branding block of UserResource.
4. Tinker verification of both endpoints.

---

## 10. Test plan

### 10.1 Static checks
- `flutter analyze` — zero issues.
- `dart format --set-exit-if-changed lib/` — exit 0.
- `flutter test` — all pass.
- `flutter build apk --debug` — compiles.

### 10.2 Widget tests (new — `test/screens/`, `test/widgets/corex/`)

| Test | Asserts |
|---|---|
| `login_screen_test.dart` | renders monogram, email + password inputs, primary button, QR secondary, version stamp |
| `login_screen_routing_test.dart` | stub identify endpoint → 'user' calls AuthProvider.login; 'client_active' calls ClientAuthService.login; 'client_pending' pushes OTP; 'unknown' shows generic error. Verify error string is byte-identical across 'unknown' and a 401 from 'user'. |
| `home_screen_test.dart` (stub User + Branding) | renders AppBar, agency strip, greeting, Ellie teaser, 3 KPI tiles, today focus, workspace header, 6 module tiles, bottom nav |
| `coming_soon_screen_test.dart` | renders the passed `feature` value and optional description |
| `corex_accent_theme_test.dart` | **the per-agency proof.** Pump `HomeScreen` inside a MaterialApp whose `theme.extensions` contains `CorexAccentTheme(accent: Color(0xFF7C3AED), …)`. Walk to a `CorexPrimaryButton`, the Ellie border, and the active `CorexBottomNav` item — all three must resolve to purple. None of them is allowed to be teal. |
| `corex_card_test.dart` | accent-variant renders the left border + leftward glow |
| `corex_kpi_tile_test.dart` | money variant uses `accentMoney` color and adds the glow shadow |

### 10.3 Manual on emulator
Capture screenshots:
1. LoginScreen matches v3 mockup
2. HomeScreen matches v3 mockup (six sections in order)
3. Bottom nav: tap Today / Calendar / Ellie / Me — each lands correctly
4. Workspace tiles: tap each — real module or coming-soon with the right name
5. Ellie teaser tap → ComingSoon('Ellie')
6. Stub `colors.money = '#7C3AED'` and `colors.button = '#7C3AED'` → entire UI re-themes to purple, no teal anywhere except platform tokens

Not done until all of the above pass.

---

## 11. Commit plan (one per logical chunk)

1. `feat(theme): add money color to Branding + CorexAccentTheme extension`
2. `feat(theme): add CorexTokens platform constants`
3. `feat(widgets): add Corex* widget kit (11 widgets)`
4. `feat(screens): add ComingSoonScreen`
5. `feat(screens): replace LoginChoiceScreen with LoginScreen`
6. `feat(screens): replace HomeHubScreen with HomeScreen`
7. `chore(deps): add tabler_icons`
8. `test: cover redesign screens + per-agency theming proof`
9. `docs: add mobile-redesign spec`

---

## 12. Open questions / flags for Phase 3

1. **Identify endpoint availability.** Does the backend team have capacity to ship `POST /api/v1/auth/identify` in the same window, or do we ship the 3-call fallback first and migrate to identify later? (Spec §7.1)
2. **Agency name source**. Confirm the field name on the logged-user payload — `agency.name`, `agency_name`, or under `branding`? Will inspect in Phase 3.
3. **First-name extraction**. `AuthProvider.userName` is currently the full name. Need to split for the greeting — confirm full name format.
4. **Business pulse counts**. Confirm which provider exposes pending signatures, FICA in-review, viewings today. Likely a mix of `DashboardProvider` and `NotificationsProvider` — to be wired in Phase 3.
5. **Today focus property**. Is there a "currently active property" concept on `PropertyProvider` today, or does the focus card need a new selector?

---

**STOP HERE. Awaiting your approval of this spec before Phase 3 (build).**
