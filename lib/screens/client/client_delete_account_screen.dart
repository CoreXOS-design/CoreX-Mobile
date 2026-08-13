import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../main.dart' show AuthGate, rootNavigatorKey;
import '../../providers/client_matches_provider.dart';
import '../../providers/client_session_provider.dart';
import '../../providers/seller_listings_provider.dart';
import '../../services/api_service.dart' show ApiException;
import '../../services/client_auth_service.dart';
import '../../widgets/ui/auth_scaffold.dart';
import '../../widgets/ui/glow_button.dart';

/// Account deletion — App Store guideline 5.1.1(v).
///
/// Wording rule for everything in this file: this removes the client's *login*
/// only. Their record with the agency (deal history, FICA documents) is kept as
/// a normal business record and is untouched, so the copy only ever talks about
/// the "account" / "app access" / being signed out everywhere. Never "your
/// data".
const Color _kDanger = Color(0xFFEF4444);

/// Entry point for the whole flow: confirm → (password step | straight to the
/// API) → signed out on the login screen.
///
/// [bearerToken] overrides the stored token — the forced password-change screen
/// holds the live one in memory and passes it through.
Future<void> startClientAccountDeletion(
  BuildContext context, {
  String? bearerToken,
}) async {
  if (!await _confirmDelete(context) || !context.mounted) return;

  final session = context.read<ClientSessionProvider>();
  // A client mid-forced-rotation is asked for nothing: they must be able to
  // leave without first setting a password they no longer want.
  final needsPassword =
      (session.client?.hasPassword ?? false) && !session.passwordMustChange;

  if (needsPassword) {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientDeleteAccountScreen(bearerToken: bearerToken),
      ),
    );
    return; // That screen owns the rest of the flow.
  }

  await _deleteWithoutPassword(context, bearerToken: bearerToken);
}

/// Native confirm sheet. Cupertino on Apple platforms so the destructive action
/// gets the system red — this dialog is the one the reviewer will look at.
Future<bool> _confirmDelete(BuildContext context) async {
  const title = 'Delete your account?';
  const body = 'You will be signed out of every device and will need to sign '
      'up again to use the app. This cannot be undone.';

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

/// Forced password-change path: no field to fill in, so run the call behind a
/// blocking spinner instead of pushing a screen for it.
Future<void> _deleteWithoutPassword(
  BuildContext context, {
  String? bearerToken,
}) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );

  try {
    await ClientAuthService().deleteAccount(bearer: bearerToken);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // spinner
    await finishClientAccountDeletion(context);
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // spinner
    showClientDeletionToast(deletionErrorMessage(e));
  }
}

/// Clears the session and hard-resets navigation to the login screen.
///
/// The token is dropped *before* navigating, so being killed mid-toast still
/// leaves nothing on disk — the server has already revoked it either way.
Future<void> finishClientAccountDeletion(BuildContext context) async {
  context.read<SellerListingsProvider>().reset();
  context.read<ClientMatchesProvider>().reset();
  await context.read<ClientSessionProvider>().signOutLocal();

  // Not popUntil(isFirst): the forced password-change screen is pushed with
  // `(r) => false`, so it *is* the first route and popping would land straight
  // back on it. Rebuilding from AuthGate reaches the login screen from any
  // entry point, and the session is already cleared so it renders immediately.
  rootNavigatorKey.currentState?.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const AuthGate()),
    (route) => false,
  );

  showClientDeletionToast('Your account has been deleted.');
}

/// Posts to the app-root messenger — the calling screen is gone by this point.
void showClientDeletionToast(String message) {
  final ctx = rootNavigatorKey.currentContext;
  if (ctx == null) return;
  ScaffoldMessenger.maybeOf(ctx)
      ?.showSnackBar(SnackBar(content: Text(message)));
}

String deletionErrorMessage(Object error) {
  if (error is! ApiException) {
    return 'Could not reach the server. Check your connection.';
  }
  switch (error.statusCode) {
    case 401:
      return 'Your session has expired. Sign in again to delete your account.';
    case 429:
      return 'Too many attempts. Please try again in a minute.';
    default:
      // 422 carries the server's "Password is incorrect."
      return error.message;
  }
}

/// Password confirmation step. Only reached when the client actually has a
/// password and is not mid-forced-rotation.
class ClientDeleteAccountScreen extends StatefulWidget {
  final String? bearerToken;

  const ClientDeleteAccountScreen({super.key, this.bearerToken});

  @override
  State<ClientDeleteAccountScreen> createState() =>
      _ClientDeleteAccountScreenState();
}

class _ClientDeleteAccountScreenState extends State<ClientDeleteAccountScreen> {
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _api = ClientAuthService();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _api.deleteAccount(
        password: _passwordController.text,
        bearer: widget.bearerToken,
      );
      if (!mounted) return;
      await finishClientAccountDeletion(context);
    } catch (e) {
      // A wrong password (422) deleted nothing — stay put with the session
      // intact so they can retry or back out.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = deletionErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Delete account',
      subtitle: 'Confirm your password to delete your account. You will be '
          'signed out of every device and will need to sign up again to use '
          'the app.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(
                hintText: 'Password',
                prefixIcon: Icon(Icons.lock_outline_rounded, size: 20),
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
              child: const Text('Delete account'),
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
