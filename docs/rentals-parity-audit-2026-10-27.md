# Rentals parity audit: mobile app vs web (27 Oct 2026)

**What I compared:** the server contract `.ai/specs/at-508-mobile-rentals-MOBILE-PROMPT.md` (Staging, last changed 25 Oct), the two companion prompts it points to (inspection view, push), and the Staging routes file. On the app side: the rentals screens, their API client and their offline queue, as they stand in the app repo today (including rentals work that is not committed yet).
**Report only.** No code was changed.

---

## 1. Rule breaches and bugs (read this first)

### Good news: the most important rules hold

- **Rule 7 (old tenant lease endpoint):** the app **never** calls `GET /client/rentals/leases/{lease}`. The app's code has no way to call it at all. A comment in the code says it was left out on purpose. The tenant's lease screen uses `my-lease`.
- **Rule 1 (no money for clients):** no rent, deposit or payment appears on any tenant or owner screen. (The owner does see repair quote amounts and extra-cost amounts when asked to decide. That is repair money, not rent. See Questions.)
- **Rule 2 (tenant sees nothing about the owner):** tenant screens show no owner name, contact or detail. A notice given by the owner reads "Notice has been given". If the server ever sent an owner detail by mistake, the app quietly records it as a server fault and still doesn't show it.
- **Rule 3:** the tenant sees the agent's name, phone and email, and no WhatsApp. The owner sees the tenant's name.
- **Rule 6:** when the server says "archived", a queued item is dropped and the person is told.

### Problems found (most important first)

**B1. Inspection condition colours ignore the agency's settings (rules 4 and A-a).**
The server says how serious each condition is (blue / red / amber / grey). The app ignores that and guesses a colour from the word itself. The result: "Damaged" and "Missing" show in the same neutral colour as "Good", and the one-tap condition buttons have no colour at all.
*What the agent sees:* a room where everything is broken looks the same as a room where everything is fine.

**B2. The phone decides when to offer "Start Out Inspection" (rule 5).**
The lease screen shows this button when the server's lease timeline says the move-out step is current. It also shows it when the phone itself sees an accepted notice or an expired lease. That second part is the phone's own reasoning, not the server's.
*What the agent sees:* the button can appear (or not) out of step with the web's "next step" card.

**B3. The phone offers buttons the server will refuse (rule 5).**
- "Sign as the agent (last)" shows even while tenants or the landlord still haven't signed. The server already sends the list of who is still outstanding, so the app only needs to hide the button until that list is empty.
- "Refused to sign" is offered to every agent, including agents without permission to record a refusal.

In both cases the server says no, so no wrong data is saved.
*What the agent sees:* they tap a button and then get a "no" message.

**B4. The Rental Images tab hides the server's message when no inspection is under way.**
The agent sees "Failed to load rental inspections" instead of the server's own plain-English reason.

**B5. Inventory photos that aren't filed to a room never appear in the app.** They are saved on the server and the web shows them. The phone just never displays them.

**B6. Small bits of wording the phone writes itself (rule 4, low risk):**
- The filter choices on list screens (e.g. "Draft", "In progress", "Overdue", "Within 60 days") are the app's own words.
- The staff inspection list uses the type tabs "Inspection" / "Out Inspection".
- The staff "record a condition" sheet shows the raw code ("Last recorded: damaged") instead of the agency's label.
- The Notice box on the staff lease screen shows raw codes such as "tenant" or "readvertise".
- The empty Documents screen uses the app's own sentence.
- On the tenant/owner inspection view the condition words are tidied-up codes, because the server sends no label there (server gap).

**Note on the contract document.** The app uses three server features that the contract document doesn't describe, but which are live in the Staging routes:
- filing an inspection photo to an item, a room or the unsorted tray
- adding, changing and removing inventory lines
- lease capture

I didn't count these as invented. The document should be updated so they are part of the contract.

---

## 2. Area by area

### A. Inspections

