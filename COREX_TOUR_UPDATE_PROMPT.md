# PROMPT — Update the "CoreX OS Interactive Guided Tour" to match the current app

Copy everything below this line into the web Claude conversation that already contains your CoreX OS tour page (so it can edit the existing artifact). If you're starting a fresh conversation, first paste the existing HTML, then paste this.

---

You previously built me a single-file, self-contained web app called the **CoreX OS Interactive Guide** — a pixel-faithful, clickable replica of our Flutter mobile app wrapped in a guided tour. The real app has since moved on (we're now on version **1.0.10**, up from 1.0.0). I need you to **update the existing page** to match the current app.

**This is an update, not a rebuild.** Keep the existing structure, design system, component library, tour engine, demo data and everything that still holds. Change only what's listed below. Where I say a screen "is unchanged," do not touch it. Where I give verbatim copy, use it exactly.

A few things up front so you don't over-correct:

- **The design system did not change.** All colours, radii, fonts, gradients, shadows and tokens are exactly as before. Do **not** restyle anything. The accent is still `#0EA5E9`, money gold still `#E8B86D`, pillar colours unchanged, the AI badge still purple.
- **Ellie gained no new powers.** She still does exactly one thing — book a calendar event from a voice command — with an Undo. Don't invent new AI capabilities. (There *is* one change to Ellie: a microphone-permission flow. It's in §5.)
- **The Home cards, the Workspace module grid (still the same four modules), the Compliance card's four gates, and the login screen's static copy are all unchanged** in content. Some of these screens changed *structurally* (see below) but their copy and data are the same.

Work through the sections below and apply each change. Then run the acceptance checklist at the end.

---

## §0 — GLOBAL CHANGES (apply everywhere they appear)

### 0.1 Version number bumped: 1.0.0 → 1.0.10
The app is now version **1.0.10**, build **18**. Update every place the version shows:
- **Login screen footer:** was `v1.0.0` → now **`v1.0.10`**.
- **Settings → About → Version:** now shows **`1.0.10 (18)`** (the version with build number in parentheses).
- The new **force-update** and **update-available** screens (§1) also show `1.0.10 (18)` — see their copy.

### 0.2 Enum/status values are now "label-cased" (acronym-safe) everywhere
The app added a display helper that title-cases machine values coming from the API **without lowercasing anything** — so it only ever *raises* the first letter of each word, which keeps acronyms intact. Apply this rule to **every status chip, type pill and enum-shaped label** in the replica:

- `active` → **Active**
- `under_offer` → **Under Offer**
- `sole_mandate` → **Sole Mandate**
- `not_started` → **Not started** (in a sentence) / **Not Started** (standalone chip)
- Acronyms already capitalised survive untouched: **FICA**, **OTP**, **P24**, **VAT** stay exactly as-is (never "Fica" or "p24").

Rule of thumb: replace `_` and `-` with spaces, collapse whitespace, capitalise the first letter of each word, and **never touch existing capitals**. This is for machine values only — **user-typed text (names, notes, descriptions) must render exactly as entered**, so don't apply it there.

Right now the replica likely shows raw values like "active" or "under_offer" on property/contact cards and status chips. Fix all of those.

### 0.3 Wide-screen content cap (only relevant if your replica has a desktop/tablet view)
The app now **centres page content at a max width on wide viewports** — 720px for general content, 480px for forms/auth — while letting the background gradient bleed full-width behind it. Inside the phone frame this has no visible effect, so if your tour only ever renders the app at phone width, **skip this**. If you added a tablet/desktop preview, apply the cap there: a centred 720px column (480px for forms) over an edge-to-edge backlight.

### 0.4 External-link fallbacks (minor, worth a one-line mention in explanations)
When a `tel:` / `sms:` / `mailto:` link can't open (e.g. a tablet with no phone app), the app now copies the number/address to the clipboard and shows a snackbar instead of failing silently. You don't need to simulate the clipboard, but if any explanation panel discusses Call/WhatsApp/Email actions, you can note this graceful fallback.

