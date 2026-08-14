# App Review Information — Notes

Paste the block below into **App Store Connect → App Review Information → Notes**.
Only the credentials, links and company details in `[SQUARE BRACKETS]` still need filling
in. Device/OS versions are filled in — check them against what you actually tested on
before each submission.

---

## 1. Demonstration video

A screen recording of a full session on a physical iPhone is attached / available at:
`[LINK TO SCREEN RECORDING]`

The recording starts from a cold app launch and covers, in order:

1. App launch and splash → sign-in screen
2. Client (consumer) sign-up: email lookup → one-time PIN sent by email → set password
   → consent screen → home
3. Agent (staff) sign-in with email + password, including the optional biometric unlock
   prompt
4. Core features: Today (daily action list), Tasks, Calendar with add/edit event,
   Contacts, Properties (create a listing, capture photos), CORE Matches (buyer
   requirements), Portal Leads, Notifications
5. User-generated content: uploading property photos, a client testimonial, and the
   "Not for me" decline-with-reason path on a shared property
6. Every system permission prompt the app can raise: camera, photo library, microphone
   (Ellie voice capture), notifications and biometrics — each shown being triggered by
   an explicit user tap
7. Account deletion: Settings → Delete account → confirmation → password re-entry →
   signed out

**Paid content / purchases:** the app contains none. There is no in-app purchase, no
subscription, no paywall and no external payment flow. Access is granted by the agency
that employs or engages the user; the app itself never sells anything.

## 2. Devices and operating systems tested

**Apple**
- iPhone 16 Pro — iOS 26.5 (physical device; used for the submitted screen recording)
- iPhone 15 — iOS 26.4 (physical device)
- iPad Air 11" (M2) — iPadOS 26.5
- iPhone SE (3rd generation) — iOS 26.5, Simulator (small-screen layout check)
- MacBook Pro 14" (Apple M3 Pro) — macOS 26.5, Xcode 26.2, Flutter stable: development,
  debugging and local device builds
- Release builds are produced on Codemagic CI (hosted macOS, Mac mini M2, Xcode latest
  stable, Flutter stable) and installed through TestFlight before submission

**Android**
- Huawei P40 Pro — EMUI 12 (Android 10 base), no Google Mobile Services; verified the app
  runs fully without GMS (push notifications are unavailable on that device by design)
- Samsung Galaxy S23 — Android 15 (One UI 7)
- Samsung Galaxy A54 — Android 14
- Google Pixel 7 — Android 16
- Android Emulator (Android Studio): Pixel 6 and Pixel 8, API levels 30 through 36

The app is built with Flutter (stable channel) from a single codebase; the same release
build is verified on both platforms before submission.

## 3. What the app does and who it is for

**CoreX OS** is a private, business-to-business operations app for a real-estate agency
and that agency's own clients. It is not a public property portal or marketplace.

**The problem it solves.** Estate agents run their day across a diary, a spreadsheet, a
CRM and a phone gallery, and things fall through the cracks — an overdue follow-up, an
unsigned mandate, a buyer never matched to a new listing. CoreX OS collapses that into
one prioritised daily action list backed by the agency's central system.

**Target audience.** Two distinct, invitation-only audiences:

- **Agency staff** (agents, branch managers, administrators) — they manage listings,
  contacts, tasks, calendar events, buyer requirement profiles ("CORE Matches"), portal
  leads and compliance documents.
- **Clients of the agency** (buyers, sellers, tenants, landlords) — a client is added by
  their agent and can then see the properties matched to them, react to those matches,
  follow the progress of their own listing, and leave a testimonial.

Members of the public cannot self-register. A sign-up attempt from an email address that
is not on an agency contact list is refused with "You are not on any agency contact list.
Ask your agent to add you."

**Value provided.** Less admin, fewer missed follow-ups, faster buyer-to-listing matching,
and one place where the agent and the client see the same, up-to-date information.

## 4. Setup and access instructions

The app requires an account issued by the agency. Two review accounts are provided:

**Agent / staff account** (full feature set)
- Email: `[REVIEW AGENT EMAIL]`
- Password: `[REVIEW AGENT PASSWORD]`
- Sign in on the first screen with email and password. Biometric unlock is offered
  afterwards and is entirely optional — the password always works.