| Feature | Verdict | Where in the app | Note |
|---|---|---|---|
| Four types (In, Out, Routine, Interim) | MATCHES | Inspections list | Each row's type name comes from the server; the filter tabs use the app's own words (B6) |
| One live In per tenancy | MATCHES | Start flow | Server rule; the app shows the server's refusal |
| Start from a lease (due list or lease screen) | MATCHES | Due tab, lease screen | Works offline (queued) |
| Start from a property with no lease | SERVER GAP | — | The start endpoint needs a lease |
| Schedule, reschedule, cancel, archive, restore | SERVER GAP | — | |
| "Next inspection" chain | SERVER GAP | — | |
| "Start new inspection" to replace a sent report | SERVER GAP | — | |
| Checklist from the server, never hardcoded | MATCHES | Walkthrough | Cached for offline use |
| One-tap condition buttons from the agency's list | MATCHES | Record sheet | Labels come from the server |
| Severity colours | APP GAP | Record sheet, item rows | See B1 |
| Notes required where the agency requires them | MATCHES | Record sheet | "Record" stays disabled until a note is typed |
| N/A on an item | MATCHES | Record sheet | Works if the agency's condition list includes N/A |
| N/A per room, "All good" per room or whole inspection | SERVER GAP | — | |
| Room notes | MATCHES | Walkthrough | Works offline |
| Overall notes | MATCHES | Walkthrough | Needs signal (as the contract says) |
| Header block (meters, keys, remotes, furnished, move-in date) **shown** | APP GAP | — | The server sends it read-only; the app doesn't show it |
| Header block **edited** | SERVER GAP | — | |
| Discrepancy raise / resolve | MATCHES | Walkthrough | The server raises it; the app flags it and resolves it |
| Attendance (who was there) | MATCHES | Walkthrough | |
| Photos taken and sent straight away | MATCHES | Item, room, unsorted tray | One shot at a time per item/room/tray, several from the record sheet; queued offline |
| Tag / untag / bulk-tag / archive photos, photo notes, pairing, compare viewer | SERVER GAP | — | |
| Evidence "added after signing" | APP GAP (partly) | Walkthrough, client view | Late photos show a caption but sit among the normal photos; late condition records aren't shown at all |
| Signing parties (every tenant, landlord, agent) | MATCHES | Signatures box | List comes from the server |
| Agent signs last | APP GAP | Signatures box | The server enforces it; the button shows too early (B3) |
| Agent can never refuse | MATCHES | Signatures box | No refuse option for the agent |
| Refusal with a reason preset | MATCHES | Signatures box | Presets come from the server; "other" needs a note |
| Wet ink: will sign on paper / photograph the signed paper | MATCHES | Signatures box | |
| Print-for-signature | SERVER GAP | — | |
| "Ready to sign" step | SERVER GAP | — | The app shows the server's readiness message only |
| Personal signing links, QR | SERVER GAP | — | |
| "Sign now on this device" | APP GAP (partly) | Signatures box | A party can sign on the agent's phone, but there's no "read the report first" screen |
| Signed report is locked | MATCHES | Walkthrough | Lock banner; the server's refusal is shown |
| "Edit report" (clears signatures) | SERVER GAP | — | |
| Party PDFs, DRAFT stamp | SERVER GAP | — | No report PDF for the phone |
| Out: comparison against the In (staff view) | SERVER GAP | — | |
| Out: charges list | SERVER GAP | — | |
| Out: completion warnings with "Complete anyway" | MATCHES | Complete button | Shows the server's warnings, then "Go back" / "Complete" |
| "Still sending" guard on complete | MATCHES | Complete button | Shows "N still sending", pushes the queue, shows the server's reason |
| Unknown items on complete | MATCHES | Complete button | The server's message is shown |
| Archived while queued | MATCHES | Queue | Dropped, person told |
| Every offline write carries its key and time | MATCHES | Queue | |
| Rebuild from the server after reinstall | MATCHES | Walkthrough | Always reloads the full inspection from the server |
| Paper site form, scan back, AI read-back | SERVER GAP | — | |
| Raise a fault / work order / job card from an item | SERVER GAP | — | |
| Due board (view) | MATCHES | Due tab | |
| Due board planned dates (create / skip / reopen / archive) | SERVER GAP | — | |
| Build rooms from the standard checklist; add / rename / retire / reorder | SERVER GAP | — | |
| Tenant/owner view of a SENT inspection | MATCHES | Client inspections | Move-in shown beside move-out per item; signatures; link to the paired inspection; booked dates can't be opened |
| Staff view of a sent inspection | MATCHES (read-only) | Walkthrough | The move-in-beside-move-out comparison isn't in the staff data (server gap) |

