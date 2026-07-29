import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/ui/content_width.dart';

import '../services/api_service.dart';
import '../theme.dart';

// Persistent cache. The agent's slug never changes, so once fetched we
// keep both the JSON payload AND the rendered PNG bytes across launches.
const String _agentQrPrefsKey = 'agent_qr_cache_v2';

class _CachedQr {
  final Map<String, dynamic> data;
  final Uint8List png;
  _CachedQr(this.data, this.png);
}

_CachedQr? _memoryCache;

Future<_CachedQr?> _readCache() async {
  if (_memoryCache != null) return _memoryCache;
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_agentQrPrefsKey);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map &&
        decoded['data'] is Map &&
        decoded['png_b64'] is String) {
      final png = base64Decode(decoded['png_b64'] as String);
      _memoryCache = _CachedQr(
        Map<String, dynamic>.from(decoded['data'] as Map),
        png,
      );
      return _memoryCache;
    }
  } catch (_) {}
  return null;
}

Future<void> _writeCache(Map<String, dynamic> data, Uint8List png) async {
  _memoryCache = _CachedQr(data, png);
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _agentQrPrefsKey,
      jsonEncode({'data': data, 'png_b64': base64Encode(png)}),
    );
  } catch (_) {}
}

Future<void> clearAgentQrCache() async {
  _memoryCache = null;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_agentQrPrefsKey);
  } catch (_) {}
}

class MyAgentQrScreen extends StatefulWidget {
  const MyAgentQrScreen({super.key});

  @override
  State<MyAgentQrScreen> createState() => _MyAgentQrScreenState();
}

class _MyAgentQrScreenState extends State<MyAgentQrScreen> {
  final _api = ApiService();

  Map<String, dynamic>? _data;
  Uint8List? _png;
  bool _loading = false;
  String? _error;
  bool _sharing = false;
  bool _saving = false;

  /// Anchors the iPad share popover. UIKit raises an uncatchable
  /// NSInvalidArgumentException if a UIActivityViewController is presented on
  /// iPad without a source rect, so this is not optional.
  final GlobalKey _shareButtonKey = GlobalKey();

  Rect? _shareOrigin() {
    final box =
        _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final cached = await _readCache();
    if (cached != null) {
      if (!mounted) return;
      setState(() {
        _data = cached.data;
        _png = cached.png;
      });
      return;
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.getMyAgentQr();
      final pngUrl = res['png_url']?.toString();
      if (pngUrl == null || pngUrl.isEmpty) {
        throw Exception('Server returned no png_url');
      }
      final pngRes = await http.get(Uri.parse(pngUrl));
      if (pngRes.statusCode != 200) {
        throw ApiException(pngRes.statusCode, 'Could not download QR image');
      }
      final png = pngRes.bodyBytes;
      await _writeCache(res, png);
      if (!mounted) return;
      setState(() {
        _data = res;
        _png = png;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.statusCode == 401
            ? 'Session expired, please log in again.'
            : e.statusCode == 403
                ? 'This account is a client account, not an agent.'
                : "Couldn't load your QR (${e.statusCode}): ${e.message}. Tap to retry.";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load your QR: $e. Tap to retry.";
      });
    }
  }

  Future<void> _share() async {
    final url = _data?['url']?.toString();
    final png = _png;
    if (url == null) return;
    setState(() => _sharing = true);
    try {
      final origin = _shareOrigin();
      if (png != null) {
        await Share.shareXFiles(
          [XFile.fromData(png, name: 'agent-qr.png', mimeType: 'image/png')],
          text: url,
          sharePositionOrigin: origin,
        );
      } else {
        await Share.share(url, sharePositionOrigin: origin);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share QR')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _save() async {
    final png = _png;
    if (png == null) return;
    setState(() => _saving = true);
    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Photo library permission denied')),
          );
          return;
        }
      }
      await Gal.putImageBytes(png, name: 'corex-agent-qr');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to Photos')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save image')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My QR Code')),
      body: ContentSafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: GestureDetector(
          onTap: _load,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }
    if (_data == null || _png == null) return const SizedBox.shrink();

    final agent = (_data!['agent'] as Map?) ?? const {};
    final fullName = agent['full_name']?.toString() ?? '';
    final agency = (agent['agency'] as Map?) ?? const {};
    final agencyName = agency['name']?.toString() ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Image.memory(
              _png!,
              width: 280,
              height: 280,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Your Client QR',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Hand this to prospects. When they scan it in the CoreX app, '
            'they sign up directly as your client.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 12),
          if (fullName.isNotEmpty || agencyName.isNotEmpty)
            Text(
              [fullName, agencyName].where((s) => s.isNotEmpty).join(' · '),
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textMuted(context),
              ),
            ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: _shareButtonKey,
                  onPressed: _sharing ? null : _share,
                  icon: _sharing
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.share_outlined),
                  label: const Text('Share'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined),
                  label: const Text('Save Image'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
