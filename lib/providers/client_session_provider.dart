import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/client_models.dart';
import '../services/api_service.dart' show ApiException;
import '../services/client_auth_service.dart';
import '../services/debug_log.dart';

// Owns the long-lived client session: token, profile, agencies, current
// agency. Sibling to AuthProvider — they never both hold a session at the
// same time (logging in to one tears down the other in main.dart).
class ClientSessionProvider extends ChangeNotifier {
  final ClientAuthService _api = ClientAuthService();

  bool _checking = true;
  bool _isLoggedIn = false;
  ClientProfile? _client;
  ClientContact? _contact;
  List<ClientAgency> _agencies = const [];
  bool _passwordMustChange = false;

  bool get isChecking => _checking;
  bool get isLoggedIn => _isLoggedIn;
  bool get passwordMustChange => _passwordMustChange;
  ClientProfile? get client => _client;
  ClientContact? get contact => _contact;
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

  bool get needsAgencyPicker {
    if (_agencies.length <= 1) return false;
    if (_client?.lockedToAgencyId != null) return false;
    return _client?.currentAgencyId == null;
  }

  /// Cold-start: do we have a token and is it still valid?
  Future<void> bootstrap() async {
    final log = DebugLog.instance;
    log.add('client.bootstrap: start');
    final token = await _api.getToken();
    log.add('client.bootstrap: token=${token == null ? "null" : "present"}');
    if (token == null) {
      _checking = false;
      notifyListeners();
      return;
    }
    try {
      log.add('client.bootstrap: GET /v1/client/me');
      final me = await _api.me().timeout(const Duration(seconds: 8));
      log.add('client.bootstrap: /me OK');
      _client = me.client;
      _contact = me.contact;
      _agencies = me.agencies;
      _passwordMustChange = me.client.passwordMustChange;
      _isLoggedIn = true;
    } on TimeoutException {
      log.add('client.bootstrap: /me TIMEOUT');
    } on ApiException catch (e) {
      log.add('client.bootstrap: /me ApiException ${e.statusCode}');
      if (e.statusCode == 401) {
        await _api.clearToken();
      } else if (e.statusCode == 423) {
        _isLoggedIn = true;
        _passwordMustChange = true;
      }
    } on SocketException catch (e) {
      log.add('client.bootstrap: /me SocketException $e');
      _isLoggedIn = true;
    } catch (e) {
      log.add('client.bootstrap: /me ERROR $e');
    }
    _checking = false;
    log.add('client.bootstrap: done loggedIn=$_isLoggedIn');
    notifyListeners();
  }

  void applyLogin(ClientLoginResponse resp) {
    _client = resp.client;
    _agencies = resp.agencies;
    _passwordMustChange = resp.client.passwordMustChange;
    _isLoggedIn = true;
    notifyListeners();
  }

  Future<void> saveToken(String token) => _api.saveToken(token);

  Future<void> refreshMe() async {
    try {
      final me = await _api.me();
      _client = me.client;
      _contact = me.contact;
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
    _agencies = const [];
    _passwordMustChange = false;
    notifyListeners();
  }
}