### B. Inventory

| Feature | Verdict | Where in the app | Note |
|---|---|---|---|
| List and detail | MATCHES | Inventories | |
| Start an inventory (no lease needed) | SERVER GAP | — | |
| Same rooms as inspections | MATCHES | Inventory screen | Rooms come from the server |
| "Nothing in this room" mark / undo | SERVER GAP | — | |
| Show which rooms are marked empty | APP GAP | — | The server sends it; the app doesn't show it |
| Show rooms not yet visited | APP GAP | — | The server sends it; the app doesn't show it |
| Typed lines (quantity, description, room) | MATCHES | Inventory screen | Works offline |
| Condition chip from the agency's list | MATCHES | Line sheet | |
| Retire a line (never deleted) | MATCHES | Line sheet | |
| Copy from last inventory | SERVER GAP | — | |
| Batch photo upload (up to 10) | APP GAP (minor) | Inventory screen | One photo at a time |
| Photos tagged to a room or line | MATCHES | Inventory screen | Photos with no room are lost from view (B5) |
| "Inspection" badge on shared photos | APP GAP | — | The server flags them; the app shows no badge |
| Signatures shown | APP GAP | — | The server sends who signed; the app doesn't show it |
| Sign, complete, report PDF, public link, auto-email | SERVER GAP | — | |
| Locked after it leaves draft | MATCHES | Inventory screen | Add buttons hidden; the server's refusal is shown |
| Archived while queued | MATCHES | Queue | |
| Move-out comparison, per-line findings, move-out photos, sign-off | SERVER GAP | — | |
| Cancel / archive / restore | SERVER GAP | — | |
| Buyer acceptance link | SERVER GAP | — | |

### C. Rental images and Rental details

| Feature | Verdict | Where in the app | Note |
|---|---|---|---|
| In / Out / custom sections with dates | MATCHES | Property → Rental Images | |
| Upload | MATCHES | Rental Images | |
| Rename a section | MATCHES | Rental Images | |
| Delete (server archives it) | MATCHES | Rental Images | |
| Bulk delete | NOT SURE | — | Need the rental-images spec to see whether a bulk call exists |
| Download | NOT SURE | — | Same |
| "Not a rental" / "not live" | MATCHES | Rental Images | The server's wording is shown |
| "No inspection under way" | APP GAP | Rental Images | Generic error instead of the server's wording (B4) |
| "Unreadable image" | MATCHES | Rental Images | The server's message is passed through |
| Photos after completion flagged "added after signing" | APP GAP | Rental Images | The app ignores the flag |
| Rental amount, deposit, lease dates | MATCHES | Property edit | |
| Admin fee, marketing fee, commission % | APP GAP | Property edit | The server accepts them; the form doesn't offer them |
| Price type, lease period, furnished, occupation date, water/electricity/levies, "show available from", valve and DB board (with photos), custom fields | SERVER GAP | — | |

### D. Leases, notices, renewals