---

## §1 — NEW: APP-LIFECYCLE & ACCOUNT SCREENS (add these)

These are entirely new since your build. They exist mostly to satisfy App Store / Play requirements, and they're genuinely useful tour material.

### 1.1 Force-update gate (blocking, shown BEFORE login)
A hard gate. On launch and on every resume, the app asks the server whether the installed build is still supported; if it's below the minimum, this screen replaces the entire app — **no back button, no dismiss, Android system-back is swallowed.** It appears *before* the login screen.

Build it as a full-screen centred layout:
- Icon: a "system update" glyph in the brand accent.
- Title: **"Update required"**
- Body: **"This version of CoreX is no longer supported. Update to the latest version to carry on."** *(An operator can override this with a custom message; use the default.)*
- Primary button: **"Update now"** (would open the store).
- Footer line: **"Installed: 1.0.10 (18)"**

**Teach the logic** (it's in my project notes, and learners' agencies ask about it): the gate is driven by a server `min_build`. It **fails open** — if the check errors, times out, or no update URL is configured, the user is let straight through. It only ever latches on; it never flickers off mid-session.

For the tour: add a control (a button in the tour UI, or a step) that **triggers the force-update gate on demand** so the learner can see it, then dismiss it back to the app for the demo.

### 1.2 Optional "Update available" dialog (dismissible, shown AFTER login)
A softer nudge, driven by a separate `latest_build` dial. Shown as a **dismissible dialog**, but only once the user is already inside the app (never on the login screen), and **only once per release** — tapping "Later" snoozes it against that build number so it won't nag again until a genuinely newer build ships.

- Icon: system-update glyph, brand accent.
- Title: **"Update available"**
- Body: **"CoreX 1.1.0 is ready to install. Update to get the latest fixes and features."** *(the "1.1.0" is the target version; fall back to "build N" if no version name.)*
- Second line: **"You're on 1.0.10 (18)"**
- Buttons: **"Update now"** (filled, brand) and **"Later"** (text button). Tapping outside the dialog = "Later".

Make it clear in the explanation that this and the force-gate are mutually exclusive: forced = terminal and before auth; optional = dismissible, one nudge per release, inside the app.

### 1.3 Delete account — AGENT (new, App Store requirement)
A two-step destructive flow.

**Entry points (add both):**
- **Profile screen:** a quiet red text button with a trash icon, **"Delete my account"**, sitting directly *beneath* the existing "Sign out" button (deliberately less prominent than Sign out).
- **Settings screen:** a **new "Account" section** whose row is a red **"Delete my account"** with a trash icon and chevron.

