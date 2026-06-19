import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/env.dart';
import '../models/client_models.dart';
import '../models/p24_location.dart';
import '../models/seller_models.dart';
import 'api_service.dart' show ApiException, ValidationException;

// Wraps every client-side endpoint. The session token lives in
// flutter_secure_storage (Keychain / KeyStore). The activation token is held
// in memory by the caller — never written to disk.
class ClientAuthService {
  static const _tokenKey = 'client_auth_token';
  static const _lastPathKey = 'last_login_path'; // 'user' | 'client'

  static String get _baseUrl => Env.apiBaseUrl; // ends in /api
  static const Duration _timeout = Duration(seconds: 15);

  // NOTE: do NOT enable `encryptedSharedPreferences: true` — on several Android
  // builds the KeyStore-backed EncryptedSharedPreferences init hangs forever
  // on first read, bricking cold-start. Default storage is still encrypted via
  // KeyStore, just without that wrapper.
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  // -------------------- Token helpers --------------------

  Future<String?> getToken() => _storage.read(key: _tokenKey);
  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);
  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Future<String?> getLastPath() => _storage.read(key: _lastPathKey);
  Future<void> setLastPath(String path) =>
      _storage.write(key: _lastPathKey, value: path);

  Future<Map<String, String>> _authHeaders([String? overrideToken]) async {
    final token = overrideToken ?? await getToken();
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Map<String, String> get _publicHeaders => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  // -------------------- Endpoints --------------------

  Future<ClientLookupResult> lookup(String email) async {
    final res = await http
        .post(
          Uri.parse('$_baseUrl/v1/client-auth/lookup'),
          headers: _publicHeaders,
          body: jsonEncode({'email': email}),
        )
        .timeout(_timeout);

    if (res.statusCode == 200) {
      return ClientLookupResult.fromJson(
          Map<String, dynamic>.from(jsonDecode(res.body)));
    }
    throw _toException(res, 'Lookup failed');
  }

  /// Sends an OTP to the client. 429 → caller should toast a wait message.
  Future<int> sendOtp(String email) async {
    final res = await http
        .post(
          Uri.parse('$_baseUrl/v1/client-auth/otp/send'),
          headers: _publicHeaders,
          body: jsonEncode({'email': email}),
        )
        .timeout(_timeout);

    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      if (body is Map && body['expires_in_min'] is num) {
        return (body['expires_in_min'] as num).toInt();
      }
      return 10;
    }
    throw _toException(res, 'Could not send code');
  }

  /// Returns the short-lived activation token (hold in memory only).
  Future<String> verifyOtp(String email, String code) async {
    final res = await http
        .post(
          Uri.parse('$_baseUrl/v1/client-auth/otp/verify'),
          headers: _publicHeaders,
          body: jsonEncode({'email': email, 'code': code}),
        )
        .timeout(_timeout);

    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      if (body is Map && body['activation_token'] is String) {
        return body['activation_token'] as String;
      }
      throw ApiException(500, 'Server returned no activation token');
    }
    if (res.statusCode == 422) {
      throw ApiException(422, 'Invalid or expired code');
    }
    throw _toException(res, 'Could not verify code');
  }

  /// Sets a fresh password using either the activation token (first time) or
  /// the long-lived session token (forced rotation). Returns the new session.
  Future<ClientLoginResponse> setPassword({
    required String bearer,
    required String password,
    required String passwordConfirmation,
    required String deviceName,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_baseUrl/v1/client-auth/password/set'),
          headers: await _authHeaders(bearer),
          body: jsonEncode({
            'password': password,
            'password_confirmation': passwordConfirmation,
            'device_name': deviceName,
          }),
        )
        .timeout(_timeout);

    if (res.statusCode == 200 || res.statusCode == 201) {
      return ClientLoginResponse.fromJson(
          Map<String, dynamic>.from(jsonDecode(res.body)));
    }
    throw _toException(res, 'Could not set password');
  }

  Future<AgentQrAgent> agentQrPreview(String slug) async {
    final res = await http
        .get(
          Uri.parse('$_baseUrl/v1/client-auth/agent-qr/$slug'),
          headers: _publicHeaders,
        )
        .timeout(_timeout);
    if (res.statusCode == 200) {
      final body = Map<String, dynamic>.from(jsonDecode(res.body));
      final raw = body['agent'] is Map ? body['agent'] : body;
      return AgentQrAgent.fromJson(Map<String, dynamic>.from(raw as Map));
    }
    throw _toException(res, 'Agent QR not found');
  }

  Future<AgentQrRegisterResponse> agentQrRegister({
    required String slug,
    required String firstName,
    required String lastName,
    required String phone,
    required String email,
    required String password,
    required String passwordConfirmation,
    required String deviceName,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_baseUrl/v1/client-auth/agent-qr/$slug/register'),
          headers: _publicHeaders,
          body: jsonEncode({
            'first_name': firstName,
            'last_name': lastName,
            if (phone.isNotEmpty) 'phone': phone,
            'email': email,
            'password': password,
            'password_confirmation': passwordConfirmation,
            'device_name': deviceName,
          }),
        )
        .timeout(_timeout);
    if (res.statusCode == 200 || res.statusCode == 201) {
      return AgentQrRegisterResponse.fromJson(
          Map<String, dynamic>.from(jsonDecode(res.body)));
    }
    throw _toException(res, 'Could not sign up');
  }

  Future<ClientLoginResponse> login({
    required String email,
    required String password,
    required String deviceName,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_baseUrl/v1/client-auth/login'),
          headers: _publicHeaders,
          body: jsonEncode({
            'email': email,
            'password': password,
            'device_name': deviceName,
          }),
        )
        .timeout(_timeout);

    if (res.statusCode == 200) {
      return ClientLoginResponse.fromJson(
          Map<String, dynamic>.from(jsonDecode(res.body)));
    }
    if (res.statusCode == 422) {
      throw ApiException(422, 'Invalid credentials');
    }
    throw _toException(res, 'Login failed');
  }

  Future<String> forgotPassword(String email) async {
    final res = await http
        .post(
          Uri.parse('$_baseUrl/v1/client-auth/password/forgot'),
          headers: _publicHeaders,
          body: jsonEncode({'email': email}),
        )
        .timeout(_timeout);

    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      if (body is Map && body['message'] is String) {
        return body['message'] as String;
      }
      return 'Code sent';
    }
    if (res.statusCode == 422) {
      // Includes the agent-managed-login case — surface the server message.
      String msg = 'Could not start recovery';
      try {
        final body = jsonDecode(res.body);
        if (body is Map && body['message'] is String) {
          msg = body['message'] as String;
        }
      } catch (_) {}
      throw ApiException(422, msg);
    }
    throw _toException(res, 'Could not start recovery');
  }

  Future<void> changePassword({
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_baseUrl/v1/client-auth/password/change'),
          headers: await _authHeaders(),
          body: jsonEncode({
            'current_password': currentPassword,
            'password': password,
            'password_confirmation': passwordConfirmation,
          }),
        )
        .timeout(_timeout);

    if (res.statusCode == 200 || res.statusCode == 204) return;
    throw _toException(res, 'Could not change password');
  }

  Future<({ClientProfile client, List<ClientAgency> agencies})> selectAgency({
    required int agencyId,
    required bool lock,
    required bool favourite,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_baseUrl/v1/client-auth/agency/select'),
          headers: await _authHeaders(),
          body: jsonEncode({
            'agency_id': agencyId,
            'lock': lock,
            'favourite': favourite,
          }),
        )
        .timeout(_timeout);

    if (res.statusCode == 200) {
      final body = Map<String, dynamic>.from(jsonDecode(res.body));
      return (
        client: ClientProfile.fromJson(
            Map<String, dynamic>.from(body['client'] as Map)),
        agencies: (body['agencies'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => ClientAgency.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
    }
    throw _toException(res, 'Could not switch agency');
  }

  Future<
      ({
        ClientProfile client,
        List<ClientAgency> agencies,
        ClientContact? contact,
        ClientAgent? agent,
      })> me() async {
    final res = await http
        .get(
          Uri.parse('$_baseUrl/v1/client/me'),
          headers: await _authHeaders(),
        )
        .timeout(_timeout);

    if (res.statusCode == 200) {
      final body = Map<String, dynamic>.from(jsonDecode(res.body));
      final contactRaw = body['contact'];
      final agentRaw = body['agent'];
      return (
        client: ClientProfile.fromJson(
            Map<String, dynamic>.from(body['client'] as Map)),
        agencies: (body['agencies'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => ClientAgency.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        contact: contactRaw is Map
            ? ClientContact.fromJson(Map<String, dynamic>.from(contactRaw))
            : null,
        agent: agentRaw is Map
            ? ClientAgent.fromJson(Map<String, dynamic>.from(agentRaw))
            : null,
      );
    }
    throw _toException(res, 'Could not load profile');
  }

  Future<({int agencyId, List<ClientMatch> matches})> matches() async {
    final res = await http
        .get(
          Uri.parse('$_baseUrl/v1/client/matches'),
          headers: await _authHeaders(),
        )
        .timeout(_timeout);

    if (res.statusCode == 200) {
      final body = Map<String, dynamic>.from(jsonDecode(res.body));
      return (
        agencyId: (body['agency_id'] as num?)?.toInt() ?? 0,
        matches: (body['matches'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => ClientMatch.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
    }
    throw _toException(res, 'Could not load matches');
  }

  // -------------------- Seller properties ("My Listings") --------------------

  /// Properties the signed-in client owns/sells in their current agency.
  Future<({int agencyId, List<SellerProperty> properties})>
      sellerProperties() async {
    final res = await http
        .get(
          Uri.parse('$_baseUrl/v1/client/seller-properties'),
          headers: await _authHeaders(),
        )
        .timeout(_timeout);

    if (res.statusCode == 200) {
      final body = Map<String, dynamic>.from(jsonDecode(res.body));
      return (
        agencyId: (body['agency_id'] as num?)?.toInt() ?? 0,
        properties: (body['properties'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => SellerProperty.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
    }
    throw _toException(res, 'Could not load listings');
  }

  /// Full seller dashboard for one listing. 404 → client isn't seller-linked.
  Future<SellerPropertyInsights> sellerPropertyInsights(int propertyId) async {
    final res = await http
        .get(
          Uri.parse('$_baseUrl/v1/client/seller-properties/$propertyId/insights'),
          headers: await _authHeaders(),
        )
        .timeout(_timeout);

    if (res.statusCode == 200) {
      return SellerPropertyInsights.fromJson(
          Map<String, dynamic>.from(jsonDecode(res.body)));
    }
    throw _toException(res, 'Could not load listing insights');
  }

  // -------------------- Client matches / properties --------------------

  Future<ClientMatchDetail> matchDetail(int matchId) async {
    final res = await http
        .get(
          Uri.parse('$_baseUrl/v1/client/matches/$matchId'),
          headers: await _authHeaders(),
        )
        .timeout(_timeout);
    if (res.statusCode == 200) {
      return ClientMatchDetail.fromJson(
          Map<String, dynamic>.from(jsonDecode(res.body)));
    }
    throw _toException(res, 'Could not load match');
  }

  Future<ClientMatch> createMatch(ClientMatchInput input) async {
    final res = await http
        .post(
          Uri.parse('$_baseUrl/v1/client/matches'),
          headers: await _authHeaders(),
          body: jsonEncode(input.toJson()),
        )
        .timeout(_timeout);
    if (res.statusCode == 200 || res.statusCode == 201) {
      final body = Map<String, dynamic>.from(jsonDecode(res.body));
      final raw = body['match'] is Map ? body['match'] : body;
      return ClientMatch.fromJson(Map<String, dynamic>.from(raw as Map));
    }
    throw _toException(res, 'Could not create match');
  }

  Future<ClientMatch> updateMatch(int matchId, ClientMatchInput input) async {
    final res = await http
        .put(
          Uri.parse('$_baseUrl/v1/client/matches/$matchId'),
          headers: await _authHeaders(),
          body: jsonEncode(input.toJson()),
        )
        .timeout(_timeout);
    if (res.statusCode == 200) {
      final body = Map<String, dynamic>.from(jsonDecode(res.body));
      final raw = body['match'] is Map ? body['match'] : body;
      return ClientMatch.fromJson(Map<String, dynamic>.from(raw as Map));
    }
    throw _toException(res, 'Could not update match');
  }

  Future<void> postFeedback({
    required int matchId,
    required int propertyId,
    required String reaction,
    String? note,
  }) async {
    final res = await http
        .post(
          Uri.parse(
              '$_baseUrl/v1/client/matches/$matchId/feedback/$propertyId'),
          headers: await _authHeaders(),
          body: jsonEncode({
            'reaction': reaction,
            if (note != null && note.isNotEmpty) 'note': note,
          }),
        )
        .timeout(_timeout);
    if (res.statusCode == 200 || res.statusCode == 201) return;
    throw _toException(res, 'Could not save feedback');
  }

  /// Fire-and-forget view ping. Errors are swallowed.
  Future<void> postView({required int matchId, required int propertyId}) async {
    try {
      await http
          .post(
            Uri.parse('$_baseUrl/v1/client/matches/$matchId/view/$propertyId'),
            headers: await _authHeaders(),
          )
          .timeout(_timeout);
    } catch (_) {}
  }

  Future<ClientPropertyDetail> property(int propertyId) async {
    final res = await http
        .get(
          Uri.parse('$_baseUrl/v1/client/properties/$propertyId'),
          headers: await _authHeaders(),
        )
        .timeout(_timeout);
    if (res.statusCode == 200) {
      final body = Map<String, dynamic>.from(jsonDecode(res.body));
      final raw = body['property'] is Map ? body['property'] : body;
      return ClientPropertyDetail.fromJson(
          Map<String, dynamic>.from(raw as Map));
    }
    throw _toException(res, 'Could not load property');
  }

  Future<ClientMatchOptions> matchOptions() async {
    final res = await http
        .get(
          Uri.parse('$_baseUrl/v1/client/match-options'),
          headers: await _authHeaders(),
        )
        .timeout(_timeout);
    if (res.statusCode == 200) {
      return ClientMatchOptions.fromJson(
          Map<String, dynamic>.from(jsonDecode(res.body)));
    }
    throw _toException(res, 'Could not load options');
  }

  // -------------------- Testimonials --------------------

  /// `POST /v1/client/testimonials`. Submits a review about the client's
  /// connected agent (the server attributes the agent automatically) and
  /// returns the freshly created, unpublished testimonial.
  ///
  /// 422 → [ValidationException] with per-field messages so the form can map
  /// them back onto the inputs. 409 (no agency selected) / 404 (no contact
  /// record) surface as plain [ApiException]s for the caller to handle.
  Future<ClientTestimonial> submitTestimonial(
      ClientTestimonialInput input) async {
    final res = await http
        .post(
          Uri.parse('$_baseUrl/v1/client/testimonials'),
          headers: await _authHeaders(),
          body: jsonEncode(input.toJson()),
        )
        .timeout(_timeout);

    if (res.statusCode == 200 || res.statusCode == 201) {
      final body = Map<String, dynamic>.from(jsonDecode(res.body));
      final raw = body['testimonial'] is Map ? body['testimonial'] : body;
      return ClientTestimonial.fromJson(Map<String, dynamic>.from(raw as Map));
    }
    if (res.statusCode == 422) throw _parseValidationError(res.body);
    throw _toException(res, 'Could not submit testimonial');
  }

  /// `GET /v1/client/testimonials` — the testimonials this client has
  /// submitted for their current agency, newest first (server-ordered).
  Future<({int agencyId, List<ClientTestimonial> testimonials})>
      testimonials() async {
    final res = await http
        .get(
          Uri.parse('$_baseUrl/v1/client/testimonials'),
          headers: await _authHeaders(),
        )
        .timeout(_timeout);

    if (res.statusCode == 200) {
      final body = Map<String, dynamic>.from(jsonDecode(res.body));
      return (
        agencyId: (body['agency_id'] as num?)?.toInt() ?? 0,
        testimonials: (body['testimonials'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => ClientTestimonial.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
    }
    throw _toException(res, 'Could not load testimonials');
  }

  // -------------------- Consent (POPIA/CPA ledger) --------------------

  /// `GET /v1/client/consent` — all 7 consent types with the client's current
  /// decision in their selected agency. Same ledger the agent edits on the web.
  Future<ClientConsentResult> consent() async {
    final res = await http
        .get(
          Uri.parse('$_baseUrl/v1/client/consent'),
          headers: await _authHeaders(),
        )
        .timeout(_timeout);
    if (res.statusCode == 200) {
      return ClientConsentResult.fromJson(
          Map<String, dynamic>.from(jsonDecode(res.body)));
    }
    throw _toException(res, 'Could not load your consent settings');
  }

  /// `POST /v1/client/consent` — record one decision. [decision] is `'given'`,
  /// `'declined'`, or `'clear'` (back to not-recorded). Returns the SAME shape
  /// as [consent] (the full refreshed list) so the caller re-renders from it.
  /// 422 → [ValidationException] (bad `type`/`decision`).
  Future<ClientConsentResult> setConsent({
    required String type,
    required String decision,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_baseUrl/v1/client/consent'),
          headers: await _authHeaders(),
          body: jsonEncode({'type': type, 'decision': decision}),
        )
        .timeout(_timeout);
    if (res.statusCode == 200 || res.statusCode == 201) {
      return ClientConsentResult.fromJson(
          Map<String, dynamic>.from(jsonDecode(res.body)));
    }
    if (res.statusCode == 422) throw _parseValidationError(res.body);
    throw _toException(res, 'Could not save your choice');
  }

  // -------------------- Property24 location cascade --------------------

  // Reuses the SAME `/mobile/p24/*` cascade the agent property-create screen
  // uses, but authenticated with the client session token instead of the agent
  // token (the agent's ApiService reads `auth_token` from SharedPreferences,
  // which a signed-in client never has — that was why the client suburb picker
  // showed "Could not load list"). The suburb `id` returned here is identical
  // to the one stored as `p24_suburb_id` on a property, so client match
  // suburbs line up with agent property suburbs.
  Future<List<P24Location>> _getP24(
      String path, Map<String, String> qp) async {
    final uri = Uri.parse('$_baseUrl/mobile/p24/$path').replace(
      queryParameters: {
        for (final e in qp.entries)
          if (e.value.isNotEmpty) e.key: e.value,
      },
    );
    final res = await http
        .get(uri, headers: await _authHeaders())
        .timeout(_timeout);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final list = (data['data'] as List?) ?? const [];
      return list
          .map((e) => P24Location.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    throw _toException(res, 'Could not load $path');
  }

  Future<List<P24Location>> getP24Provinces({String q = ''}) =>
      _getP24('provinces', {'q': q});

  Future<List<P24Location>> getP24Cities({
    required int provinceId,
    String q = '',
  }) =>
      _getP24('cities', {'province_id': '$provinceId', 'q': q});

  Future<List<P24Location>> getP24Suburbs({
    required int cityId,
    String q = '',
  }) =>
      _getP24('suburbs', {'city_id': '$cityId', 'q': q});

  Future<void> logout() async {
    final token = await getToken();
    if (token == null) return;
    try {
      await http
          .post(
            Uri.parse('$_baseUrl/v1/client-auth/logout'),
            headers: await _authHeaders(token),
          )
          .timeout(_timeout);
    } on SocketException {
      // Network down — token will be cleared locally regardless.
    } catch (_) {
      // Ignore — local sign-out must still succeed.
    }
  }

  // -------------------- Errors --------------------

  /// Parses a Laravel-style 422 body into a [ValidationException] carrying one
  /// message per field (the first message in each `errors[field]` list), so a
  /// form can surface errors inline against the matching input.
  ValidationException _parseValidationError(String body) {
    String topMessage = 'Validation failed';
    final fieldErrors = <String, String>{};
    try {
      final json = jsonDecode(body);
      if (json is Map) {
        if (json['message'] is String) topMessage = json['message'] as String;
        final errors = json['errors'];
        if (errors is Map) {
          errors.forEach((k, v) {
            if (v is List && v.isNotEmpty) {
              fieldErrors[k.toString()] = v.first.toString();
            } else if (v is String) {
              fieldErrors[k.toString()] = v;
            }
          });
        }
      }
    } catch (_) {}
    return ValidationException(topMessage, fieldErrors);
  }

  ApiException _toException(http.Response res, String fallback) {
    String message = fallback;
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['message'] is String) {
        message = body['message'] as String;
      }
    } catch (_) {}
    return ApiException(res.statusCode, message);
  }
}