| Feature | Verdict | Where in the app | Note |
|---|---|---|---|
| Lease list with filters (expiring, status, sort, search) | MATCHES | Leases | |
| List tiles (counts) | SERVER GAP | — | The list endpoint gives no counts |
| Lease screen shows the server's next step, open items, timeline and permissions | MATCHES | Lease screen | Apart from B2 |
| One capture screen (new lease / renewal, three outcomes) | APP GAP | — | The server endpoint exists; the app has no screen (no capture key, missing list or renewal link) |
| "Who signs" check and confirm | APP GAP | — | The server endpoint exists |
| Lease fee as a lease term | NOT SURE | — | Not in the contract document; need confirmation it's live on Staging |
| Tenancy log | APP GAP | — | The server endpoint exists |
| Month-to-month and reverse | MATCHES | Lease screen | |
| Renewal draft (copy forward / template / upload) | APP GAP | — | The server endpoints exist |
| Agent records tenant or landlord notice | MATCHES | Lease screen | Uses notice date, intended end date and reason (the new names) |
| Attach a document to a recorded notice | APP GAP | — | Not offered |
| Notices to review (list) | MATCHES | Notices | Read-only, opens the lease |
| Accept / reject a received notice | SERVER GAP | — | |
| Reverse notice | MATCHES | Lease screen | |
| Change outcome (readvertise / withdraw / leave) | MATCHES | Lease screen | |
| Expiry notice state shown | MATCHES | Lease screen | "Expiry notice sent" row |
| Expiry notice send / mark given, alerts, red banner | SERVER GAP | — | |
| Breach notices | SERVER GAP | — | |
| Notices sent, resend, templates | SERVER GAP | — | |
| Notice-terms edit | SERVER GAP | — | |
| Lease edit / activate / cancel / escalate / archive | SERVER GAP | — | |
| Cancel a draft renewal | SERVER GAP | — | |
| Rental applications | SERVER GAP | — | The contract lists these as "later" |
| Deposit deductions, deposit calculator, trust interest | SERVER GAP | — | The contract lists these as "later" |
| Tenancy report PDF | SERVER GAP | — | |
| Portal access setup | SERVER GAP | — | |
| Open lease documents | SERVER GAP | Lease screen | Listed only; no download link from the server |

**For Johan's decision (money shown to staff):** the staff lease screens show **no** rent, deposit or lease fee. Elsewhere, staff do see:
- repair costs on work orders (approved amount, final cost, quote and invoice amounts), only when the server sends them, i.e. for staff allowed to see costs
- rent and deposit on the property edit form

### E. Faults, work orders, job cards

**Tenant and owner**

| Feature | Verdict | Where in the app | Note |
|---|---|---|---|
| Report a fault: first-aid steps, urgent switch, photos, offline | MATCHES | Tenant: Report a fault | |
| My faults + timeline | MATCHES | Tenant: My faults | |
| Add a note or photo | MATCHES | Fault screen | |
| Withdraw | MATCHES | Fault screen | Only offered when the server allows it |
| "Is it fixed?" | MATCHES | Work check screen | |
| Tenant progress (started / finished / not fixed) | MATCHES | Work order screen | |
| Owner approve / decline repair | MATCHES | Owner fault screen | |
| Owner quote decision | MATCHES | Owner work order | |
| Owner extra-cost (variation) decision | MATCHES | Owner decisions | |
| Owner query, stop / resume, repair request | MATCHES | Owner fault screen | |
| Owner appointment + progress | MATCHES | Owner work order | |
| Owner "how I want faults handled" per property + change request | APP GAP | — | The server endpoints exist; no screen |
| Shared invoices + quote document | MATCHES | Owner work order | |
| My Lease cards | MATCHES | Tenant / owner home | |
| Push preferences | MATCHES | Settings | Only the server's switchable list is shown |
| Give notice | MATCHES | Notices | |
| Documents | MATCHES | Documents | |
| Inspections (read-only, sent only) | MATCHES | Inspections | |
| Owner's emailed "I do not agree" link | WEB-ONLY (RULED) | — | |

**Staff**

| Feature | Verdict | Where in the app | Note |
|---|---|---|---|
| Fault list / detail / create / photos | MATCHES | Faults | |
| Record the owner's decision | MATCHES | Fault screen | Writes the older approval record; the screen doesn't assume the newer authorisation behaviour |
| Owner decision "agency appoints": pick a contractor | SERVER GAP | Fault screen | No contractor list for the phone; the app tells the agent to use the web |
| Set the outcome | MATCHES | Fault screen | |
| Work order list / detail / create / photos | MATCHES | Work orders | Create is online-only, as the contract says |
| Assign a supplier | SERVER GAP | — | The assign call exists but there's no contractor list to choose from |
| Record the contractor's answer | MATCHES | Work order screen | |
| File an invoice | MATCHES | Work order screen | |
| Complete (with "still sending" guard) | MATCHES | Work order screen | |
| Job card show / access note / tick task / photo | APP GAP | — | The server endpoints exist; no job card screen (job card items say "open on the web") |
| Command Centre counts | MATCHES | Rentals home | |
| Waiting list opens the right record | MATCHES | Rentals home | Uses subject type + id, not web route names |
| 6 rentals reports | APP GAP | — | A server reports endpoint exists (not in the contract document); the app doesn't use it |
| Screens hidden by permission | MATCHES | Rentals home | One fallback path opens the inspections list as if the person could act; the server still refuses |
| Owner-version draft, send to owner, send to inspect, authorisation records, fault edit / reclassify / cancel / archive, raise work order from fault, quotes, "approved up to" cost lock, variations, staff appointment, start progress, notes, cancel, who pays, send back, invoice edit / share / archive, job card list / create / crew / schedule / lines / sign-offs / complete, crews, parts-and-labour catalogue | SERVER GAP (all confirmed) | — | |
| Contractor / crew links | WEB-ONLY (RULED) | — | |

