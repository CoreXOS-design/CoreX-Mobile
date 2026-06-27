import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static String get apiBaseUrl => dotenv.env['API_BASE_URL'] ?? 'https://staging.corexos.co.za/api';
  static bool get useMockData => dotenv.env['USE_MOCK_DATA']?.toLowerCase() == 'true';
  static String get agencySlug => dotenv.env['AGENCY_SLUG'] ?? 'home-finders-coastal';
}
