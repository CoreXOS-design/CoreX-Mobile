import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/client_models.dart';
import '../services/api_service.dart' show ApiException;
import '../services/client_auth_service.dart';
import '../services/messaging_service.dart';

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

  // Rentals sides at the current agency, from the latest /client/me. Never
  // persisted: a cold start, sign-in or agency switch starts at neither and
  // shows rentals only once /client/me says so.
  ClientRentalSides _rentals = ClientRentalSides.none;
  bool _rentalsLoaded = false;
  // Bumped whenever the agency (or person) changes, so a /client/me that was
  // already in flight cannot apply the previous agency's flags.
  int _rentalsGen = 0;

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
  ClientRentalSides get rentals => _rentals;

  /// True once /client/me has answered for the current agency.
  bool get rentalsLoaded => _rentalsLoaded;

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
      _applyRentals(me.rentals);
      _client = me.client;
      _contact = me.contact;
      _agent = me.agent;
      _agencies = me.agencies;
      _passwordMustChange = me.client.passwordMustChange;
      _isLoggedIn = true;
      // Re-register the phone on every cold start (the token may have
      // rotated while the app was closed).
      unawaited(MessagingService.instance.onClientLogin());
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
    // The login response has no rentals block; Home's refreshMe fills it.
    _clearRentals();
    notifyListeners();
    unawaited(MessagingService.instance.onClientLogin());
  }

  Future<void> saveToken(String token) => _api.saveToken(token);

  void _clearRentals() {
    _rentalsGen++;
    _rentals = ClientRentalSides.none;
    _rentalsLoaded = false;
  }

  void _applyRentals(ClientRentalSides sides) {
    _rentals = sides;
    _rentalsLoaded = true;
  }

  Future<void> refreshMe() async {
    final gen = _rentalsGen;
    try {
      final me = await _api.me();
      if (gen == _rentalsGen) _applyRentals(me.rentals);
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
    // Rentals sides are per agency: hide them until /client/me answers for
    // the new one (the same person may be a tenant at one, a buyer at another).
    _clearRentals();
    notifyListeners();
    unawaited(refreshMe().catchError((_) {}));
    // Pushes are per agency: register this phone again for the new one.
    unawaited(MessagingService.instance.onClientLogin());
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
    // Before the token goes: the device-token DELETE needs it.
    await MessagingService.instance.onClientLogout();
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
    _clearRentals();
    notifyListeners();
  }
}
