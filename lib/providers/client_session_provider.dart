import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/client_models.dart';
import '../services/api_service.dart' show ApiException;
import '../services/client_auth_service.dart';

// Owns the long-lived client session: token, profile, agencies, current
// agency. Sibling to AuthProvider — they never both hold a session at the
// same time (logging in to one tears down the other in main.dart).
class ClientSessionProvider extends ChangeNotifier {
  final ClientAuthService _api = ClientAuthService();

  bool _checking = true;
  bool _isLoggedIn = false;
  ClientProfile? _client;
  ClientContact? _contact;
  ClientAgent? _agent;
  List<ClientAgency> _agencies = const [];
  bool _passwordMustChange = false;

  // Set once the client has chosen an agency for the *current* app run. It is
  // intentionally in-memory only: a cold start clears it so the picker shows
  // again on every app open — until the client locks to a specific agency.
  bool _agencyChosenThisSession = false;

  bool get isChecking => _checking;
  bool get isLoggedIn => _isLoggedIn;
  bool get passwordMustChange => _passwordMustChange;
  ClientProfile? get client => _client;
  ClientContact? get contact => _contact;
  ClientAgent? get agent => _agent;
  List<ClientAgency> get agencies => _agencies;

  ClientAgency? get currentAgency {
    final id = _client?.currentAgencyId ??
        _client?.lockedToAgencyId ??
        _client?.preferredAgencyId;
    if (id == null) return null;
    for (final a in _agencies) {
      if (a.id == id) return a;
    }
    return _agencies.isNotEmpty ? _agencies.first : null;
  }

  /// Whether the agency picker should be shown on app open. It keeps asking on
  /// every cold start until the client locks to a specific agency
  /// ([ClientProfile.lockedToAgencyId]). Choosing without locking only
  /// dismisses it for the current run.
  bool get mustPickAgency {
    if (_agencies.length <= 1) return false;
    if (_client?.lockedToAgencyId != null) return false;
    return !_agencyChosenThisSession;
  }

  /// Cold-start: do we have a token and is it still valid?
  Future<void> bootstrap() async {
    // 3s timeout guards against flutter_secure_storage hanging on Android
    // KeyStore init on certain devices — defense-in-depth alongside the
    // disabled `encryptedSharedPreferences` flag in ClientAuthService.
    String? token;
    try {
      token = await _api.getToken().timeout(const Duration(seconds: 3));
    } catch (_) {
      token = null;
    }
    if (token == null) {
      _checking = false;
      notifyListeners();
      return;
    }
    try {
      final me = await _api.me().timeout(const Duration(seconds: 8));
      _client = me.client;
      _contact = me.contact;
      _agent = me.agent;
      _agencies = me.agencies;
      _passwordMustChange = me.client.passwordMustChange;
      _isLoggedIn = true;
    } on TimeoutException {
      // Network hung — leave logged-out so splash can finish.
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _api.clearToken();
      } else if (e.statusCode == 423) {
        _isLoggedIn = true;
        _passwordMustChange = true;
      }
    } on SocketException {
      _isLoggedIn = true;
    } catch (_) {
      // ignore
    }
    _checking = false;
    notifyListeners();
  }

  void applyLogin(ClientLoginResponse resp) {
    _client = resp.client;
    _agencies = resp.agencies;
    _passwordMustChange = resp.client.passwordMustChange;
    _isLoggedIn = true;
    // A fresh sign-in starts a new run: ask for the agency again unless locked.
    _agencyChosenThisSession = false;
    notifyListeners();
  }

  Future<void> saveToken(String token) => _api.saveToken(token);

  Future<void> refreshMe() async {
    try {
      final me = await _api.me();
      _client = me.client;
      _contact = me.contact;
      _agent = me.agent;
      _agencies = me.agencies;
      _passwordMustChange = me.client.passwordMustChange;
      _isLoggedIn = true;
      notifyListeners();
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await signOutLocal();
      } else if (e.statusCode == 423) {
        _isLoggedIn = true;
        _passwordMustChange = true;
        notifyListeners();
      }
    }
  }

  void applyAgencySelection({
    required ClientProfile client,
    required List<ClientAgency> agencies,
  }) {
    _client = client;
    _agencies = agencies;
    _agencyChosenThisSession = true;
    notifyListeners();
  }

  void clearPasswordMustChange() {
    _passwordMustChange = false;
    if (_client != null) {
      _client = ClientProfile(
        id: _client!.id,
        email: _client!.email,
        hasPassword: true,
        passwordMustChange: false,
        preferredAgencyId: _client!.preferredAgencyId,
        lockedToAgencyId: _client!.lockedToAgencyId,
        currentAgencyId: _client!.currentAgencyId,
        lastLoginAt: _client!.lastLoginAt,
      );
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    await _api.logout();
    await signOutLocal();
  }

  Future<void> signOutLocal() async {
    await _api.clearToken();
    _isLoggedIn = false;
    _client = null;
    _contact = null;
    _agent = null;
    _agencies = const [];
    _passwordMustChange = false;
    _agencyChosenThisSession = false;
    notifyListeners();
  }
}