### F. Push

| Feature | Verdict | Where in the app | Note |
|---|---|---|---|
| Staff phone registration on login and refresh | MATCHES | Notifications | Removed on log-out |
| Tenant / owner phone registration on login and refresh | MATCHES | Notifications | |
| Android channel `corex_alerts` | MATCHES | Notifications | |
| Opens the right screen (tenant/owner: subject type + id; agent: target + id) | MATCHES | Notifications | Signs in first; a 403/404 goes home quietly |
| "Inspection report ready" for tenants / owners | MATCHES | Notifications | Opens the read-only inspection; the switch comes from the server's list |
| Must-have vs can-switch-off alerts | MATCHES | Settings | Only the server's switchable list is shown |
| Protection against push floods | MATCHES | Notifications | Duplicates dropped, banner rate capped |

---

## 3. Two short lists

### The app can do this already, it just isn't wired (APP GAP)
1. Severity colours on inspection conditions (B1)
2. Hide the agent's sign button until everyone else has signed; hide "refused" for agents without the right (B3)
3. "Start Out Inspection" driven only by the server (B2)
4. Lease capture screen (new lease and renewal), "who signs" check, tenancy log
5. Renewal drafts (copy forward / template / upload)
6. Owner "how I want faults handled" + change request
7. Job card screen (show, access note, tick task, photo)
8. Inspection header block (meters, keys, remotes) shown read-only
9. Inventory: rooms marked empty, rooms not yet visited, "Inspection" photo badge, who signed, photos with no room (B5), several photos at once
10. Rental Images: the server's wording for "no inspection under way" (B4); "added after signing" flag
11. "Added after signing" shown apart from the normal evidence on inspections
12. Admin fee, marketing fee and commission % on the property form
13. Attachment on a recorded notice
14. The six rentals reports
15. Small wording clean-up (B6)
16. *(Added after rulings)* "Read the full report, then sign" screen on the agent's phone
17. *(Added after rulings)* Contractor yes/no: a required note for both answers (today only an optional reason on "no")

