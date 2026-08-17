# Reply to App Review — 5.1.1(v) account deletion + 5.1.1(i)/5.1.2(i) third-party AI

Paste into Resolution Center. **Do not send the AI section until the in-app consent step
actually ships** — it claims a build feature that must exist when the reviewer looks.

---

Hello,

Thank you for the review. Replying to both items.

**Guideline 5.1.1(v) — Account deletion**

The app does support account deletion, entirely in the app, and the deletion is permanent
— there is no deactivate-only option and no customer-service step. We believe the option
was not found because it lives on the client account rather than the staff account, so
here is the exact path.

Sign in with the client account:
- Tap "I'm a client" on the first screen
- Email: a.roets12@gmail.com
- Password: [CLIENT PASSWORD]

Then: Profile / Settings (person icon in the navigation bar) → scroll to "Danger zone" →
**Delete account** → confirm in the dialog → re-enter the password → **Delete account**.

The account is deleted on our server at that moment, every session token is revoked, the
app signs out and shows "Your account has been deleted." That email can no longer sign
in. Nothing is queued, deactivated or held for review, and no email or phone call is
involved.

In build [BUILD NUMBER] we also made the on-screen wording unambiguous. The confirmation
dialog now reads: "Your account will be permanently deleted and you will be signed out of
every device. This cannot be undone."

On the second account type: staff accounts (estate agents and their managers) cannot be
created in the app. An agency administrator provisions them on our web system, and the app
offers no registration for them — the only account the app can create is the client
account described above, and that account can be deleted in the app. If you would prefer
an in-app deletion entry on the staff side as well, tell us and we will add it in the next
build.

A screen recording captured on a physical iPhone — signing in with the account above,
navigating to the option, and the complete deletion through to confirmation — is attached.

**Guidelines 5.1.1(i) and 5.1.2(i) — third-party AI service**

Confirming exactly what happens. One optional feature, the "Ellie" assistant, uses a
third-party AI service. When the user taps the microphone button and speaks an
instruction, the recording is uploaded to our own server and transcribed by speech-to-text
software running on our own infrastructure. The text of that instruction is then sent to
Anthropic (Claude API), which returns a draft calendar entry or task that the user
confirms, edits or discards.

That instruction text is all that is sent. No contact list, no client records, no
photographs, no location, no account credentials and no device or advertising identifiers
are sent to Anthropic. The feature never runs on its own — it is reached only by an
explicit tap on the microphone button — and if the user never uses it, nothing is sent.

In build [BUILD NUMBER] we added an in-app disclosure and permission step before any data
can be sent. The first time the user taps the microphone, a screen appears that names
Anthropic as the recipient, states what is sent (the words the user speaks) and what is
not, and requires the user to tap "Allow" before the first recording is made. Declining
leaves the feature switched off and sends nothing, and consent can be withdrawn at any
time in Settings.

Our privacy policy at [PRIVACY POLICY URL] has been updated to identify this data, how it
is collected, every use of it, and that Anthropic processes it under commercial terms
giving equivalent protection and does not use it to train models.

We are happy to provide anything further you need.

Kind regards,
[NAME]
[TITLE], CoreX OS