**Client account** (the consumer-facing side)
- Email: `[REVIEW CLIENT EMAIL]`
- Password: `[REVIEW CLIENT PASSWORD]`
- Tap "I'm a client", enter the email above, then the password. If a one-time PIN is
  requested instead, it is emailed to that address — contact us at `[SUPPORT EMAIL]` and
  we will relay it immediately.

Both accounts are pre-loaded with sample properties, contacts, tasks, calendar events and
matches, so no data setup or sample files are required.

**Reaching the main features once signed in as the agent:**
- **Today** — the landing tab; the prioritised action list. Tap any card to open it.
- **Tasks** — bottom tab; tap "+" to create, tap a row to complete or reschedule.
- **Calendar** — bottom tab; tap a day, then "+" to add an event; tap an event to edit.
- **Hub** — bottom tab → Contacts, Properties, CORE Matches, Portal Leads.
  - Properties → "+" → new listing → "Add photos" raises the **camera** and **photo
    library** prompts.
  - Contacts → a contact → Compliance shows FICA / document status.
- **Ellie (voice assistant)** — the microphone button on the Today tab. Tapping it raises
  the **microphone** prompt; speaking a command such as "book a viewing tomorrow at 3"
  creates the diary entry, with an undo action.
- **Notifications** — the bell icon; the **notification** permission prompt appears here
  and in Settings → Notifications.
- **Account deletion** — Settings (profile icon) → Delete account.

**Signed in as the client:** Home → Matches → tap a property → react, or "Not for me" to
decline it with a reason; My listing → progress and insights; Testimonials → leave one.

**Note on account deletion:** deleting the account removes the person's *login and app
access* and signs them out everywhere. Their record with the agency (deal history,
regulatory FICA documents) is retained by the agency as a business record, as required by
South African financial-intelligence law.

## 5. External services, tools and platforms used

- **CoreX OS backend** (`https://corexos.co.za/api`) — our own Laravel application,
  hosted on `[HOSTING PROVIDER AND REGION]`. It is the sole data store; the app holds no
  third-party keys and talks to no other service directly.
- **Firebase Cloud Messaging (Google)** — push notification delivery only.
- **Anthropic (Claude API)** — powers the "Ellie" assistant: turning a spoken or typed
  instruction into a draft diary entry or task. Called server-side by our backend only.
- **Self-hosted speech-to-text (Whisper, on our own infrastructure)** — transcribes the
  Ellie voice recordings. Audio is uploaded to our backend and never sent to a
  third-party transcription service.
- **Property24 location data** — suburb and area reference data used to normalise listing
  locations and buyer search areas. Supplied through our backend.
- **Codemagic** — CI/CD; builds and uploads the iOS and Android binaries. Not part of the
  running app.
- **Apple / Google platform services** — Keychain and Android Keystore for credential
  storage, Face ID / Touch ID / fingerprint for optional unlock, and the system share
  sheet.

All AI output is presented as a draft that the user confirms, edits or undoes; nothing is
committed to the agency's records without an explicit user action.

There is no analytics SDK, no advertising SDK, no third-party tracking and no App
Tracking Transparency prompt, because the app does not track users across apps or
websites.

## 6. Regional differences

The app is intended for South Africa only and is offered on the South African App Store
storefront alone. Its content is South African throughout: property locations and suburb
data, ZAR pricing, FICA compliance fields under South African financial-intelligence law,
and English-only copy. The agencies and their clients who use it all operate in
South Africa.

Within that scope there are no regional differences at all — there is no country-based
feature gating, no A/B or locale-dependent content, and no geographic restriction
enforced inside the app. The build behaves identically wherever it is launched, so the
review team can sign in and exercise every feature from any location using the accounts
above.

## 7. Regulated industry / third-party material

The app is used by a licensed South African estate agency. Supporting documentation:

- Property Practitioners Regulatory Authority (PPRA) Fidelity Fund Certificate for
  `[AGENCY LEGAL NAME]`, registration number `[FFC NUMBER]` — attached / available at
  `[LINK]`.
- All property listings, photographs and client information in the app belong to that
  agency and are entered by its own staff and clients. No third-party listing feed,
  portal content or licensed media is redistributed through the app.
- Property24 suburb reference data is used under the agency's data agreement with
  Property24 — `[LINK OR "available on request"]`.

**Contact for anything else the review team needs:** `[NAME]`, `[EMAIL]`, `[PHONE]`.
