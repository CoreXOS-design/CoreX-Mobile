# PROMPT — Build the "CoreX OS Interactive Guided Tour" web app

Copy everything below this line into Claude on the web.

---

You are building a **single-page, self-contained web application** called the **CoreX OS Interactive Guide** — a pixel-faithful, clickable replica of our real Flutter mobile app, wrapped in a guided tour that teaches an estate agent (and their clients) exactly how to use it.

This is a **training and onboarding tool**. Real agents who are struggling with the app will open this page and learn by doing: they walk through a simulated phone, tap real buttons, fill in real forms, and every single element is explained. Nothing talks to a server — it is all simulated with local state and fake data — but it must *look and behave* exactly like the real app.

Take your time and be thorough. Completeness matters far more than brevity. This should be a large, polished, genuinely impressive artifact.

---

## PART 0 — WHAT CoreX OS ACTUALLY IS

CoreX OS is a **real-estate operating system** used by estate agencies in **South Africa** (currency Rand, `R 2 500 000`; timezone Africa/Johannesburg; suburbs like Uvongo, Margate, Ramsgate, Umtentweni; portals Property24 and Private Property). The launch tenant is an agency called **Home Finders Coastal**.

Everything in CoreX connects to **four pillars**: **Property**, **Contact**, **Deal**, **Agent (User)**. Every task, event and notification must link to at least one pillar — an "orphan" item that links to nothing is considered a bug.

The app has **two completely separate experiences behind one login**:

1. **The Agent app** — for estate agents and agency staff. Listings, contacts, matches, calendar, tasks, AI.
2. **The Client portal** — for the agent's buyers, sellers and tenants. A much smaller, softer app: see your agent, see properties matched to you, react to them, watch your own listing's stats, review your agent, manage your privacy consent.

The backend decides which one you get when you log in. **Your tour must cover both**, and must make it obvious to the learner which side they are looking at.

The product philosophy, which the tour should teach explicitly:

> Agents open CoreX to answer one question — **"What do I do now?"** So the app is action-first. The old version was 18 stacked scorecard cards and agents hated the noise. Everything now is something you can *complete, reschedule, skip, or open*.

---

## PART 1 — THE DELIVERABLE

**One single HTML file.** All CSS and JavaScript inline. No external requests of any kind — no CDN scripts, no external stylesheets, no Google Fonts link, no remote images. A strict Content-Security-Policy will block them. Everything must be self-contained:

- **Icons:** hand-write **inline SVG** icons. The real app uses **Tabler Icons** (stroke-based, 2px stroke, round caps, 24×24 viewBox). Reproduce them in that style — do not use emoji as UI icons, and do not use Material icons. Build a small `icon(name)` helper that returns SVG markup so you can reuse them everywhere.
- **Fonts:** the real app uses **Inter** for body text and **Plus Jakarta Sans** for headings/display. You cannot load those. Use a font stack that degrades gracefully and *note in the UI credits* that the real app uses Inter + Plus Jakarta Sans:
  `font-family: 'Plus Jakarta Sans', 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;`
  Headings get tight negative letter-spacing (see the type scale) — that is a big part of the app's character, so keep it.
- **Images:** no remote images. For property photos, generate **CSS gradient placeholders** with a house icon watermark, or tiny inline SVG scenes. Make them look intentional, not broken. Vary the gradients per property so the lists look alive.
- **No build step, no framework required.** Vanilla JS is perfectly fine and probably cleanest. If you prefer, you may use plain JS modules — but it must all live in the one file.

**Layout of the page itself:**