**Step A — confirm dialog** (this is one of the app's few real centred dialogs, alongside the "Missing Required Fields" one):
- Title: **"Delete your account?"**
- Body: **"Your CoreX app account will be deleted and you will be signed out of this device."**
- Buttons: **"Cancel"** and **"Delete"** (Delete is destructive red).

**Step B — password screen** (rendered on the auth-style scaffold: glow background, transparent app bar with a back arrow, big 30px left-aligned title, subtitle below):
- Title: **"Delete account"**
- Subtitle: **"Enter your password to delete your CoreX app account. You will be signed out on this and every other device immediately."**
- A password field (hint **"Password"**, lock icon, show/hide eye). Empty-field validator: **"Enter your password"**.
- Primary red button: **"Delete my account"**
- Secondary text button: **"Cancel"**
- Success toast: **"Your account has been deleted."** → then signed out to login.

**Error states** (render inline in the auth-error style — red warning icon + red text):
- Network: **"Could not reach the server. Check your connection."**
- Session expired (401): **"Your session has expired. Sign in again to delete your account."**
- Rate-limited (429): **"Too many attempts. Please try again in a minute."**
- Wrong password: **"Incorrect password."**

**Teach the nuance:** this deletes the agent's *app sign-in access*, not their CoreX business record. Restoring access is web-only. That's why, if a deleted user tries to sign in again, the login screen shows: **"This account has been deleted. To use the app again, restore app access from My Portal → Tools on the CoreX website, or ask your administrator."** (add that as a login error state — see §5.4).

### 1.4 Delete account — CLIENT (new)
Same shape, client wording.

**Entry point:** Client Settings gains a **"DANGER ZONE"** section (with a divider above it): a red **"Delete account"** row (trash icon), plus helper text beneath: **"Permanently deletes your CoreX account and signs you out of every device. This cannot be undone."**

**Step A — confirm dialog:**
- Title: **"Delete your account?"**
- Body: **"Your account will be permanently deleted and you will be signed out of every device. This cannot be undone."**
- Buttons: **"Cancel"**, **"Delete"** (destructive).

**Step B — password screen** (auth scaffold):
- Title: **"Delete account"**
- Subtitle: **"Confirm your password to permanently delete your account. Your account will be deleted immediately and you will be signed out of every device. This cannot be undone."**
- Password field (hint **"Password"**), validator **"Enter your password"**.
- Primary red button: **"Delete account"**
- Text button: **"Cancel"**
- Success toast: **"Your account has been deleted."**
- Error states: same four as the agent flow, except the wrong-password message here is **"Password is incorrect."**

---

## §2 — CHANGED: DETAIL SCREENS ARE NOW TABBED

This is the biggest structural change. Both the **Property Overview** and the **Contact detail** screens moved from one long scroll to a **collapsing hero + a pinned tab bar + one independently-scrolling view per tab**. Introduce a shared "tabbed detail" pattern for both.

**The tab-label convention:** a tab shows just its name, or `Name · N` when it has a count (e.g. `Contacts · 4`, `Matches · 3`, `Drive · 7`). Build that into the tab component.

### 2.1 Property Overview → tabbed
The old single scroll (Hero → At a glance → Compliance → Contacts → Description → portals → agents → owner → Key dates → …) is gone. Reorganise the **exact same content** (copy unchanged) into these tabs, in this order:

1. **Info** — the collapsing **hero stays above the tab bar** (status pill, "{n} days on market" chip, title, suburb, gold price — unchanged). Under the **Info** tab: **At a glance** (the spec strip), **Description** (with **"Read more"** / **"Show less"**), **"Open Live Preview"**, **"Where this listing is published"** (the portal cards — copy unchanged, including *"Not yet published to any portal"* / *"This listing isn't live anywhere yet — open Syndication on the desktop to publish."*), **Virtual Tour**, and **Key dates** (Listed / Expires / Loaded / Modified).
2. **Compliance** — the compliance card, moved verbatim: the **LIVE / READY / BLOCKED** badge, the four gates (**Authority to market**, **Seller FICA**, **Photos**, **Listing details**), **"Blocking go-live"**, **Sellers** with FICA badges, **"Next actions"**, and the **"Send Authority to Market"** button with its helper *"Resolve the items above to enable sending to market."* All unchanged — just now on its own tab. (Show a small spinner in this tab while compliance data "loads.")
3. **Contacts · {count}** — **three old sections merged into one tab**: the linked Contacts (with **"Add contact"**, empty state *"No contacts linked yet."*, the unlink dialog), the **Listing Agent(s)** (**"Lead agent"** / **"Co-agent"**), and the **Owner** card. The count badge = linked contacts + agents + owner.
4. **Drive · {count}** — a brand-new tab. See §2.3.
5. **Inspections** — only present when the property is a rental. Contains the **"Rental Inspections"** card (*"In, out & custom inspection galleries"*).

Also: the app-bar title on this screen **is now the property's title** (e.g. "12 Beach Road, Uvongo"), not the literal word "Overview". (The loading/error state still says "Overview".)

### 2.2 Contact detail → tabbed
Same treatment. The app-bar title still shows the contact's full name with the edit pencil.

- **New collapsing hero** (does *not* repeat the name — the app bar has it): a larger initials avatar, the contact-type pill (label-cased, per §0.2), and a one-line "reach" summary joining phone and email with a middle dot — e.g. `082 555 1234  ·  john@example.co.za`.
- **Three tabs:**
  1. **Details** — holds the actions and the details card. Top: the primary **"WhatsApp"** button (busy state **"Opening…"**) and the **"+ Match"** / **"+ Listing"** secondary row. Then the **details card**: the phone / email / ID rows and the green **"WhatsApp · {n}"** pill with **"last {date}"**. **New empty state** when a contact has no phone/email/ID and no WhatsApp history: **"No phone, email or ID captured yet. Tap Edit to add them."** Then the **Compliance** tile (**"Compliance"** / *"Consent · Documents · FICA"*).
  2. **Matches · {count}** — empty state unchanged: **"No matches yet"** / *"Tap + Match to capture buyer or tenant criteria."* Match rows show a status pill (now label-cased) and `For Sale · Uvongo · R1 200 000 – R2 500 000`.
  3. **Properties · {count}** — **note the tab is now labelled "Properties" (was "Linked Properties")**, though the empty-state heading is still **"No linked listings"** / *"Tap + Listing to create a property tied to this contact."*

### 2.3 NEW: the "Property Drive" (Drive tab)
A **read-only** per-property document store — every file filed against the listing on the web, shown here with folder chips and per-row download. **Uploading, tagging and deleting are web-only** — this tab only views and downloads. Say that in the explanation; it's a common point of confusion.

The card itself has **no title heading** (its identity is the "Drive" tab label). Layout:

- **Folder chips** (a horizontal row): an **"All"** chip first with the total count, then one chip per folder showing its label and count. The selected chip is brand-coloured. A count of 0 is hidden. (An "Unfiled" bucket appears only if the server sends one.)
- **Document rows** — each: a file-kind icon tile (pdf / image / doc / sheet / generic, each with its own tint), the filename (one line, ellipsised), and a metadata line joining `size · uploaded-by · relative-time` with middle dots (blanks dropped) — e.g. `1.2 MB · Andre Roets · 3d ago`.
- **Per-row actions:** two icon buttons — **Download** (tooltip **"Download"**) and **Share** (tooltip **"Share"**). While a download is in flight, that button becomes a spinner. If the account has downloads switched off, **both are greyed** with the tooltip **"Downloads are switched off for your account"**.

**Download-complete dialog** (simulate it):
- Title: **"Download complete"**
- Body: **"{filename}\nSaved to {location}."** (e.g. *"Mandate.pdf\nSaved to Downloads."*)
- Buttons: **"Done"** and **"Open"**
- If nothing can open the file type: snackbar **"No app on this device can open {filename}."**

**States:**
- Loading: a small centred spinner.
- Fetch failed: a cloud-off icon + **"Couldn't load files."** + a **"Retry"** button.
- Property has no files: **"No files on this property yet."**
- A folder filter with no matches: **"No files in this folder."**

For demo data, give one or two properties a Drive with a few files across folders (e.g. a **Mandate** folder with `Mandate.pdf`, a **FICA** folder with `Seller ID.jpg`, `Proof of address.pdf`, and an **Unfiled** item), so the folder chips, download dialog and empty-folder state can all be shown. Give the blocked "7 Marine Drive" property an empty Drive so learners see the empty state.

---

## §3 — CHANGED: the photo gallery upload sheet

The upload sheet (**"Upload Photos"**) kept its header, tag chips, the three source buttons (**"Multi Capture"** / **"Native"** / **"Gallery"**), and the **"Upload N photo(s)"** button — but the mechanics were rebuilt. Update your simulation to include:

- **A new "Preparing" state.** Picked photos are downscaled and orientation-corrected before they enter the queue. While that runs, show a spinner + **"Preparing photos…"**, and disable the three source buttons.
- **A durable queue.** Photos survive closing the sheet (and, in the real app, an app restart). You can note this in the explanation; you don't have to persist across page reloads.
- **Concurrent uploads with retry.** Up to **3 at a time**, up to **3 attempts each** with a short backoff between tries. Each queued thumbnail shows a spinner while it's uploading.
- **New queue header copy:** while uploading, **"Uploaded 3 of 8…"**; otherwise **"{n} selected"**.
- **New failed-list copy:** header **"2 photos didn't upload — tap to retry"** (in red), with a new **"Retry all"** button (shown only when more than one failed and nothing is currently uploading), plus a per-row **"Retry"** button. (This replaces the old "Failed (n) — tap to retry".)
- **New batch-result snackbars:** success **"5 photos uploaded"**; partial **"2 photos didn't upload — tap Retry below"**; stale tags mid-batch **"Some tags are no longer available — please re-select"**.
- **New storage-full snackbar:** **"Couldn't add 2 photos — device storage may be full"**.

Unchanged (keep as-is): the **"Tag this photo"** section, the **"No tag"** chip, the no-spaces note *"This property has no spaces yet — photos will upload to Unsorted."*

The demo you already have — upload several photos, one fails, retry it — still works; just route it through the new "Preparing…" → concurrent-upload → "Retry all" flow and update the copy. (Behind the scenes the app now also compresses images and converts iPhone HEIC to JPEG before upload; you can mention this as a one-liner but nothing visual changes.)

---

## §4 — CHANGED: Ellie gets a microphone-permission flow

Ellie's screen and interaction are otherwise **identical** (same header **"Ellie"** + purple AI badge, same status lines, same hint *'Try: "Book a viewing with John at 12 Beach Road tomorrow at 11am"'*, same 140px push-to-talk mic that turns red while recording, same **"LAST TRANSCRIPT"** card, same result sheet that Schedules an event with **Undo** / **Open event**). **Do not change any of that.**

What's new is a permission gate before she can hear you. Add a **"microphone needed"** state to the Ellie screen:

- When the mic isn't granted yet, the **mic button shows a `microphone-off` icon** (instead of the normal mic), and the copy changes:
  - Status line: **"Ellie needs your microphone to hear you"**
  - Hint line becomes an instruction (replacing the "Try:" example):
    - if permanently denied: **"Turn on Microphone for CoreX in Settings, then come back."**
    - if just denied: **"Tap the mic to allow access."**
  - Button caption (replacing "Hold to talk"):
    - permanently denied: **"Open Settings"**
    - denied: **"Tap to enable"**
- **The first press asks for access and does not record** — you must press again once granted. Simulate this: first tap on a "not yet granted" Ellie flips it to granted with the snackbar **"Microphone on — hold the mic and speak."**; *then* holding records as normal.
- Permission snackbars to include:
  - granted: **"Microphone on — hold the mic and speak."**
  - denied: **"Ellie needs the microphone to hear you."**
  - permanently denied: **"Microphone access is off for CoreX. Turn it on in Settings."** with a **"Settings"** action button.
- If recording fails to start even with permission: **"Couldn't start recording — check nothing else is using the mic."**

This is worth a short tour beat — permission prompts are exactly where non-technical users get stuck, so showing the "needs mic → tap to enable → granted → hold to talk" sequence is genuinely helpful. Add a tour control to toggle Ellie between "mic not yet granted" and "granted" so the learner can see both.

The **"Ellie voice isn't available on this account yet."** disabled-account state (feature flag off) is unchanged.

---

## §5 — SMALLER CHANGES

### 5.1 Home screen: the app-bar avatar is gone
The initials avatar was removed from the Home app bar — the account now lives on the "Me" tab. So the Home app bar is now: **menu · "CoreX OS" wordmark · QR · bell** (no avatar on the right). Remove the avatar from Home's app bar. (Other screens that used a plain app bar are unaffected.) The Home content — greeting, Meet Ellie card, Next Appointment card, Workspace grid — is otherwise unchanged.

### 5.2 Calendar event edit-lock: new messages, and status no longer locks
Two changes to when an event can't be edited:
- **An event's status never locks it any more.** Only its *source* does.
- The old single message *"This event can't be edited."* is replaced by two, depending on why:
  - A private event belonging to someone else: **"This is someone else's private event."**
  - An event synced from another record: **"This event comes from another record and is kept in sync with it — change it at the source."**
- User-created events that never stamped a source are now correctly editable (they used to sometimes read as read-only). If your replica simulates a locked event, use the new copy.

### 5.3 Notification settings: the test button was removed
Delete the **"Send test notification"** button (and its *"Test notification sent — check your notification bar."* success copy) from the notification-settings screen. Everything else on that screen stays.

### 5.4 Login screen: new states (static copy otherwise unchanged)
The wordmark, tagline **"YOUR REAL ESTATE OS"**, and the **"Continue to your workspace"** button are unchanged. Add/adjust:
- **Fingerprint sign-in.** A secondary **"Unlock with fingerprint"** button appears when biometrics are enabled and available. After the first successful password sign-in, a one-time dialog offers to turn it on:
  - Title: **"Use your fingerprint to sign in?"**
  - Body: **"Unlock CoreX with your fingerprint next time instead of typing your password."**
  - Buttons: **"Not now"** and **"Enable"** (with a fingerprint icon).
  - If enabling fails: snackbar **"Biometric sign-in wasn't enabled. You can turn it on in Settings."**
  - A hint block for when the session was lost: **"Sign in with your password once to switch fingerprint sign-in back on — this device doesn't have your session any more."**
- **The QR entry was reframed as account creation** (App Review wording): the secondary button is now **"Create your account"** (QR icon) with helper text **"New client? Create your account by scanning your agent's QR."** (Previously "Scan agent QR".)
- **Deleted-account error** (see §1.3): **"This account has been deleted. To use the app again, restore app access from My Portal → Tools on the CoreX website, or ask your administrator."**
- **Unknown-email error** now reads: **"We couldn't find that email. Ask your agency to add you, or create your account by scanning your agent's QR code."**

Correspondingly, in **Settings → Security**, the biometric row label is **"Fingerprint sign-in"** (or **"Fingerprint not available"** when unsupported) — update it if yours said "Biometric sign-in".

### 5.5 My QR Code screen: Save now gives feedback
The **"Save Image"** button used to be silent; it now confirms:
- Android: **"corex-qr.png saved to Downloads"** (Android saves to the Downloads folder now, not the gallery).
- iOS: **"Saved to Photos"**.
- If tapped before the image is ready: **"The QR image hasn't finished loading yet."**
- On failure: **"Could not save image: {reason}"**.
The screen's title and body copy (**"Your Client QR"** / *"Hand this to prospects…"*) are unchanged.

---

## §6 — NEW / UPDATED TOUR CHAPTERS

Fold these into the existing chapter structure (keep your numbering scheme; insert where they fit):

- **New chapter — "Keeping the app up to date"**: explains the force-update gate vs the optional update nudge, why the gate fails open, and what the "Installed: 1.0.10 (18)" line means.
- **New chapter — "Deleting your account"**: walk both the agent and client flows, and explain the app-access-vs-business-record distinction and that restore is web-only.
- **New chapter — "Fingerprint sign-in"**: the enable dialog and the unlock button.
- **Update chapter — "Uploading a property"**: the property Overview is now **tabbed** — teach the Info / Compliance / Contacts / Drive / Inspections tabs, and make **"why won't my listing go live?"** point specifically to the **Compliance tab**.
- **New sub-section — "The Property Drive"**: what it is (a read-only view of the listing's web documents), how to download a file, and that uploads happen on the web.
- **Update chapter — "Adding a contact" / contact detail**: the contact page is now **tabbed** (Details / Matches / Properties).
- **Update chapter — "Meet Ellie"**: add the microphone-permission beat before the booking demo.
- **Update the design-language / "reading the interface" chapter**: mention that status and type labels are shown in Label Case (Active, Under Offer, Sole Mandate) while acronyms like FICA and P24 keep their capitals.

Update the tour's progress/version indicator (if any) to reflect the new version, and refresh any "what's new" or intro copy that references the old version number.

---

## §7 — DO NOT TOUCH (explicitly unchanged)

To stop you over-editing, these are confirmed unchanged and must stay exactly as they are:
- The entire **design system**: colours, gold money, purple AI badge, pillar colours, radii, fonts, gradients, shadows, spacing.
- **Ellie's capabilities and result sheet** (still only books a viewing, still Undo / Open event). Only the mic-permission states are new.
- The **Home** greeting, Meet Ellie card, Next Appointment card, and the **Workspace grid's four modules** (Properties / Contacts / Core Matches / Portal Leads).
- The **Compliance card's four gates** and all their copy (now living on the Compliance tab, but unchanged in content).
- The **login** wordmark, tagline, and primary button copy.
- **Today**, **Calendar** (views, FAB), **Tasks** (kanban, swipes, Quick Add), **Core Matches**, **Portal Leads**, **Notifications** (grouping), and the whole **client portal** flow (reactions, "Not for me" sheet, seller insights, testimonials, tri-state consent) — all unchanged except where §0.2 (label-casing) touches a status/type string.
- The **contact "New Contact" form**, the **property 4-step wizard steps 1–3** (address, details, spaces), the **duplicate-contact dialog**, the **"Missing Required Fields" dialog** — unchanged. (Only the gallery upload sheet in step 4 changed — see §3.)

---

## §8 — ACCEPTANCE CHECKLIST

Before calling it done:

- [ ] Every version string reads **1.0.10** (login footer `v1.0.10`; About and update screens `1.0.10 (18)`). No `1.0.0` remains.
- [ ] All status/type chips render in Label Case (Active, Under Offer, Sole Mandate), and acronyms (FICA, P24, OTP) keep their capitals. User-typed text is untouched.
- [ ] The **force-update gate** is reachable, blocks the whole app, has no dismiss, and shows the exact copy + "Installed: 1.0.10 (18)".
- [ ] The **optional update dialog** is dismissible and shows "You're on 1.0.10 (18)".
- [ ] **Delete account** works for both agent (Profile + Settings entry points) and client (Settings "DANGER ZONE"), with the confirm dialog, password screen, exact copy and error states.
- [ ] **Property Overview** is tabbed: **Info / Compliance / Contacts·N / Drive·N / Inspections** (Inspections only for rentals), with the collapsing hero above the tab bar and the app-bar title showing the property name.
- [ ] The **Property Drive** tab works: folder chips (All + folders), document rows with Download/Share, the "Download complete" dialog, and all four states (loading / error+Retry / no files / empty folder).
- [ ] **Contact detail** is tabbed: hero (no name) + **Details / Matches·N / Properties·N**, with the new "No phone, email or ID captured yet…" empty state.
- [ ] The **gallery upload** shows "Preparing photos…", concurrent uploads, "Uploaded X of Y…", the "…didn't upload — tap to retry" failed list with **"Retry all"**, and the new snackbars.
- [ ] **Ellie** has the mic-permission states (off-icon, "needs your microphone", "Tap to enable" / "Open Settings"), and a toggle to demo them; her booking flow is otherwise unchanged.
- [ ] The **Home app bar has no avatar** (menu · wordmark · QR · bell).
- [ ] The **"Send test notification"** button is gone from notification settings.
- [ ] Login has the **fingerprint** button + enable dialog and the **"Create your account"** QR framing; Settings → Security says **"Fingerprint sign-in"**.
- [ ] New/updated **tour chapters** exist for updates, account deletion, fingerprint, the tabbed detail screens, the Drive, and Ellie's mic step.
- [ ] Nothing in §7 was restyled or rewritten.
- [ ] Still a single self-contained file, both themes still work, no external requests.

Apply all of the above to the existing page and give me back the updated single-file artifact.