### Needs the server team first (SERVER GAP), highest value first
*(Updated after Johan's rulings, section 4.)*

**Inspections: signing**
- "Ready to sign" step, personal signing links + QR (ruled wanted), print-for-signature, wet-ink supersede

**Inspections: scheduling and control**
- Schedule, reschedule and cancel with party notifications, archive / restore (all per role, ruled wanted), next inspection, replace a sent report
- Start from a property with no lease
- ("Edit report" is now WEB-ONLY, ruled)

**Inventory**
- Create on site (ruled wanted), "nothing in this room", sign, complete (per the web rule), report PDF / public link / email, copy from last, move-out comparison and sign-off, cancel / archive / restore, buyer link

**Notices**
- Act on a received notice (ruled: no reject): CPA / non-CPA flag, the actions that apply, record what was done
- Breach notices, notices sent / resend / templates
- Expiry notice send / mark given, notice-terms edit

**Rental applications**
- Create the contact + send the application out (ruled: phone does only this; review and authorise stay on the web)

**Leases: money for staff**
- Rent, deposit and lease fee in the staff lease data, for roles allowed to see costs only (ruled)

**Contractors**
- Contractor list for assigning (ruled wanted)
- Contractor yes/no: note required for both answers, "recorded by agent" marking (ruled)

**Inspections: the rest**
- Header details edit, room N/A / mark good / all good
- Photo tag / untag / archive / notes / pairing / compare
- Checklist editing and standard-checklist seeding
- Report PDF / public link / resend, paper form scan + review, follow-up from an item
- Move-out comparison findings and charges, planned-date management
- Condition labels in the tenant/owner inspection view

**Leases**
- Edit / activate / cancel / escalate / archive, cancel draft renewal, list counts
- Deposit calculator, trust interest, tenancy report PDF, portal access setup, document download

**Faults and work orders**
- A contractor list (unblocks "agency appoints" and supplier assignment)
- Everything in the staff "expected server gap" list above

**Rental details**
- Price type, lease period, furnished, occupation, utilities, "available from", valve / DB board with photos, custom fields

---

## 4. Johan's rulings (27 Oct 2026) and what they change

| # | Question | Johan's ruling | What it changes |
|---|---|---|---|
| 1 | Owners see quote and extra-cost amounts | **Yes**: the owner decides on the quote. | Nothing. The app is already right. |
| 2 | Rent, deposit, lease fee for staff on the phone | **Only roles allowed to see costs** (Role Manager, same as web). | **SERVER GAP:** the staff lease data has no money in it at all. The server must add rent, deposit and lease fee, sent only to roles allowed to see costs (the same way work-order costs already work). Then the app shows them when present. **To check:** the property edit form shows rent and deposit to every staff member; it should follow the same role rule. |
| 3 | Cancel / reschedule / archive an inspection | **Yes, per role**; parties are notified. Archive = soft delete, per role. | Still a **SERVER GAP**, now confirmed wanted: cancel and reschedule (with notifications), archive and restore, each with a per-role "may do this" flag in the inspection data so the phone shows the button only when allowed. |
| 4 | "Edit report" (wipes signatures) | **Not on the phone.** Office only; originals kept as versions. | Changes from SERVER GAP to **WEB-ONLY (RULED)**. The phone must keep showing a signed report as locked. |
| 5 | Tenant reads the report before signing | **Yes**, plus sign by link and sign by scanning a QR code on their own phone. | **APP GAP:** a "read the full report, then sign" screen on the agent's phone (the inspection data already has what it needs). **SERVER GAP:** ready-to-sign step, personal signing link, QR code. |
| 6 | Inventories on the phone | **Create on site** (room by room, with photos) **and add to the office's**; sign-off follows the web rule. | **SERVER GAP:** create an inventory, "nothing in this room" mark / undo, signatures (agent last), complete. The phone must not decide when an inventory may be signed off; the server's answer rules. Adding lines and photos already works. |
| 7 | Accept / reject a notice | **Agencies cannot reject a notice, only act on it.** A natural person (CPA tenant) may give notice regardless of the contract; a business tenant is bound by the lease. The phone shows the notice, who it's from (CPA / non-CPA) and the actions that apply; the agent records what was done. | Replaces "accept / reject". **SERVER GAP:** the notice data needs (a) whether the giver is a natural person (CPA) or a business, (b) the list of actions that apply to that notice, decided by the server, and (c) an endpoint to record the action taken. **APP GAP** once those exist: a notice detail screen showing the CPA / non-CPA badge and only the server's actions. **For the server team:** the web currently has "reject (reason required)". That conflicts with this ruling and should be reviewed. |
| 8 | Rental applications | **Phone: create the contact and send the application out only.** Reviewing uploaded documents and authorising stay on the web. | **SERVER GAP:** create contact + send application endpoints. Review and authorise become **WEB-ONLY (RULED)**. |
| 9 | Assign contractors | **Yes, per role**; the contractor still gets their per-job link. | **SERVER GAP:** a contractor list for the phone. The assign endpoint already sends the per-job link to a new contractor. Once the list exists it's an **APP GAP** (picker on the work order and on "agency appoints"). |
| 10 | Agent records the contractor's yes/no | **Keep it**, marked "recorded by agent", **note required**; the same screen gets added on the web so both match. | **SERVER GAP:** the server must require a note for both yes and no, and show "recorded by agent" (today it only asks for a reason on a "no"). **APP GAP:** the phone's note box only appears on a "no" and isn't required. It must become a required note for both answers, with the "recorded by agent" marking shown. **Web team:** add the matching web screen. |

---

## 5. Confirmation

This was an audit only. I changed no app code and no server code. The only file added is this report (rulings added 27 Oct 2026).