- A **stage** area, centered, containing a **realistic phone frame** (rounded bezel, subtle notch/dynamic-island, ~390×844 viewport — an iPhone-class device). The app renders *inside* that frame at real mobile scale. The frame should have a soft outer glow/shadow so it floats on the page.
- Beside the phone (on desktop), an **explanation panel** — this is where the teaching happens. On narrow screens it stacks below the phone.
- A **top bar** for the page itself with: the CoreX OS wordmark, a **chapter selector**, a **light/dark theme toggle**, an **Agent / Client side switcher**, and a **"Restart tour"** button.
- The page background should be a dark, deep, premium surface (matching the app's dark theme) with a subtle radial backlight — but it must also fully support light mode.

**Both themes are required.** The app itself has a real light theme and a real dark theme, and the tour must let the learner flip between them and see the phone re-theme. Default to **dark** (the app boots dark).

---

## PART 2 — THE DESIGN SYSTEM (use these exact values)

These are lifted directly from the production Flutter codebase. Do not invent alternatives. Reproduce them as CSS custom properties.

### 2.1 Brand / accent colours (per-agency, server-driven — use the defaults)

The app is **white-labelled**: each agency supplies its own colours from the API. The fallback / demo palette is:

| Role | Hex | Meaning |
|---|---|---|
| `accent` (aka `button`) | `#0EA5E9` | **The primary colour.** Every CTA, active nav item, focus ring, icon tint, link. |
| `icon` | `#0EA5E9` | Icon tint (same as accent by default) |
| `money` | `#E8B86D` | **Gold.** Used *only* for monetary values — prices, commission, market value KPIs. It glows. |
| `default` | `#0B2A4A` | Deep navy. Banded surfaces, headers. |
| `sidebar` | `#0EA5E9` | (web sidebar tint — not used on mobile) |

Derived accent steps (compute these, they're used constantly):
```
--accent-soft:   rgba(14,165,233,0.15)   /* icon boxes, chip fills, avatar backgrounds */
--accent-glow:   rgba(14,165,233,0.25)   /* halos, button glow shadows */
--accent-border: rgba(14,165,233,0.40)   /* avatar borders, focus borders */
--money-soft:    rgba(232,184,109,0.15)
--money-glow:    rgba(232,184,109,0.30)  /* text-shadow blur 10px on money values */
```

**Nice touch for the tour:** because the app is white-labelled, add an **"Agency theme" swatch picker** in the top bar letting the learner switch the accent between a few demo agencies (e.g. Sky `#0EA5E9`, Emerald `#10B981`, Crimson `#E11D48`, Violet `#7C3AED`) and watch the entire phone re-brand live. Explain that this is exactly what happens when a new agency is onboarded. The **money gold** and the **purple AI badge** deliberately do *not* change — explain why (money is a semantic role; the AI badge is a system signal, not a brand signal).

### 2.2 Dark palette (default)

```
--page-base:      #0A0F1C   /* page background */
--page-top-tint:  #16243F   /* top of the page radial backlight */
--surface-top:    #1B2440   /* top of every card's gradient */
--surface-base:   #131A2A   /* bottom of every card's gradient */
--text-primary:   #F5F7FB
--text-secondary: #8B9AB5
--text-tertiary:  #5C6B85
--text-muted:     #3D4660
--border:         rgba(255,255,255,0.05)
```

### 2.3 Light palette

```
--page-base:      #E4EAF3   /* deliberately cooler/darker than the cards so white cards pop */
--page-top-tint:  #D3DCEA
--surface-top:    #FFFFFF
--surface-base:   #F6F8FC
--text-primary:   #0B1426
--text-secondary: #4A5878
--text-tertiary:  #7B8AA6
--text-muted:     #B0BACB
--border:         rgba(0,0,0,0.08)
```

### 2.4 Semantic colours

| Role | Hex | Used for |
|---|---|---|
| Success | `#22C55E` | Task done, live listing, "Interested", strong match, active status |
| Success delta (KPI trend) | `#6BD968` | The little ▲ delta under a KPI value |
| Warning / amber | `#F59E0B` | Pending, draft, overdue-soon, "Saved" reaction, fair match, conflicts |
| Danger | `#EF4444` | Overdue, errors, "Not for me", expired, sign-out |
| Destructive | `#DC2626` | Delete confirmations, required-field asterisks |
| Info blue | `#3B82F6` | Informational notifications, good match, deal pillar |
| Neutral | `#6B7280` / `#8890A4` | "Skip", paused, To-Do column, unknown |

### 2.5 Pillar colours (non-negotiable — these are contractual)

| Pillar | Hex |
|---|---|
| Property | `#F97316` (orange) |
| Deal | `#3B82F6` (blue) |
| Contact | `#8B5CF6` (violet) |
| Agent | neutral grey |

Pillar chips are tiny: 9px, uppercase, weight 600, letter-spacing 0.6, radius **3px** (not a pill), background = colour at 15% alpha, text = full colour. If an item has no pillar, the chip **renders nothing at all** — it never fabricates a destination.

### 2.6 The AI badge (deliberately NOT brand-coloured)

Purple, always, regardless of agency:
- Dark theme: background `rgba(59,30,99,0.85)`, foreground `#C9B6F5`
- Light theme: background `#EDE4FB`, foreground `#5B2BB5`
- Content: a small robot icon (11px) + the label **"AI"**, 10px, weight 700, letter-spacing 0.3, radius 6px, hairline border at 35% alpha.

It appears anywhere the machine generated something. **This is a trust signal** — explain that in the tour.

### 2.7 Radius scale

```
--r-card:   14px   /* every card, tile, list row */
--r-button: 12px   /* buttons and inputs */
--r-small:  10px   /* thumbnails, icon boxes inside cards */
--r-large:  20px   /* hero cards, bottom sheets, the floating bottom nav */
--r-pill:   999px  /* chips, status pills */
```

### 2.8 Typography scale (sizes in px, matching the mobile sp values)

| Role | Size | Weight | Letter-spacing |
|---|---|---|---|
| Auth screen H1 | 30 | 800 | −0.6 |
| Login wordmark | 32 | 800 | — |
| Home greeting | 24 | 700 | −0.4 |
| Screen title (Ellie/Tasks header) | 22 | 700 | — |
| App bar / section hero | 20 | 700 | −0.3 |
| Card title, sheet title, empty-state title | 18 | 700 | −0.2 to −0.3 |
| Section header ("Workspace") | 16 | 700 | — |
| List row title | 15 | 700 | −0.2 |
| Primary button label | 15 | 700 | 0.1–0.2 |
| Body / card title | 14 | 600 | −0.1 |
| Subtitle / secondary | 12–12.5 | 500 | — |
| Status chip | 12 | 600 | 0.1 |
| Small chip | 11 | 600 | 0.2 |
| **Eyebrow / uppercase label** | **10** | **700** | **1.4** |
| Bottom nav label | 10 | 700 active / 500 idle | — |
| Pillar tag chip | 9 | 600 | 0.6 |

**The eyebrow is a signature element.** Tiny, uppercase, wide-tracked, usually accent-coloured. Examples used verbatim in the app: `NEXT APPOINTMENT`, `ELLIE · DAILY`, `LAST TRANSCRIPT`, `YOUR AGENT`, `MY LISTINGS`, `YOUR REAL ESTATE OS`. Get these right and the replica will feel authentic.

### 2.9 Elevation, gradients and glow — this is what makes the app look expensive

**Material elevation is zero everywhere.** Depth is faked entirely with gradients and coloured shadows. Reproduce these:

```css
/* Every card: a vertical gradient, not a flat fill */
background: linear-gradient(to bottom, var(--surface-top), var(--surface-base));

/* Page background: a radial "backlight" from the top */
background: radial-gradient(120% 110% at 50% 0%, var(--page-top-tint) 0%, var(--page-base) 55%);

/* Card "seat" shadow (dark theme) */
box-shadow: 0 1px 0 rgba(0,0,0,0.30);
/* Card seat shadow (light theme) */
box-shadow: 0 2px 6px rgba(0,0,0,0.06);

/* Soft card shadow (used on list rows / surface cards) */
box-shadow: 0 8px 24px -4px rgba(0,0,0,0.45);   /* dark */
box-shadow: 0 8px 24px -4px rgba(0,0,0,0.05);   /* light */

/* Primary button glow — the signature look */
box-shadow: 0 12px 28px -10px var(--accent-glow);

/* Hero card glow */
box-shadow: 0 16px 40px -12px rgba(14,165,233,0.22);

/* Floating bottom nav */
box-shadow: 0 10px 24px -8px rgba(0,0,0,0.40);

/* Money value glow */
text-shadow: 0 0 10px var(--money-glow);
```

Every card also carries a **1px top highlight line** — `rgba(255,255,255,0.05)` across the top inside edge — which sells the "lit from above" look. Do this with an inset box-shadow or a pseudo-element.

**Accent cards** (used for "Meet Ellie", "Next appointment", the client's agent card) additionally get:
- a **2px left border** in the accent colour, and
- a **leftward accent halo**: `box-shadow: -10px 0 24px -10px var(--accent-glow);`

### 2.10 Core component recipes

**Primary button** — height 56, radius 12, full width. Vertical gradient from `accent lightened 8%` down to `accent darkened 8%`. White label, 15px/700, letter-spacing 0.2. Optional leading icon at 18px. Accent glow beneath. Disabled = 55% opacity. Loading = a 22px spinner replacing the label.

**Secondary button** — height 52, radius 12, `rgba(255,255,255,0.03)` fill, `1px rgba(255,255,255,0.08)` border, label 14/600.

**Chip** — pill (999), padding 4px 10px, 11px/600, letter-spacing 0.2. Three variants: `accent` (accent-soft bg, accent text), `money` (money-soft bg, gold text), `neutral` (`rgba(255,255,255,0.06)` bg, secondary text).

**Status chip** — pill, background = its colour at **14% alpha**, text = the full colour, 12px/600. Optional 14px leading icon. A `dense` variant at 11px.

**Card** — radius 14, surface gradient, padding 16, top highlight line, seat shadow. In light mode it also takes a `1px rgba(0,0,0,0.08)` border.

**KPI tile** — a card, padding 12/14. Inside: an **uppercase eyebrow label** (10/700/1.4, tertiary), then the **value** (20/700, letter-spacing −0.3), then an optional **delta** (11/600, `#6BD968`). If `money: true`, the value is gold with the money glow.

**Module tile** (the Workspace grid) — a card, roughly square. A 40×40 rounded-12 icon box filled with accent-soft holding a 22px accent icon; the label below at 12/600. An optional 10px **gold dot** at the top-right (with a 2px surface-coloured ring) indicates unread items.

**Icon box** — the recurring motif. A rounded square (radius 10–12), background = a colour at ~14–15% alpha, containing that colour's icon. Sizes: 32 (notification rows), 40 (card headers), 64 (hero cards).

**Input field** — filled, radius 12, no border at rest, `1.5px accent` border on focus, padding 16–18px, min height 48–56. Label sits **above** the input (never beside it). Errors render immediately below in `#EF4444` at 12px. Required fields get a trailing red `*`.

**Bottom sheet** — this app has **no centred modal dialogs** except destructive confirmations. Everything else slides up from the bottom: rounded top corners (radius 20), a small grab handle (36×4, rounded), a title at 18/700, scrollable body, and a pinned full-width action button at the bottom. Reproduce this faithfully — it is one of the most distinctive interaction patterns in the app, and learners need to recognise it.

**Empty state** — centred column: a 72px icon badge (rounded square, accent-tinted, 32px icon), a title at 18/700, a subtitle at 14px, and a CTA button. **Empty states in this app are warm and directive, never blank or apologetic.** Verbatim examples: *"Your day is clear."*, *"You're all caught up."*, *"Tap + to add your first property."*, *"Nothing overdue here. ✓"*

**Bottom navigation** — a **floating pill**, not an edge-to-edge bar. 16px margin left/right, 12px from the bottom, height 64, radius 20, surface gradient, drop shadow. Items are a 22px icon above a 10px label. Active = accent + weight 700; idle = tertiary + weight 500.

**App bar** — 60px tall. Left to right: a hamburger (`menu_2`), the **"CoreX OS" wordmark** (18px/800 — with **"OS" rendered in an accent gradient**), a spacer, a QR icon, a bell (with an 8px accent dot when unread), and a 36×36 rounded-12 **initials avatar** (accent-soft fill, accent border).

### 2.11 Motion

- Tab changes: **260ms** cross-fade plus a subtle scale from 0.985 → 1.0, `ease-out-cubic`. Not a slide.
- Pressable tiles: scale to **0.96** over 140ms.
- Chips / toggles: 180ms.
- Ellie's mic: a **900ms pulsing glow**, scale 1.0 → 1.1, looping.
- Splash: letters of "CoreX" stagger-rise and fade in, an underline sweeps, then the tagline appears. Total ~1.7s.
- Keep all motion subtle and quick. Respect `prefers-reduced-motion` and disable transforms when it's set.

---

## PART 3 — APP STRUCTURE

### Agent bottom navigation (5 tabs)

| Icon (Tabler) | Label | Screen |
|---|---|---|
| `home-2` | **Home** | The launcher / cockpit |
| `calendar-event` | **Today** | Today's schedule + unread notifications |
| `calendar` | **Calendar** | Month / Week / Day / Agenda |
| `sparkles` | **Ellie** | The AI voice assistant *(only shown when the agency has AI enabled)* |
| `user-circle` | **Me** | Profile |

The **Ellie tab is feature-flagged**. Your tour should include an **"AI features: ON / OFF"** switch so learners can see exactly what an agency *without* the AI add-on sees (the tab disappears; the "Meet Ellie" card loses its header and tap-through but keeps its daily quote). This is a real, teachable difference.

### Client bottom navigation (2 tabs)
`home-2` **Home** · `user-circle` **Profile**

### Drawer (agent)
Header: 44px initials avatar, name, email. Then: **Profile**, **Notifications**, **Settings**, divider, **Sign out** (in red `#EF4444`).

### Drawer (client)
**Profile**, **My Listings** *(only if they're a seller)*, **Settings**, **Switch agency** *(only if they belong to more than one)*, a **Dark/Light mode toggle row**, **Sign out**.

---

## PART 4 — EVERY SCREEN, WITH REAL COPY

All strings below are **verbatim from the production app**. Use them exactly. Where I write `{name}` substitute demo data.

### 4.1 Splash
Letters of **"CoreX"** stagger in, an underline sweeps, tagline appears: **"Powering your property universe"** (12px, letter-spacing 2.4, uppercase-ish, muted).

### 4.2 Login
Centred, max-width 380. In order:
- The CoreX monogram (a white rounded square with a glow — approximate the logo mark).
- Wordmark **"CoreX"** + **"OS"** in an accent gradient (32px/800).
- Tagline **"YOUR REAL ESTATE OS"** (11px/700, letter-spacing **2.4**).
- **Email** field (mail icon prefix).
- **Password** field (lock icon prefix, eye toggle on the right).
- Primary button: **"Continue to your workspace"**.
- Secondary button: **"Scan agent QR"** (qrcode icon).
- Footer: **"v1.0.0"**.

**Teach the login cascade** — this is genuinely confusing for users and the tour should demystify it. When you tap Continue, the app tries, in order:
1. Log you in as an **agent**. If that works → Agent Home.
2. If the password was wrong (401) → stop, show **"Incorrect password."**
3. Otherwise, look the email up as a **client**:
   - Not found → **"We couldn't find that email. Ask your agency to add you, or scan your agent's QR code to get started."**
   - Found but never activated → **"This account hasn't been activated yet. Send a code to your email to set a password."** + an **"Activate account"** button → OTP screen (*"We sent a 6-digit code to {email}."*).
   - Active → log in as a client → Client Home.

Other error copy: **"Email or password is incorrect."** · **"Too many attempts. Please try again in a minute."** · **"Could not reach the server. Check your connection."**

In the tour, provide **two one-tap demo logins** ("Sign in as Agent" / "Sign in as Client") plus the option to type anything and watch the cascade play out.

### 4.3 Agent Home — the launcher
Top to bottom:
1. **App bar** (as spec'd in 2.10).
2. **Agency name** — 12px/600, tertiary. Demo: `Home Finders Coastal`.
3. **Greeting** — `Good {morning|afternoon|evening}, {firstName}.` at 24px/700, letter-spacing −0.4. (Cutoffs: before 12:00 morning, before 17:00 afternoon, else evening.) Demo name: **Andre**.
4. **"Meet Ellie" card** — an *accent* card. A 40×40 accent-soft box with the `sparkles` icon, then **"Meet Ellie"** (15/700) and **"Your AI assistant for CoreX"** (12px). An accent divider. Then **the day's quote in italic 14/600**. Then the eyebrow **"ELLIE · DAILY"** in accent. Tapping it opens Ellie.
   The quote rotates daily from a bank of 100 hand-written lines (**not AI-generated** — say so in the explanation, it's a nice honesty detail). Real examples to use:
   - *"The best time to follow up was yesterday. The second best time is right now."*
   - *"Your pipeline is only as warm as your last conversation."*
   - *"Listings come and go; relationships compound."*
   - *"You can't close what you don't follow up on."*
   - *"Done today is worth more than perfect next week."*
   - *"Every 'no' is one conversation closer to your next 'yes'."*
5. **"Next appointment" card** — an *accent* card with three states, all of which the tour should let the learner toggle between:
   - **Loading:** `calendar-time` icon, eyebrow **"NEXT APPOINTMENT"**, text **"Checking your schedule…"**
   - **Clear:** `circle-check` icon, eyebrow, text **"Your schedule is clear for the rest of the day"**
   - **Event:** a 64×64 icon box tinted with the event's colour, the eyebrow, the event title, a subtitle (property address, or location, or contact name), and two chips: the time (`14:30` or **"All day"**) and a *relative* chip — **"Now"** / **"in 45 min"** / **"in 2h"** / **"in 2h 15m"**. Trailing chevron.
6. **Section header "Workspace"** (16/700) with a right-aligned **"All →"** link in accent.
7. **Module grid** — 3 columns, square tiles:
   - `building-skyscraper` → **Properties**
   - `users` → **Contacts**
   - `heart-handshake` → **Core Matches**
   - `target-arrow` → **Portal Leads** *(with the gold unread dot)*
8. **Floating bottom nav.**

There is **no floating action button on Home** — deliberately. Explain: Home is for orienting, not creating.

### 4.4 Today
A 56px header row: back arrow + **"Today"** (18/700). Pull-to-refresh. (The real app polls every 60 seconds and refreshes when you return to it — mention this.)

**Block A — "Today's Schedule"**
Rows are cards with: a 4px × 44px vertical colour bar (the event's colour), a fixed 58px time column (`09:30` or **"All day"**), the title (max 2 lines), an optional location line with a pin icon, and an optional attendee count with a people icon.
Empty: **"No events today."**
Tapping a row opens a **bottom sheet** with: a colour dot + title (18/700), then icon+label rows for the full time range, the location, the event class, `"{n} attendees"`, and the description. Two actions at the bottom: an outlined **"Dismiss"** (× icon) and a filled **"Complete"** (✓ icon).

**Block B — "Unread Notifications"**
A section header with a right-side **"Mark all read"** text button (only when there are unread items).
Rows: a 32×32 rounded icon box tinted by severity, a title (2 lines, 13/600), a body (2 lines, 12px), and a relative timestamp (**"just now"** / **"5m ago"** / **"3h ago"** / **"2d ago"**).
Severity colours: overdue `#EF4444`, warning `#F59E0B`, info `#3B82F6`.
Empty: **"You're all caught up."**

### 4.5 Calendar
Sticky two-row header:
- Row 1: **month + year** (e.g. "July 2026", 20/700), and a mail icon (tooltip **"Invitations"**) with an **amber dot** when RSVPs are pending.
- Row 2: `‹` round button · a **"Today"** pill · `›` round button · spacer · a segmented view toggle **M | W | D | A**.

Views (default is **Day**):
- **Month** — `M T W T F S S` header, a 7×6 grid. Today = a filled accent circle. Selected = a navy tile. Up to 3 event colour-dots under each day. Below the grid, a panel for the selected day: `Monday, 13 July` + `{n} events`, or **"No events"**; if nothing is selected: **"Tap a day to see events"**.
- **Week** — a Monday-anchored strip of 7 day-pills (letter, number, a presence dot) + the focused day's event list. Swiping shifts ±7 days.
- **Day** — `‹ 13 July 2026 ›` + the event list. Swiping shifts ±1 day.
- **Agenda** — a forward-looking 2-month window grouped by date, headers like `Monday · 13 July` (today gets a **"Today · "** prefix and an accent dot). Empty: **"No events this month"**.

Event cards: a 3×44 **glowing** colour stripe, the time in accent (12/700), a type chip, and the title (14/600).

**FAB:** an accent `+` → the full **Event form sheet**.

### 4.6 Tasks (kanban)
Header: **"Tasks"** (22px) + subtitle **"{n} open · {n} overdue"** (the whole subtitle turns red when overdue > 0). An overflow `⋮` menu with **"Archive all Done"** (→ snackbar *"{n} task(s) archived"*).
A segmented control: **Active** | **Archived**.

**Active** = three vertically stacked columns, each with a colour dot, a name and a count:
- **To Do** `#6B7280`
- **In Progress** `#0EA5E9`
- **Done** `#22C55E`

Cards are **draggable between columns** (long-press to pick up on mobile). Make this actually work with mouse drag in your replica — it's one of the most satisfying things to demo. An empty column reads **"Nothing here."**; while dragging over it, **"Drop to move here"**. Long-pressing a card also offers a `Move "{title}"` sheet as an accessible alternative.

Task cards support **swipe gestures** — swipe right = **Complete** (green background), swipe left = **"Didn't happen"** (grey). Overdue cards get a red border at 45% alpha. Implement the swipe with pointer events so it works on desktop too, and *explain the gesture* with an animated hand/arrow hint the first time.

**Archived** = rows grouped under date headers (`Jan 5, 2026`), each with a **"Restore"** button. Empty: **"No archived tasks."**

**FAB:** `+` → the **Quick Add** sheet.

### 4.7 Quick Add sheet (Tasks + Events in one)
Title **"Quick Add"**. A segmented toggle: **Task** | **Event**.

Shared: a title field (autofocus), a **Priority** pill row — **Low** `#6B7280` / **Normal** `#0EA5E9` / **High** `#F59E0B` / **Critical** `#EF4444` — a *"Description (optional)"* textarea, and a **"Remind me"** switch (default ON).

**Task mode adds:** a **Type** dropdown (`Custom`, `Follow Up`, `Document Upload`, `Compliance`, `Review`, `Deal Action`) and a **Due Date** picker (no past dates). Button: **"Add Task"**.

**Event mode adds:** a **Date** picker, **Start time** and **End time** pickers (inline error: *"End time must be after start time"*), a **Type** dropdown (`Manual`, `Deal`, `Lease`, `Compliance`, `Prospecting`), an **"All day"** switch, and — importantly — a **non-blocking amber conflict banner**: **"Overlaps 2 events"**, listing up to three as `{title} · 09:00–10:00`, then `+ 1 more`. Button: **"Add Event"**.

Missing-field warning (amber snackbar): *"Please add a task title, a date and a start time."*

**Make the conflict banner a tour highlight.** It warns but never blocks — teach that the app trusts the agent's judgement.

### 4.8 Properties — the list
App bar with a search field **"Search by address"**, a filter icon carrying a **badge with the active-filter count**, and an **agent filter bar** (a segmented **My Properties | All Properties** plus a **"Filter by agent"** picker).

**Property card:** a 76×76 rounded thumbnail on the left; on the right a **"Co-listing"** badge (only when the property belongs to another agent), the address in bold (max 2 lines), and a stat row with icons — bed `4`, bath `2`, garage `2`. Far right: a **status chip** — `active` green, `draft` amber, anything else grey.

**Filter sheet** (bottom sheet titled **"Filters"** with a **"Clear"** button): a **Suburb** chip group, a **Price** Min/Max pair, a **Listing Type** chip group, a **Status** chip group, and a full-width **"Apply"** button. Above the list when filters are on: **"7 of 24 match"** + a **"Clear filters"** button.

Empties: **"No properties yet"** / *"Tap + to add your first property"*. No match: **"No matches"** / *"Try a different search or clear the filters."* + **"Clear all"**.

**FAB:** a glowing accent `+`.

> **Teach this rule:** tapping a **draft** property opens the **editor**; tapping a **live** one opens the **Overview**. That surprises people.

### 4.9 ★ PROPERTY UPLOAD — the 4-step wizard (make this the centrepiece of the tour)

App bar: **"New Property"**, a back arrow (tooltip *"Previous step"*) and a `×` (tooltip *"Close"*). Below it, a **4-segment progress bar** that fills in accent as you advance. The steps do **not** allow swiping — you move only with the buttons.

**⚠️ The single most important thing to teach here:** Steps 3 and 4 need a real property ID on the server, so **the property is actually created when you press the button at the end of Step 2**. That's why the button says **"Create & Continue"** the first time and **"Next: Spaces"** every time after. Learners are constantly confused by this. Call it out with a prominent callout in the explanation panel.

**STEP 1 — Address**
| Field | Type | Required |
|---|---|---|
| `Street Number` | text | no |
| `Street Name` | text | no |
| `Complex Name (optional)` | text | no |
| `Unit Number (optional)` | text | no |
| `Province *` | cascading picker | **yes** |
| `City *` | cascading picker | **yes** |
| `Suburb *` | cascading picker | **yes** |
| `District (optional)` | text | no |
| `Region (optional)` | text | no |

The **Province → City → Suburb cascade** is a real teaching moment. Each opens a **searchable bottom sheet** (`Select Province` / `Select City` / `Select Suburb`) with an autofocused search box (placeholder `Search…`), a **"No matches"** empty state, and an error state *"Could not load list — try again"* + **Retry**. City is disabled until a Province is chosen (hint: *"Select a province first"*); Suburb is disabled until a City is chosen (*"Select a city first"*). Changing a parent **clears all its children**. Simulate this fully with South African data (KwaZulu-Natal → Margate → Uvongo, Western Cape → Cape Town → Sea Point, Gauteng → Sandton → Bryanston, etc.).

Button: **"Next"**.

**STEP 2 — Details**
| Field | Type | Options / Hint | Required |
|---|---|---|---|
| `Listing Type *` | segmented chips | **For Sale** / **For Rental** | **yes** |
| `Title *` | text | hint: *"e.g. Stunning 4 Bed House in Uvongo"* | **yes** |
| `Property Type *` | dropdown | House, Apartment, Townhouse, Vacant Land, Farm, Commercial | **yes** |
| `Property Status *` | dropdown | Draft, Active, Under Offer, Sold, Withdrawn | **yes** |
| `Price (R) *` | number | hint: *"e.g. 2500000"* (non-digits stripped as you type) | **yes** |
| `Category` | dropdown | Residential, Commercial, Industrial, Agricultural | no |
| `Mandate Type` | dropdown | Sole, Open, Joint, Exclusive | no |
| `Excerpt (max 500 chars)` | textarea (2 rows, counter) | | no |
| `Description` | textarea (4 rows) | | no |

**Rental-only block** (appears when Listing Type = For Rental; header **"Rental Details"**; the values are wiped if you switch back to Sale — demo that):
`Rental Amount (R / month)`, `Deposit Amount (R)`, `Lease Start Date`, `Lease End Date` (read-only fields that open a date picker, hint `YYYY-MM-DD`).

**Validation — the "Missing Required Fields" dialog.** This is one of the few real centred dialogs in the app. Pressing **"Create & Continue"** with gaps produces:
> **Missing Required Fields**
> *Please fill in the following before creating the property:*
> · Title
> · Property Type
> · Price
>
> **[ Close ]  [ Take me there ]**

**"Take me there"** jumps to the right step and scrolls to the first missing field. Implement it — it's a lovely detail and worth showing off.

Button: **"Create & Continue"** → then **"Next: Spaces"**.

**STEP 3 — Spaces & Features**
Heading: **"Spaces & Features"**.
- An **"Add a space"** dropdown listing space types you haven't added yet, each with an icon (Bedroom, Bathroom, Kitchen, Garage, Parking, Pool, Garden, Lounge, Dining Room, Study, Flatlet). Picking one adds it with a count of 1 and **immediately opens the feature picker**.
- Empty: **"No spaces added yet."**
- Each space is a card: icon, name, **"{n} feature(s)"** subtitle, `−` / count / `+` steppers, and an `×` remove button. **Bathrooms step by 0.5** (2.5 bathrooms is a real thing) — everything else steps by 1. Setting the count to 0 removes the space. Tapping the card body opens the feature picker.
- **Feature picker sheet:** the space name + `×`. When the count is ≥ 2, two tabs appear — **All Units** | **Per Unit** — where "Per Unit" shows a horizontal chip row (`Bedroom 1`, `Bedroom 2`, `Bedroom 3`) so you can give each individual room its own features. Body = feature groups with a category header and a row of toggle chips (e.g. Bedroom → *En-suite, Built-in cupboards, Balcony, Air conditioning, Ceiling fan*). Bottom button: **"Done"**.
- Then the **AI suggestions panel** (see Part 5 — this is where it lives).
- Then **"Property Features"** — accordions per category (Security, Outdoor, Interior, Views, Sustainability) each showing **"{n} selected"**, expanding into a wrap of toggle chips (*Alarm system, Electric fence, Beam sensors, Sea view, Solar panels, Borehole, Braai area, Fibre ready…*).

Button: **"Next: Gallery"**.

**STEP 4 — Gallery**
Heading **"Gallery"** + an **"Upload"** text button.
Empty: *"No photos yet. Add spaces first to unlock tags, or tap Upload to add untagged photos."*

**The key concept to teach:** photo **tags are derived from the spaces you created**. Add a Bedroom in Step 3 and a "Bedroom" photo tag appears here. Photos are grouped by tag: each group shows `{tag} · {count}` and an **"Add Photo"** button over a horizontal strip of 120×90 thumbnails, or *"No photos in this group yet."*

**Upload sheet** (85%-height draggable sheet, **"Upload Photos"** + `×`):
- **"Tag this photo"** — tag chips showing `{tag} · {n}`, plus a **"No tag"** chip. If there are no spaces: *"This property has no spaces yet — photos will upload to Unsorted."*
- Three equal-width source buttons: **"Multi Capture"** (an in-app burst camera), **"Native"** (the OS camera, which loops so you can shoot many), **"Gallery"** (multi-select).
- The queue: **"{n} selected"** (or **"Uploading 3 of 8…"**), a strip of 90×90 thumbnails each with an `×` remove badge.
- Failures: **"Failed (2) — tap to retry"** with per-file errors and a **Retry** button.
- Bottom button: **"Upload 5 photo(s)"**. Success snackbar: *"5 photo(s) uploaded"*.

Simulate the whole upload — a progress bar counting up, one file "failing", the learner retrying it successfully. That builds real confidence.

Final button: **"Save Property"**.

### 4.10 Property Overview (the detail view)
App bar **"Overview"** + an edit pencil. Sections in order — build them all:
1. **Hero** — a 220px cover image darkened 35%, with a status pill top-left, a **"{n} days on market"** chip top-right, the title, `{suburb}, {city}`, and the price large and gold.
2. **At a glance** — a dot-separated strip: `4 Beds · 2 Baths · 2 Garages · 240 m² floor · 800 m² erf · 12 Photos · Sole mandate`.
3. **Compliance card** — *the most important card in the app for a new agent.* A status badge: **LIVE** (green ✓) / **READY** (blue) / **BLOCKED** (orange). Then a checklist of the four gates, in this exact order, each with a green check or an orange error icon, a label, a detail line, and an inline action button:
   - **Authority to market** → *Send mandate for signature*
   - **Seller FICA** → *Start seller FICA*
   - **Photos** → a chip reading **"8/12 photos"**
   - **Listing details** → *Resolve*

   Then an orange **"Blocking go-live"** panel with the bulleted reasons. Then a **Sellers** list, each row carrying a FICA badge (**"FICA approved"** green / **"FICA pending"** orange). Then **"Next actions"**. Then the primary button **"Send Authority to Market"**, disabled until everything is green, with the helper line *"Resolve the items above to enable sending to market."* Success: *"Property sent to market."* Once live, a green banner: **"Live · Sent to market on 3 Jul 2026"**.

   > **Teach this hard.** It is the #1 thing agents get stuck on: *"why can't I publish my listing?"* The answer is always one of those four gates. Give this its own tour chapter.
4. **Rental Inspections** (rentals only) — *"In, out & custom inspection galleries"*.
5. **Contacts** — linked contacts with role badges. Empty: *"No contacts linked yet."* Unlink dialog: **"Unlink contact"** / *"Remove {name} from this property? This only removes the link — the contact is kept."*
6. **Description** — truncated at 220 characters with **"Read more"** / **"Show less"**.
7. **"Open Live Preview"** button.
8. **"Where this listing is published"** — a card per portal (Website, HFC Premium, Private Property, Property24) showing either a green **"Live"** pill + *"View on Property24"*, or a greyed **"Not published"** with a lock icon, plus `Ref P24-123456`. Empty: **"Not yet published to any portal"** / *"This listing isn't live anywhere yet — open Syndication on the desktop to publish."*
9. **Listing Agent(s)** — role labels **"Lead agent"** / **"Co-agent"**, with tappable phone and email.
10. **Owner** card.
11. **Virtual Tour** card.
12. **Key dates** — a 2×2 grid: **Listed**, **Expires**, **Loaded** (relative, e.g. `3d ago`), **Modified**. Missing values render as **"—"**, never `null`.

### 4.11 Contacts — the list
App bar **"Contacts"**, a search field **"Search contacts…"** (300ms debounce), an agent filter bar (**My Contacts | All Contacts**), and a glowing `+` FAB.

**Contact row:** a circular initials avatar, the full name, the phone as the subtitle, and on the right a **contact-type chip** plus a green **WhatsApp chip showing a count** (only when > 0).

Empties: **"No contacts yet"** / *"Tap + to add your first contact."* Searching: **"No matches"** / *"No contacts match "{query}"."* Error: **"Could not load contacts"** + **Retry**.

### 4.12 ★ CONTACT UPLOAD — "New Contact"
A **single-page form** (no wizard — contrast this with Properties and explain *why*: a contact is one small record; a property needs a server ID before it can hold photos).

App bar: **"New Contact"**.

| Field | Type | Required |
|---|---|---|
| `First Name *` | text | **yes** |
| `Last Name *` | text | **yes** |
| `Phone *` | tel | **yes** |
| `Email` | email | no |
| `ID Number` | text | no |
| `Contact Type` | dropdown — `— None —` plus the agency's own list (Buyer, Seller, Tenant, Landlord, Investor, Referral) | no |
| `Notes` | textarea (3 rows) | no |

Button: **"Create Contact"**.

**Duplicate detection** — demo this deliberately (have the learner enter a phone number that already exists):
> **This contact already exists**
> *A contact with this phone or ID is already on file.*
> **[ Close ]  [ Open contact ]**

After a successful create, the app **immediately opens the new contact's detail screen** — mention that, it surprises people.

> **Worth stating plainly in the tour, because agents ask constantly:** there is **no CSV/bulk import** and **no free-text tags** and **no "source" field** on contacts in the mobile app. What you get is the **Contact Type** dropdown (agency-defined) and, separately, a **Role** *per linked property* (seller/landlord/buyer/tenant). Don't let learners hunt for features that aren't there.

### 4.13 Contact detail
App bar = the contact's name + an edit pencil.
- **Header card:** initials avatar, full name, contact-type pill, then rows for phone, email and ID number, plus a green **"WhatsApp · 7"** pill with *"last 2 Jul 2026"*.
- Primary button: **"WhatsApp"** (shows *"Opening…"*). **Every WhatsApp tap is logged server-side and increments that counter** — teach this, it's how the agency tracks outreach.
- Secondary row: **"+ Match"** | **"+ Listing"**.
- **Compliance** tile → *"Consent · Documents · FICA"*.
- **Matches** section. Empty: **"No matches yet"** / *"Tap + Match to capture buyer or tenant criteria."* Rows show a status pill and `For Sale · Uvongo · R1 200 000 – R2 500 000`.
- **Linked Properties** section. Empty: **"No linked listings"** / *"Tap + Listing to create a property tied to this contact."*

Tapping **"+ Listing"** first opens a **"Pick contact role"** sheet — **Seller** / **Landlord** / **Buyer** / **Tenant** — *then* launches the property wizard with that contact pre-linked. Nice flow; show it.

### 4.14 Contact Compliance (three tabs: Consent | Documents | FICA)
- **Consent** — a switch per consent type; subtitle *"Given 2 Jul 2026 · Electronic"* or *"Not given"*. Switching **on** opens a sheet **"How was consent given?"** with radio options **Electronic / Verbal / Written / Signed document** and a **"Confirm consent"** button. Switching **off** opens a dialog *Revoke "{label}"?* with an optional **Reason** textarea → **Cancel** / **Revoke** (red). A collapsible **History** section logs every change. Empty: **"No history"** / *"Consent changes will be logged here."*
- **Documents (Drive)** — an extended **"Upload"** FAB. Source sheet: *Choose from library* / *Take a photo*. **20 MB limit** (*"File exceeds the 20MB limit."*). Then a metadata sheet (`Upload {filename}`) with a **Document type** dropdown and a **Link to property** dropdown, then **Upload** (*"Document uploaded."*). Docs are grouped by property address with an **"Unlinked"** group. Each row: icon, filename, a type pill, `1.2 MB · by Andre Roets · 2 Jul 2026`, and **Download** / **Re-tag** / **Delete** (red; *"Delete document?"* / *"{name}" will be permanently removed."*). Empty: **"No documents"** / *"Tap Upload to add the first document."*
- **FICA** — read-only. A big status banner (complete green / expiring amber / else red), **Submissions** cards showing `Risk: Low`, `Verified by: …`, `Verified: …`, `Expires: …`, `PDF: available`, and a **Legacy documents** section. Empty: **"No submissions"** / *"No FICA submissions on file for this contact."*

*(POPIA is South Africa's privacy law — briefly explain to the learner why consent and FICA exist at all. It's a legal requirement, not bureaucracy for its own sake.)*

### 4.15 Core Matches (agent side)
A saved buyer/tenant requirement that the system scores properties against. **This is a deterministic scoring engine, not AI** — say so explicitly, because the name misleads people.

**New Match** form: `Listing Type *` (**For Sale** / **For Rental** chips), `Name`, `Category`, `Property Type`, `Price Min` / `Price Max` (side by side), `Beds Min` / `Baths Min` (side by side), `Suburbs` (a **multi-select** suburb picker), `Notes`. Button: **"Create Match"**. The edit variant adds a **"Must-have Features"** chip input and a **"Save Changes"** button.

**Match statuses:** `active` (blue) · `paused` (grey) · `fulfilled` (green) · `expired` (red).
**Result tiers** (section headers on the results list): **Strong matches** ≥ 80 (green) · **Good matches** 65–79 (blue) · **Fair matches** 50–64 (amber). Each result carries a **"{score}%"** badge.
Empty results: *"Nothing scored 50% or higher for this match. Adjust the filters to widen the search."*

**Client reactions** flow back to the agent here: **Interested** (green) / **Saved** (amber) / **Not for me** (red), with tallies.

**The WhatsApp share** — the richest comms feature in the app, and worth a tour stop. A full-width **"Send via WhatsApp"** button opens a sheet: **"Send to {Contact Name}"**, the phone number (or a red **"No phone on contact"** + *"Add a phone number to this contact first."*), an **editable pre-written message** (a server-rendered template listing the matched properties), a **"Reset to template"** link, and **"Send via WhatsApp"**. Sending logs it server-side and *then* opens WhatsApp: snackbar *"Logged WhatsApp send. whatsapp_count = 8"*.

Also a **"Client Page"** action which opens the shareable web page for this match.

### 4.16 Portal Leads
Header **"Portal Leads"** + an accent **"{n} unread"** pill. A **Sunday-anchored week strip** with per-day totals and unread dots (you cannot navigate past the current week). Tapping a day lists that day's leads. Source chips: **P24** (red `#E11D2A`) and **PP** (blue `#2563EB`). Lead detail shows the enquiry, a tappable phone (with a **"WhatsApp"** tag when the number is WhatsApp-capable) and email. Empty: **"No leads on this day."**

Explain what this is: **enquiries that came in from the public property portals**, landing straight in the agent's pocket. Speed of response is everything — that's why it has an unread dot on the Home tile.

### 4.17 Notifications
App bar **"Notifications"**, a **"Mark all read"** action, and a settings icon.
Rows are **grouped by pillar**, in this fixed order, with these exact headers: **Properties**, **Contacts**, **Deals**, **My activity**, **Other**. Inside each group, sorted overdue → warning → info, then newest first.
Each row: a severity colour bar with a glow, the title (bold when unread), a 2-line body, and a relative time. Unread rows get a coloured border and an 8px dot.
Empty: **"You're all caught up"** / *"Nothing new to look at right now."*
Error: **"Couldn't load notifications"** / *"Check your connection and try again."* + **Retry**.

> **A deliberate design rule worth teaching:** there is **no "9+" badge** anywhere in this app, and **no auto-popup on launch**. The old version interrupted agents on open and they hated it. Actionable things surface as rows you can act on; pure noise gets no badge at all.

### 4.18 Settings / Profile
**Profile:** a 96px rounded initials avatar with a brand glow, name (24/800), email, a role chip, an **"Account"** info card (Name / Email / Role), and a full-width outlined **"Sign out"** in red.
**Settings:** **Appearance** → a "Dark mode" switch. **Notifications** → "Quiet hours" and "Event reminder" (lead time). **Security** → a "Biometric sign-in" switch. **About** → "Version 1.0.0".

### 4.19 My QR Code
App bar **"My QR Code"**. A white QR card (280px — draw a plausible QR as an SVG grid), the title **"Your Client QR"**, and the copy:
> *"Hand this to prospects. When they scan it in the CoreX app, they sign up directly as your client."*

Then `Andre Roets · Home Finders Coastal`, and **"Share"** / **"Save Image"** buttons.

This is the growth loop of the whole product — give it a proper tour stop.

---

## PART 5 — THE AI FEATURES (a dedicated tour chapter, with honest explanations)

All AI is gated behind two server flags: **`aiVoice`** and **`aiImageRecognition`**. Together they're the agency's *"Advanced AI Features"* add-on. If both are off, the Ellie tab vanishes entirely.

### 5.1 Ellie — the push-to-talk voice assistant
A dedicated tab (`sparkles`, label **"Ellie"**).

**Screen, top to bottom:**
- Header: **"Ellie"** (22/700) + the purple **AI badge**.
- Status line (15px, secondary): idle → **"Hold the mic and tell Ellie what to do"** · recording → **"Listening…"** · sending → **"Thinking…"**
- Hint (12px, italic, tertiary): **`Try: "Book a viewing with John at 12 Beach Road tomorrow at 11am"`**
- A **140×140 circular gradient mic button** — accent gradient at rest, switching to a **red gradient (`#E53935` → `#B71C1C`)** while recording, with a **900ms pulsing glow**.
- Caption under it: **"Hold to talk"** / **"Release to send"** / **"Sending to Ellie…"**
- A **"LAST TRANSCRIPT"** card (uppercase eyebrow) holding the last thing you said, in italic quotes.

**Simulate the whole loop in the tour.** Press and *hold* the mic (mouse-down / touch-start), watch it turn red and pulse, release, watch "Thinking…", then a **result bottom sheet** appears:
- The AI badge + **"Ellie"**
- Your transcript, in italic quotes
- A summary tile with an icon and: **`Scheduled: Viewing with John Meyer — Tue 14 Jul 11:00`**
- Buttons: an outlined **"Undo"** and a filled **"Open event"**

Then let them tap **"Open event"** and land on the Calendar with the new event actually there. That single interaction sells the entire product — make it feel great.

**Also demo the failure paths**, because they're real:
- Released too quickly (< 0.4s) → *"Hold to talk — press and hold the mic"*
- Nothing intelligible → *"Didn't catch that — hold the mic and speak after the tone"* and the sheet reads **"I didn't catch that."**
- Feature off → a `microphone-off` icon and *"Ellie voice isn't available on this account yet."*

**Explain honestly what Ellie is and isn't.** She is a *voice-to-action* assistant: you speak, she transcribes, she extracts an intent, and she creates a calendar event — and you can undo it in one tap. She is **not** a chatbot; there's no conversation thread. Setting that expectation up front prevents a lot of disappointment.

### 5.2 AI photo analysis — "AI suggestions from your photos"
This lives **inside the property wizard, on Step 3 (Spaces & Features)**, between the spaces list and the manual Property Features checklist. It is invisible if image AI is off.

**What actually happens:** when you upload photos in Step 4, each one is queued for analysis. The panel polls for results (every 2 seconds, giving up after 90 seconds) and then proposes features it can *see* in the photos.

**Panel layout:**
- Header: the **AI badge** + **"AI suggestions from your photos"** (14/700) + a small spinner while it works.
- Sub-line: while polling → **"Analysing photos… (3/8 done)"** · timed out → *"Still analysing — features can be reviewed on the property later."* · ready → **"Tap a chip to inspect or untick."**
- **"Features"** — a wrap of **suggestion chips**. Each chip carries: a check-circle (filled when accepted), the feature name, a small **AI badge**, **confidence pips** (4 dots, filled proportional to confidence), and an **eye icon**. Tap = accept/reject. Tap the eye = open a sheet showing **the actual source photos** the feature was detected in, each with its own confidence.
- **Anything scoring ≥ 50% confidence is pre-ticked.**
- **"Spaces (advisory)"** — read-only chips like `Bedroom · 3`. The AI *suggests* room counts but never overwrites what you typed.
- A filled **"Apply AI features"** button (sparkles icon). Success: *"AI features applied."*

Demo it properly: "analysing 6 photos…", then chips appear — *Swimming pool* (4/4 pips), *Sea view* (4/4), *Built-in braai* (3/4), *Solar panels* (2/4), *Air conditioning* (1/4, unticked by default) — the learner unticks one, opens the eye to inspect the source photos, and applies.

**Teach the trust model, and be emphatic about it:** the AI **never silently changes your listing**. It proposes; you confirm. Confidence is always visible; the source photos are always inspectable; and the room counts are advisory only. That's why the badge is there and why every suggestion is a toggle. Agents are accountable for what they publish — the app is built to keep them in control.

### 5.3 What is *not* AI (clear this up — the names mislead)
Add a small "Myth-busting" panel in the AI chapter:
- **"Core Matches"** — a deterministic scoring engine (price, beds, suburb, features). Not machine learning.
- **"Agent Insights"** on the client seller dashboard — written/authored server-side, not generated.
- **"Market Presentation"** marked *"Generated 3 Jul 2026"* — a document render, not generative AI.
- **Ellie's daily quote** — one of 100 hand-written lines, chosen by the calendar date. Not a model.

Being straight about this builds trust, and it stops agents expecting behaviour that doesn't exist.

---

## PART 6 — THE CLIENT PORTAL (its own tour track)

The learner must be able to **switch sides** and walk the client experience — both so agents can explain it to their clients, and so clients themselves can be handed this tour.

Make the client side *feel* different: same tokens, but calmer, roomier, fewer controls. Two tabs, no FAB, no kanban, no compliance gates.

### 6.1 How a client even gets an account (three routes — explain all three)
1. **The agent adds them**, then they log in with their email and activate via a 6-digit OTP.
2. **They scan the agent's QR code** and sign up directly as that agent's client (First name, Surname, Cell phone, Email, Password, Confirm password → **"Create account"**, subtitle *"Sign up with your agent to start tracking your matches."*).
3. They already exist and just sign in.

If they belong to more than one agency, they hit an **agency picker** with three persistence options — teach these, they're genuinely useful:
- **"Ask me each time"** — *Choose an agency every time you open the app.*
- **"Set as my favourite"** — *Pre-selected next time — you can still switch.*
- **"Only use this agency"** — *Skip this picker from now on.*

### 6.2 Client Home
- Agency name, then **"Good afternoon, Sarah."**
- **"YOUR AGENT" card** (eyebrow) — the agent's photo/initials, name, title, and a one-tap action row: **Call** · **WhatsApp** · **Email**. No agent yet → *"Your Home Finders Coastal agent will appear here"*.
- **"MY LISTINGS" card** (sellers only) — a thumbnail, the title, and a stats line **"3 viewings · 21 days listed"** or **"View live marketing stats"**.
- **"Matched for you"** — a horizontal carousel with a **"See all"** link. Cards (190×232) show a **"92% match"** black pill overlay, the price, the address, the suburb, and bed/bath icons.
- **"Explore"** — a 3-tile grid: **Core Matches** (`heart-handshake`), **Review Agent** (`star`), **Privacy & Consent** (`shield-lock`).

### 6.3 Client property view + reactions
An image carousel with dot indicators, the title/address, the price, spec chips, a description with **"Read more"**, a **"Features"** chip list, an agent card (**"Call Andre"** / **"WhatsApp"** / **"Email"**), and **"View on web"**.

A pinned bottom **reaction bar** with three buttons: **Interested** (heart) · **Saved** (star) · **Not for me** (✕).

Choosing **"Not for me"** opens a sheet: title **"Not for me"**, a textarea labelled **"Tell us why (optional)"**, hint *"e.g. Too far from school"*, max 500 chars, **Cancel** / **Send**.

**Explain the loop, because it's the point of the whole feature:** that reaction lands on the agent's Core Match screen in real time. The "why" the client types is the single most valuable thing an agent can get — it's how the search gets sharper. Encourage clients to actually write it.

### 6.4 Client Core Matches (their own saved search)
Title **"Core Matches"**, FAB **"New search"**. Empty: **"Tell us what you're looking for"** / *"Set up your search and we'll match you with properties as soon as they hit our books."* + **"Set up my search"**.
Cards show a title (`Buy search` / `Rental search`), a price chip (`R 1.2m–2.5m`), `3+ beds`, the suburb, and a reaction tally (❤ / ★ / ✕ counts).
Clients can edit their own criteria: price, beds, suburb (the same province → city → suburb cascade), notes (**"Anything else we should know?"**) and a name (hint: **"Beach house under R2.5m"**).

### 6.5 Seller dashboard — "Listing insights"
This is the client-side showpiece. Sections:
1. **Header card** — a 16:9 hero, title, address, agency logo, the **price in gold**, and a spec row.
2. **Performance** — a 2×2 grid of KPI tiles: **Viewings**, **Days Listed**, **Market Value** *(gold)*, **Area Average** *(gold)*.
3. **"Agent Insights"** (bulb icon) — cards with a title and reasoning.
4. **"Viewing Feedback"** — mini-stats: **Viewings logged**, **Feedback notes**.
5. **"Marketing Activity"** — a dotted timeline with dates.
6. **"Similar Properties"** — comparables with `{n} days on market` and a price.
7. **"Market Presentation"** — a file row, *"Generated 3 Jul 2026"*.
8. **"Listing Status"** — chips: **Active** / **Unpublished**, **Mandate active** / **Review needed**.
9. **Agent footer** — an accent card: **"Questions? Contact your agent"** with **Call** / **Email**.
10. **"Last updated 2h ago"**.

Empty: **"No listings yet"** / *"When your agent links you to a property as the seller, its live marketing stats will appear here."*

### 6.6 Testimonials — "Review your agent"
Empty: **"Had a great experience?"** / *"Leave a testimonial about your agent. They review every one, and can choose to feature it on their website."* + **"Leave a testimonial"**.
Form: a 5-star rating, a body (hint *"Share how your agent helped you…"*), a display name (hint *"Bob B."*), and **"Send to my agent"** → *"Thanks — sent to your agent"*.
Once the agent publishes it, the card gains a **"Live on website"** chip (globe icon).

### 6.7 Privacy & Consent (POPIA)
Sections: **Communication channels**, **Marketing**, **Your data**. Each row is **tri-state: Yes / No / Clear**. Channel rows carry the warning: *"Tapping No stops the agency contacting you this way, right away."*
No linked contact record → *"We couldn't find your contact record with this agency yet. Your agent can connect you, then you can manage consent here."*

Explain that this is the *same ledger* the agent sees on their side — one source of truth, and the client can revoke at any time. That's the law, and it's also good manners.

---

## PART 7 — THE TOUR ENGINE (this is the actual product)

The replica is the canvas; **the tour is the point**. Build a proper guided-tour system.

### 7.1 Chapters
A left rail (or a top dropdown on mobile) listing chapters, each with a progress tick as it's completed. Suggested structure:

**Getting started**
1. Welcome & what CoreX is (the four pillars, the "what do I do now?" philosophy)
2. Signing in (and the agent-vs-client cascade)
3. The Home screen — your launcher
4. Reading the interface (the design language: eyebrows, chips, pillar colours, accent cards, gold money, the AI badge)

**Daily rhythm**
5. Today — your schedule and your unread items
6. Calendar — four views, and booking an appointment
7. Tasks — the kanban board, swipes and drag-and-drop
8. Quick Add — a task or an event in 15 seconds

**Core work**
9. ★ **Uploading a property** — the full 4-step wizard, end to end
10. Spaces, features and photo tags — how they connect
11. ★ **The compliance gates** — why your listing won't go live
12. The Property Overview and portal syndication
13. ★ **Adding a contact** — and the duplicate check
14. Contact compliance — consent, documents, FICA
15. Core Matches — capturing what a buyer wants, and sharing on WhatsApp
16. Portal Leads — enquiries from Property24 and Private Property

**The AI**
17. ★ **Meet Ellie** — book a viewing with your voice
18. ★ **AI photo analysis** — features detected from your pictures
19. What is *not* AI (myth-busting)

**Your clients**
20. Your QR code — how clients sign themselves up
21. ★ **The client portal** — a full walkthrough on the client side
22. Reactions and feedback — the loop back to you
23. The seller dashboard
24. Privacy, consent and POPIA

**Finishing**
25. Settings, notifications and quiet hours
26. Recap + a printable/expandable cheat-sheet of every gesture, colour and icon

Mark the ★ chapters as **"Essential"** with a badge, and offer a **"Just the essentials (10 min)"** express path alongside the full tour.

### 7.2 How a step works
Each step should be able to:
- **Navigate** the phone to a specific screen and state.
- **Spotlight** an element — dim the rest of the phone and cut a rounded hole around the target, with a soft accent ring around it. (An SVG mask or four overlay divs both work; make sure it tracks the element's real bounding box and follows it on resize/scroll.)
- Show a **coach-mark callout** anchored to the target with a little arrow, containing a short title and one or two sentences.
- Fill the **explanation panel** beside the phone with the deeper teaching: *what this is, why it exists, what agents get wrong about it, and a "try it" instruction.*
- Optionally **require an interaction** to advance — a "do it yourself" step. e.g. *"Now tap Create & Continue."* The Next button stays disabled until they do it, then it advances automatically with a satisfying little confirmation. **Mix these in generously** — passive tours don't teach.
- Offer **Back / Next / Skip chapter**, plus keyboard navigation (← → to move, `Esc` to exit the tour into free-roam).

### 7.3 Free-roam mode
A prominent **"Explore on your own"** toggle. The tour overlay lifts and the phone becomes fully interactive — every screen reachable, every form fillable, every sheet openable. All the demo data stays live and mutations persist (in memory) so someone can genuinely practise: create a property, watch it appear in the list, open it, see it blocked by compliance, fix the gates, publish it.

**Make the whole replica actually work.** This is the difference between a slideshow and a training tool. Wire up real state: creating a contact adds them to the contacts list; creating an event puts it on the calendar *and* in Today's schedule *and* makes it the "next appointment" on Home; dragging a task moves it and updates the "{n} open · {n} overdue" counter; uploading photos to a property satisfies the Photos compliance gate.

### 7.4 The explanation panel — voice and content
For every screen and every significant control, write:
- **What it is** — one plain sentence.
- **Why it exists** — the business reason. (*"FICA is a legal requirement in South Africa; you cannot market a property without the seller's identity verified."*)
- **How to use it** — the concrete steps.
- **What people get wrong** — the actual gotcha. Be candid. (*"The property is created at the end of Step 2, not at the end of Step 4. If you close the wizard after Step 2, the property is already saved — as a draft."*)

Tone: **plain, warm, direct, and never condescending.** These are working estate agents, not children. Short sentences. No marketing fluff, no exclamation marks. Assume they're busy and slightly frustrated — that's why they opened this page.

### 7.5 Extra learning aids to build in
- **A hover/tap glossary.** Any UI term with a defined meaning (FICA, POPIA, mandate, sole mandate, authority to market, P24, pillar, Core Match, syndication, draft vs active, co-listing) gets a dotted underline; hovering or tapping shows a definition popover. Build a proper glossary object and link it throughout.
- **A "Legend" panel** — a live key of the design language: every status colour, every pillar colour, the AI badge, the money gold, the confidence pips, what each icon means. Learners can pop it open at any time from the top bar.
- **A gesture cheat-sheet** — swipe right to complete, swipe left to skip, long-press to drag, pull to refresh, hold the mic. Animate each one in a small looping demo.
- **A search box over the tour** — typing "how do I publish a listing" jumps to the compliance chapter. Simple keyword matching over chapter titles and body text is plenty.
- **Progress persistence** — save completed chapters to `localStorage` so a learner can come back tomorrow. Include a "Reset progress" control.
- **A "What's the difference?" comparison card** for the two sides — an at-a-glance table of what an Agent sees vs what a Client sees.

---

## PART 8 — DEMO DATA

Make it South African, plausible, and internally consistent. Use these seeds and expand.

**The agent:** Andre Roets · `andre@homefinderscoastal.co.za` · Agent · Home Finders Coastal.

**Properties (8–12):**
- `12 Beach Road, Uvongo` — For Sale, **Active**, R 2 850 000, 4 bed / 2 bath / 2 garage, 240 m², Sole mandate, 12 photos, **Live on Property24 + Website**
- `7 Marine Drive, Margate` — For Sale, **Draft**, R 1 750 000, 3 / 2 / 1, **BLOCKED** (no authority to market, seller FICA pending, 3/12 photos)
- `Unit 4, Ocean View Complex, Ramsgate` — For Rental, **Active**, R 12 500 / month, 2 / 1 / 1
- `88 Ridge Crescent, Southbroom` — For Sale, **Under Offer**, R 4 200 000, 5 / 3 / 2, sea view, pool
- `21 Protea Street, Port Shepstone` — For Sale, **Active**, R 990 000, 2 / 1 / 0, **Co-listing** (belongs to another agent)
- …plus a few more for a realistic list and working filters.

**Contacts (10–15):** John Meyer (Buyer, WhatsApp × 7), Sarah Naidoo (Seller — *make her the client-portal persona*), Thabo Molefe (Tenant), Elena Petrov (Investor), Riaan van Zyl (Landlord), Priya Chetty (Buyer), etc. Give a couple of them linked properties and matches.

**Core Matches:** *"Beach house under R2.5m"* for John Meyer — For Sale, R 1 200 000 – R 2 500 000, 3+ beds, 2+ baths, suburbs Uvongo + Margate + Ramsgate — returning results across all three tiers (a 92% strong, an 88% strong, a 71% good, a 58% fair) with a couple of client reactions already in.

**Today / Calendar:** a handful of events across today and the week — `Viewing — 12 Beach Road` at 09:30, `Seller feedback call — Sarah Naidoo` at 11:00, `Show day — Ocean View Complex` (all day), a couple of conflicting ones so the Quick Add conflict banner actually fires.

**Tasks:** ~8 across the three columns, two of them overdue (so the header reads *"6 open · 2 overdue"* in red), a few archived.

**Notifications:** a mix of overdue / warning / info across the Properties, Contacts, Deals and My-activity pillars, some unread.

**Portal Leads:** 3–5 across the current week, a couple unread, split between P24 and PP.

**Client persona:** **Sarah Naidoo** — a *seller* (so the "My Listings" card and the seller insights dashboard both light up) who is *also* a buyer with an active Core Match (so "Matched for you" is populated). That single persona lets you demo the entire client side. Her listing: `12 Beach Road, Uvongo` — 3 viewings, 21 days listed, market value R 2 850 000, area average R 2 610 000.

---

## PART 9 — QUALITY BAR / ACCEPTANCE CHECKLIST

Before you call this done, verify every one of these:

- [ ] Single HTML file. Zero external requests. Opens correctly from `file://`.
- [ ] Both **light and dark** themes are complete and correct, and the toggle re-themes the entire phone.
- [ ] The **agency accent swatcher** re-brands the app live; **money gold** and the **AI-badge purple** correctly do *not* change.
- [ ] The **AI on/off** switch correctly hides the Ellie tab and degrades the "Meet Ellie" card.
- [ ] Every colour, radius, font size and shadow comes from the token values in Part 2. No invented values.
- [ ] All UI copy is **verbatim** from Part 4/5/6. No paraphrasing of button labels or empty states.
- [ ] The **property wizard** works end to end, including the cascading location picker, the "Missing Required Fields" dialog with a working **"Take me there"**, the spaces stepper (with 0.5 steps for bathrooms), the feature picker with its All-Units/Per-Unit tabs, and the simulated photo upload with a failure and a retry.
- [ ] The **compliance gates** genuinely block "Send Authority to Market" until resolved, and resolving them (e.g. uploading enough photos) genuinely unblocks it.
- [ ] The **contact duplicate dialog** fires on a known-duplicate phone number.
- [ ] **Ellie** records on hold, pulses red, and produces a result sheet with a working **Undo** and a working **Open event** that lands on a real event in the calendar.
- [ ] The **AI suggestions panel** polls, shows confidence pips, lets you inspect source images, and applies.
- [ ] **Tasks** drag between columns with a mouse *and* support the swipe gestures.
- [ ] The **client portal** is fully walkable, including reactions, the "Not for me" reason sheet, the seller insights dashboard, testimonials and the tri-state consent screen.
- [ ] The **spotlight** correctly tracks its target's bounding box (including after a resize) and never leaves a stale hole.
- [ ] Tour progress persists to `localStorage`; "Reset progress" works.
- [ ] Keyboard navigation works (← → Esc). Focus is visible. `prefers-reduced-motion` is respected.
- [ ] It's responsive: on a narrow screen the explanation panel stacks below the phone and nothing overflows horizontally.
- [ ] Nothing renders as `null`, `undefined` or `NaN`. Missing values show **"—"**.

---

## PART 10 — HOW TO APPROACH IT

Work in this order so you always have something coherent:

1. Tokens, the CSS reset, the phone frame, the icon helper, and the theme system.
2. The component library (card, button, chip, status chip, KPI tile, module tile, icon box, input, bottom sheet, empty state, app bar, bottom nav). Get these right and every screen after this is quick.
3. The router / screen-state machine and the demo-data store.
4. The agent screens, in this order: Login → Home → Today → Calendar → Tasks → Properties (list → wizard → overview) → Contacts (list → new → detail) → Core Matches → Portal Leads → Notifications → Settings/Profile/QR.
5. Ellie and the AI suggestions panel.
6. The full client side.
7. The tour engine, the spotlight, and the explanation panel.
8. Write all the tour content.
9. The glossary, the legend, the gesture cheat-sheet and the search.
10. Polish: motion, focus states, empty states, the acceptance pass.

Don't stop early or leave sections as "TODO" — build the whole thing. If you must trade something off, keep **fidelity to the design system** and **the depth of the explanations**; those are what make this useful.

Start now.
