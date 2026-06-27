import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/branding.dart';
import '../services/api_service.dart';
import '../theme.dart';

/// Holds the active agency branding and exposes it to the widget tree.
/// Cached in SharedPreferences keyed by agency id (or slug pre-login) so the
/// app starts with the correct colours before the network call returns.
class BrandingProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  static const String _cacheKey = 'branding_cache_v1';

  Branding _branding = Branding.fallback;
  bool _loaded = false;
  bool _disposed = false;

  Branding get branding => _branding;
  bool get loaded => _loaded;

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Restore the last-used branding from disk so the first frame uses the
  /// agency's colours, not the fallback.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw != null) {
      try {
        _branding = Branding.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        _loaded = true;
        AppTheme.updateActiveBranding(_branding);
        _safeNotify();
      } catch (_) {
        // Ignore corrupt cache.
      }
    }
  }

  /// Pre-login fetch. Safe to call without auth.
  Future<void> loadBySlug(String slug) async {
    try {
      final b = await _api.getBrandingBySlug(slug);
      await _set(b);
    } catch (e) {
      debugPrint('[branding] loadBySlug failed: $e');
    }
  }

  /// Post-login: tries /v1/logged-user first; if that's not authorised
  /// (some deployments guard v1 with a different token), falls back to
  /// extracting the agency slug from the user profile and hitting
  /// /v1/branding/{slug}.
  ///
  /// [profile] is the cached `/profile` (or `/login`) payload, used for the
  /// fallback slug lookup. May be null.
  Future<Map<String, dynamic>?> loadFromLoggedUser({
    Map<String, dynamic>? profile,
  }) async {
    try {
      final payload = await _api.getLoggedUser();
      final block = payload['branding'];
      if (block is Map) {
        final b = Branding.fromJson(Map<String, dynamic>.from(block));
        debugPrint('[branding] loaded from /v1/logged-user: '
            'sidebar=${block['colors']?['sidebar']} '
            'button=${block['colors']?['button']}');
        await _set(b);
      } else {
        debugPrint('[branding] /v1/logged-user returned no branding block');
      }
      return payload;
    } catch (e) {
      debugPrint('[branding] loadFromLoggedUser failed ($e) — '
          'falling back to slug-based branding');
      final slug = _agencySlugFrom(profile);
      if (slug != null) {
        debugPrint('[branding] fallback: loadBySlug($slug)');
        await loadBySlug(slug);
      } else {
        debugPrint('[branding] no agency slug found in profile. '
            'profile keys=${profile?.keys.toList()}');
      }
      return null;
    }
  }

  /// Walk a few likely shapes to find an agency slug in the profile payload.
  /// Covers both flat (`agency_slug`) and nested (`agency.slug`, `team.slug`)
  /// styles so the fallback works without locking to one schema.
  String? _agencySlugFrom(Map<String, dynamic>? profile) {
    if (profile == null) return null;
    final candidates = <dynamic>[
      profile['agency_slug'],
      (profile['agency'] is Map) ? (profile['agency'] as Map)['slug'] : null,
      (profile['team'] is Map) ? (profile['team'] as Map)['slug'] : null,
      (profile['user'] is Map)
          ? ((profile['user'] as Map)['agency_slug'] ??
              (((profile['user'] as Map)['agency'] is Map)
                  ? ((profile['user'] as Map)['agency'] as Map)['slug']
                  : null))
          : null,
    ];
    for (final c in candidates) {
      if (c is String && c.isNotEmpty) return c;
    }
    return null;
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    _branding = Branding.fallback;
    AppTheme.updateActiveBranding(_branding);
    _safeNotify();
  }

  Future<void> _set(Branding b) async {
    _branding = b;
    _loaded = true;
    AppTheme.updateActiveBranding(b);
    debugPrint('[branding] applied: button=${_hex(b.button)} '
        'icon=${_hex(b.icon)} sidebar=${_hex(b.sidebar)} '
        'default=${_hex(b.defaultColor)}');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey,
      jsonEncode({
        'logo_url': b.logoUrl,
        'colors': {
          'sidebar': _hex(b.sidebar),
          'icon': _hex(b.icon),
          'default': _hex(b.defaultColor),
          'button': _hex(b.button),
        },
      }),
    );
    _safeNotify();
  }

  static String _hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}
