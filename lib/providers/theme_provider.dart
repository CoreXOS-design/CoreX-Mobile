import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class ThemeProvider extends ChangeNotifier {
  static const _key = 'theme_mode';
  final ApiService _api = ApiService();

  ThemeMode _themeMode = ThemeMode.dark;
  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;

  ThemeProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    if (value == 'light') {
      _themeMode = ThemeMode.light;
    } else {
      _themeMode = ThemeMode.dark;
    }
    notifyListeners();
  }

  Future<void> toggle() async {
    _themeMode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    final v = isDark ? 'dark' : 'light';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, v);
    // Mirror to server so the web cockpit picks up the same preference.
    // Fire-and-forget — local state is the source of truth for the UI.
    unawaited(_api.setUserTheme(v).catchError((_) {}));
  }

  /// Apply theme mode from a server value (e.g. branding/user-prefs API).
  /// Accepts 'light' or 'dark' (case-insensitive). Persists the result.
  Future<void> setFromApi(String? value) async {
    final v = value?.trim().toLowerCase();
    if (v != 'light' && v != 'dark') return;
    final mode = v == 'light' ? ThemeMode.light : ThemeMode.dark;
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, v!);
  }

  /// Pulls the user's saved theme from `/v1/me/theme` and applies it. Called
  /// on login (and cold-start with a valid session) so the app mirrors the
  /// server-side preference. Local toggles overwrite this via [toggle].
  Future<void> syncFromServer() async {
    try {
      final theme = await _api.getUserTheme();
      await setFromApi(theme);
    } catch (_) {
      // Silent — keep local preference if the server roundtrip fails.
    }
  }
}
