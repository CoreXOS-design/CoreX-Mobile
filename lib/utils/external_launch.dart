import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] outside the app and always tells the user when it couldn't.
///
/// iPads and other Wi-Fi-only devices have no Phone app, so `tel:` and `sms:`
/// fail outright — `launchUrl` either returns false or throws a
/// PlatformException. Swallowing that leaves a Call button that does nothing
/// when tapped, which reads as a broken app. Fall back to putting the number
/// or address on the clipboard so the action is still completable.
Future<void> launchExternal(
  BuildContext context,
  String? url, {
  LaunchMode mode = LaunchMode.externalApplication,
}) async {
  if (url == null || url.isEmpty) return;
  final uri = Uri.tryParse(url);
  if (uri == null) return;

  // Captured before the await so we don't reach across the async gap.
  final messenger = ScaffoldMessenger.of(context);

  bool ok;
  try {
    ok = await launchUrl(uri, mode: mode);
  } catch (_) {
    ok = false;
  }
  if (ok) return;

  final handoff = _handoffTarget(uri);
  if (handoff != null) {
    await Clipboard.setData(ClipboardData(text: handoff));
    messenger.showSnackBar(
      SnackBar(content: Text('${_capability(uri)} — $handoff copied.')),
    );
    return;
  }
  messenger.showSnackBar(
    const SnackBar(content: Text("Couldn't open that link.")),
  );
}

/// The raw number / address behind a contact scheme, worth copying when the
/// device can't act on it directly.
String? _handoffTarget(Uri uri) {
  switch (uri.scheme) {
    case 'tel':
    case 'sms':
    case 'mailto':
      final target = Uri.decodeComponent(uri.path).trim();
      return target.isEmpty ? null : target;
    default:
      return null;
  }
}

String _capability(Uri uri) => switch (uri.scheme) {
      'tel' => "This device can't place calls",
      'sms' => "This device can't send texts",
      'mailto' => 'No mail app is set up',
      _ => "Couldn't open that",
    };
