import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  /// Reads a key from the loaded .env, or null when dotenv hasn't been
  /// initialised yet (e.g. in widget tests). Never throws — callers fall back
  /// to a sane default rather than crashing a build.
  static String? _get(String key) =>
      dotenv.isInitialized ? dotenv.env[key] : null;

  static String get apiBaseUrl {
    final v = _get('API_BASE_URL');
    return (v == null || v.isEmpty) ? 'https://staging.corexos.co.za/api' : v;
  }

  static bool get useMockData => _get('USE_MOCK_DATA')?.toLowerCase() == 'true';

  static String get agencySlug {
    final v = _get('AGENCY_SLUG');
    return (v == null || v.isEmpty) ? 'home-finders-coastal' : v;
  }
}
