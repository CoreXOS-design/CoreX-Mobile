import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'client_agent_qr_signup_screen.dart';

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

  static final RegExp _slugRe = RegExp(r'^[a-z0-9]{6,16}$');

  String? _extractSlug(String raw) {
    final value = raw.trim();
    Uri? uri;
    try {
      uri = Uri.parse(value);
    } catch (_) {
      return null;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    final segments = uri.pathSegments;
    // Expect path like /r/a/{slug}
    if (segments.length < 3) return null;
    if (segments[segments.length - 3] != 'r') return null;
    if (segments[segments.length - 2] != 'a') return null;
    final slug = segments.last.toLowerCase();
    if (!_slugRe.hasMatch(slug)) return null;
    return slug;
  }

  void _onDetect(BarcodeCapture capture) {
    if (!mounted) return;
    if (_handled) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final slug = _extractSlug(raw);
      if (slug != null) {
        _handled = true;
        _controller.stop();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ClientAgentQrSignupScreen(slug: slug),
          ),
        );
        return;
      } else {
        setState(() => _errorBanner = 'Not a CoreX agent QR code');
        return;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
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
            errorBuilder: (context, error, child) => Center(
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
                      'Point at the agent\'s QR code',
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
