import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../main.dart' show logoutAndReset, rootNavigatorKey;
import '../services/api_service.dart';
import '../widgets/ui/auth_scaffold.dart';
import '../widgets/ui/glow_button.dart';

/// Agent account deletion — App Store guideline 5.1.1(v).
///
/// What this actually does, because the copy in here has to be honest about
/// it: `DELETE /v1/me/app-access` deletes the agent's **app account** — their
/// ability to sign in to CoreX Mobile, on every device. It does not delete the
/// CoreX record behind it. An agent's deals, commissions and FICA documents
/// are the agency's business records, retained under South African law, and
/// are not the agent's alone to erase — the same reasoning already documented
/// on the client-side flow in `client/client_delete_account_screen.dart`.
///
/// Wording rules, learned the hard way on that client flow (App Review
/// rejected an earlier build for reading as deactivation):
///   * Say **deleted**. Never "disabled", "deactivated", "paused", "temporary".
///   * Never claim every trace of the person is erased — it isn't.
///   * Say nothing here about getting access back. The flow reads as a
///     deletion, which is what Apple requires; an earlier draft carried a
///     "you can restore this later" footnote and it undercut exactly that.
///
/// Restoring is web-only and self-service (My Portal → Tools on the CoreX
/// website). Nothing in the app mentions or performs it — the one place a user
/// is told the account is gone rather than restorable is
/// [kAccountDeletedSignInMessage], which fires only after they try to sign in
/// again and so cannot soften the deletion itself.
const Color _kDanger = Color(0xFFEF4444);

/// Shown on the login screen when a sign-in is refused with `account_deleted`,
/// and when a live session is dropped because access was deleted elsewhere.
const String kAccountDeletedSignInMessage =
    'This account has been deleted. To use the app again, restore app access '
    'from My Portal → Tools on the CoreX website, or ask your administrator.';

/// Entry point for the whole flow: confirm → password → signed out on the
/// login screen. Call this from wherever the destructive row lives.
Future<void> startAccountDeletion(BuildContext context) async {
  if (!await _confirmDelete(context) || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const DeleteAccountScreen()),
  );
}

/// Native confirm sheet. Cupertino on Apple platforms so the destructive action
/// gets the system red — this dialog is the one the reviewer will look at.
Future<bool> _confirmDelete(BuildContext context) async {
  const title = 'Delete your account?';
  const body = 'Your CoreX app account will be deleted and you will be signed '
      'out of this device.';

  final platform = Theme.of(context).platform;
  final isApple =
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

  if (isApple) {
    return await showCupertinoDialog<bool>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text(title),
            content: const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(body),
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              CupertinoDialogAction(
                isDestructiveAction: true,
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }

  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(title),
          content: const Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: _kDanger),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;
}

/// Clears the local session and hard-resets navigation to the login screen.
///
/// The token goes first and on its own: the server has already revoked it, and
/// being killed anywhere in here must not leave a dead bearer on disk. The rest
/// ([logoutAndReset] → messaging teardown, saved email, branding, biometric
/// opt-in) is ordinary sign-out cleanup that can safely fail.
Future<void> _finishAccountDeletion(BuildContext context) async {
  await ApiService().clearToken();
  if (context.mounted) {
    await logoutAndReset(context);
  } else {
    await _resetFromRoot();
  }
  _showDeletionToast('Your account has been deleted.');
}

/// Fallback for when the calling screen was disposed while the request was in
/// flight: the root navigator context outlives it and drives the same reset.
Future<void> _resetFromRoot() async {
  final ctx = rootNavigatorKey.currentContext;
  if (ctx == null) return;
  await logoutAndReset(ctx);
}

/// Posts to the app-root messenger — the calling screen is gone by this point.
void _showDeletionToast(String message) {
  final ctx = rootNavigatorKey.currentContext;
  if (ctx == null) return;
  ScaffoldMessenger.maybeOf(ctx)
      ?.showSnackBar(SnackBar(content: Text(message)));
}

String _deletionErrorMessage(Object error) {
  if (error is! ApiException) {
    return 'Could not reach the server. Check your connection.';
  }
  switch (error.statusCode) {
    case 401:
      return 'Your session has expired. Sign in again to delete your account.';
    case 429:
      return 'Too many attempts. Please try again in a minute.';
    default:
      // 422 carries the server's "Incorrect password."
      return error.message;
  }
}

/// Password confirmation step — the API requires the current password, and it
/// doubles as the accident guard Apple allows for.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _api = ApiService();

  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _api.deleteAppAccess(_passwordController.text);
      if (!mounted) return;
      await _finishAccountDeletion(context);
    } catch (e) {
      // A wrong password (422) deleted nothing — stay put with the session
      // intact so they can retry or back out.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _deletionErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Delete account',
      // Kept word-for-word in step with the confirm dialog in [_confirmDelete].
      // The two screens are back-to-back in one flow, so any drift between them
      // reads as a contradiction at the exact moment the user is deciding.
      subtitle: 'Enter your password to delete your CoreX app account. You '
          'will be signed out of this device.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _passwordController,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                hintText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                ),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Enter your password' : null,
              onFieldSubmitted: (_) => _busy ? null : _submit(),
            ),
            if (_error != null) AuthError(_error!),
            const SizedBox(height: 24),
            GlowButton(
              onPressed: _busy ? null : _submit,
              loading: _busy,
              color: _kDanger,
              child: const Text('Delete my account'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
