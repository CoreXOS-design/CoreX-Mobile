import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../config/env.dart';
import 'client_agent_qr_signup_screen.dart';

final RegExp _slugRe = RegExp(r'^[a-z0-9]{6,16}$');

/// Hosts whose QR codes we accept. Production is always allowed; the host of
/// the configured API base URL is added so a staging build still scans QRs
/// minted by staging.
Set<String> _allowedHosts() {
  final hosts = <String>{'corexos.co.za', 'www.corexos.co.za'};
  final apiHost = Uri.tryParse(Env.apiBaseUrl)?.host.toLowerCase();
  if (apiHost != null && apiHost.isNotEmpty) hosts.add(apiHost);
  return hosts;
}

/// Returns the agent slug for a scanned payload, or null when it isn't a
/// CoreX agent QR. Validation is purely host + path shape — no API call.
///
/// Accepted:
///   https://corexos.co.za/corex/agents/{name-slug}/{slug}  (current)
///   https://corexos.co.za/r/a/{slug}                       (legacy redirect)
///
/// {name-slug} is cosmetic and deliberately not validated.
String? extractAgentQrSlug(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (!_allowedHosts().contains(uri.host.toLowerCase())) return null;

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final bool isCurrent = segments.length == 4 &&
      segments[0] == 'corex' &&
      segments[1] == 'agents';
  final bool isLegacy =
      segments.length == 3 && segments[0] == 'r' && segments[1] == 'a';
  if (!isCurrent && !isLegacy) return null;

  final slug = segments.last.toLowerCase();
  return _slugRe.hasMatch(slug) ? slug : null;
}

class ClientAgentQrScannerScreen extends StatefulWidget {
  const ClientAgentQrScannerScreen({super.key});

  @override
  State<ClientAgentQrScannerScreen> createState() =>
      _ClientAgentQrScannerScreenState();
}

class _ClientAgentQrScannerScreenState
    extends State<ClientAgentQrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  bool _handled = false;
  String? _errorBanner;

  void _onDetect(BarcodeCapture capture) {
    if (!mounted) return;
    if (_handled) return;
    var sawPayload = false;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      sawPayload = true;
      final slug = extractAgentQrSlug(raw);
      if (slug != null) {
        _handled = true;
        unawaited(_controller.stop());
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ClientAgentQrSignupScreen(slug: slug),
          ),
        );
        return;
      }
    }
    // Nothing in this frame was a CoreX agent QR — stay on the scanner.
    if (sawPayload && _errorBanner == null) {
      setState(() => _errorBanner = 'Not a CoreX agent QR code');
    }
  }

  @override
  void dispose() {
    // Async since mobile_scanner 6; State.dispose can't await, and the
    // teardown doesn't need to complete before this frame ends.
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            // mobile_scanner 7 dropped the trailing `child` argument.
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Camera unavailable: ${error.errorCode.name}',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          // Crosshair overlay
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.flash_on, color: Colors.white),
                    onPressed: () => _controller.toggleTorch(),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_errorBanner != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _errorBanner!,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    const Text(
                      'Point at your agent\'s QR code to create your account',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
