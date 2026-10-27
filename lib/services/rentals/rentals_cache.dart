import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Last-known JSON for screens that must keep working without signal (an
/// inspection walkthrough, its checklist, the due list). Reads never throw;
/// a missing or corrupt entry is simply null.
///
/// Entries are keyed per signed-in session so one person's cached inspection
/// is never shown to the next person on the phone.
class RentalsCache {
  RentalsCache._();

  static String _k(String session, String key) =>
      'rentals_cache_v1|$session|$key';

  static Future<Map<String, dynamic>?> read(String? session, String key) async {
    if (session == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_k(session, key));
      if (raw == null) return null;
      final m = jsonDecode(raw);
      return m is Map ? Map<String, dynamic>.from(m) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(
      String? session, String key, Map<String, dynamic> value) async {
    if (session == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_k(session, key), jsonEncode(value));
    } catch (_) {}
  }
}
