import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../../config/app_version.dart';
import '../../config/env.dart';
import '../api_service.dart';
import '../client_auth_service.dart';

/// Who a rentals call is made as. Picks the bearer token and, for clients, the
/// `X-Portal-Role` header.
///
/// One client login can be both owner and tenant; the header makes the server
/// refuse (403 `role_mismatch`) a call that belongs to the other side, so a
/// tenant screen that ever hit an owner route by mistake fails loudly instead
/// of being handed owner data.
enum RentalsAudience {
  staff,
  tenant,
  owner;

  bool get isClient => this != RentalsAudience.staff;

  String get wire => name;

  static RentalsAudience? fromWire(String? v) {
    for (final a in RentalsAudience.values) {
      if (a.name == v) return a;
    }
    return null;
  }
}

/// A rentals call the server refused, with everything the screens and the
/// offline queue branch on.
class RentalsApiException extends ApiException {
  /// The decoded body, when it was JSON. Carries extras such as
  /// `ungraded_items`, `warnings` or `unknown` that some refusals add.
  final Map<String, dynamic> body;

  /// Laravel's 422 field errors, first message per field.
  final Map<String, String> fieldErrors;

  RentalsApiException(
    super.statusCode,
    super.message, {
    super.code,
    this.body = const {},
    this.fieldErrors = const {},
  });

  /// `0` is "never reached the server" (offline, DNS, timeout).
  bool get isNetwork => statusCode == 0;

  /// The record was withdrawn or archived while the write waited. Not an
  /// error the person can fix: the queue drops the item and says so kindly.
  bool get isArchived => statusCode == 410 || code == 'archived';

  bool get isRoleMismatch => body['role_mismatch'] == true;

  /// Worth retrying later with the same idempotency key: the server or the
  /// network failed, or the first attempt of this same write is still running
  /// (409 "still being sent").
  bool get isTransient {
    if (isNetwork || statusCode >= 500 || statusCode == 429) return true;
    if (statusCode == 409) {
      // Named conflicts are rule refusals; only the "still being sent" lock
      // (which carries no code) clears up on its own.
      return code == null && message.toLowerCase().contains('still being sent');
    }
    return false;
  }
}

/// One file part of a multipart request.
class RentalsFilePart {
  final String field;
  final String path;
  const RentalsFilePart(this.field, this.path);
}

/// Thin JSON/multipart client for every rentals endpoint, staff and client.
///
/// Paths are relative to `/api/v1` (e.g. `/mobile/fault-reports`,
/// `/client/rentals/my-lease`). Every 2xx body comes back as a map; a bare
/// list is wrapped as `{"data": [...]}` so callers have one shape to read.
class RentalsHttp {
  RentalsHttp._();
  static final RentalsHttp instance = RentalsHttp._();

  static const Duration _timeout = Duration(seconds: 20);

  /// False after a request failed to reach the server at all (no signal,
  /// timeout); true again on any reply, refusals included. The offline queue
  /// keeps retrying, so this recovers by itself. The online-only actions
  /// read it to disable themselves with a plain message.
  final ValueNotifier<bool> reachable = ValueNotifier(true);

  /// Photos go up one per request from a phone that may be on one bar of
  /// signal; the queue retries on top of this, so a slow attempt is retried
  /// rather than fatal.
  static const Duration _uploadTimeout = Duration(minutes: 5);

  final ApiService _staff = ApiService();
  final ClientAuthService _client = ClientAuthService();

  String get _base => '${Env.apiBaseUrl}/v1';

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v == null) return;
      final s = v is bool ? (v ? '1' : '0') : v.toString();
      if (s.isEmpty) return;
      q[k] = s;
    });
    final uri = Uri.parse('$_base$path');
    return q.isEmpty ? uri : uri.replace(queryParameters: q);
  }

  Future<Map<String, String>> _headers(RentalsAudience aud,
      {bool json = true, String? idempotencyKey}) async {
    final token = aud.isClient
        ? await _client.getToken()
        : await _staff.getToken();
    return {
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      'X-CoreX-App-Version': kAppVersion,
      if (token != null) 'Authorization': 'Bearer $token',
      if (aud.isClient) 'X-Portal-Role': aud.wire,
      if (idempotencyKey != null) 'X-Client-Idempotency-Key': idempotencyKey,
    };
  }

  Future<Map<String, dynamic>> get(
    RentalsAudience aud,
    String path, {
    Map<String, dynamic>? query,
  }) async {
    return _run(aud, () async {
      return http
          .get(_uri(path, query), headers: await _headers(aud))
          .timeout(_timeout);
    });
  }

  Future<Map<String, dynamic>> post(
    RentalsAudience aud,
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) =>
      _send(aud, 'POST', path, body: body, idempotencyKey: idempotencyKey);

  Future<Map<String, dynamic>> put(
    RentalsAudience aud,
    String path, {
    Map<String, dynamic>? body,
  }) =>
      _send(aud, 'PUT', path, body: body);

  Future<Map<String, dynamic>> patch(
    RentalsAudience aud,
    String path, {
    Map<String, dynamic>? body,
  }) =>
      _send(aud, 'PATCH', path, body: body);

  Future<Map<String, dynamic>> delete(RentalsAudience aud, String path,
          {Map<String, dynamic>? body}) =>
      _send(aud, 'DELETE', path, body: body);

  Future<Map<String, dynamic>> _send(
    RentalsAudience aud,
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) {
    return _run(aud, () async {
      final req = http.Request(method, _uri(path))
        ..headers.addAll(
            await _headers(aud, idempotencyKey: idempotencyKey));
      if (body != null) req.body = jsonEncode(body);
      final streamed = await req.send().timeout(_timeout);
      return http.Response.fromStream(streamed).timeout(_timeout);
    });
  }

  /// Multipart POST. [fields] values may be scalars or lists; a list `photos`
  /// is sent as repeated `photos[]` parts, which is what Laravel expects.
  Future<Map<String, dynamic>> multipart(
    RentalsAudience aud,
    String path, {
    Map<String, dynamic> fields = const {},
    List<RentalsFilePart> files = const [],
    String? idempotencyKey,
  }) {
    return _run(aud, () async {
      final req = http.MultipartRequest('POST', _uri(path))
        ..headers.addAll(await _headers(aud,
            json: false, idempotencyKey: idempotencyKey));
      fields.forEach((k, v) => _addField(req, k, v));
      for (final f in files) {
        req.files.add(await http.MultipartFile.fromPath(
          f.field,
          f.path,
          contentType: contentTypeFor(f.path),
        ));
      }
      final streamed = await req.send().timeout(_uploadTimeout);
      return http.Response.fromStream(streamed).timeout(_uploadTimeout);
    });
  }

  /// Downloads a token-protected file (portal documents, quote and invoice
  /// files are streams, not signed URLs) into [dir] and returns it.
  ///
  /// [pathOrUrl] may be what the server hands out: a relative
  /// `/api/v1/...` path, a path relative to `/api/v1`, or an absolute URL on
  /// the API host.
  Future<File> download(RentalsAudience aud, String pathOrUrl,
      {required Directory dir, required String fileName}) async {
    Uri uri;
    if (pathOrUrl.startsWith('http')) {
      uri = Uri.parse(pathOrUrl);
    } else if (pathOrUrl.startsWith('/api/v1')) {
      uri = Uri.parse('$_base${pathOrUrl.substring('/api/v1'.length)}');
    } else {
      uri = _uri(pathOrUrl);
    }
    // Only ever send the bearer to our own API host.
    if (uri.host != Uri.parse(_base).host) {
      throw RentalsApiException(403, 'That file is not on the CoreX server.');
    }
    final headers = await _headers(aud, json: false);
    final http.Response res;
    try {
      res = await http.get(uri, headers: headers).timeout(_uploadTimeout);
    } on TimeoutException {
      reachable.value = false;
      throw RentalsApiException(0, 'The download timed out.');
    } on SocketException {
      reachable.value = false;
      throw RentalsApiException(0, 'No connection right now.');
    }
    reachable.value = true;
    if (res.statusCode != 200) throw _error(res.statusCode, _decode(res.body));
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
    final f = File('${dir.path}/$safe');
    await f.writeAsBytes(res.bodyBytes, flush: true);
    return f;
  }

  static void _addField(http.MultipartRequest req, String key, dynamic v) {
    if (v == null) return;
    if (v is List) {
      for (var i = 0; i < v.length; i++) {
        _addField(req, '$key[$i]', v[i]);
      }
      return;
    }
    if (v is Map) {
      v.forEach((k, inner) => _addField(req, '$key[$k]', inner));
      return;
    }
    req.fields[key] = v is bool ? (v ? '1' : '0') : v.toString();
  }

  /// Explicit content type per extension: `MultipartFile.fromPath` otherwise
  /// sends `application/octet-stream`, which the server's image rule refuses.
  static MediaType contentTypeFor(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.png')) return MediaType('image', 'png');
    if (p.endsWith('.webp')) return MediaType('image', 'webp');
    if (p.endsWith('.heic')) return MediaType('image', 'heic');
    if (p.endsWith('.heif')) return MediaType('image', 'heif');
    if (p.endsWith('.pdf')) return MediaType('application', 'pdf');
    return MediaType('image', 'jpeg');
  }

  Future<Map<String, dynamic>> _run(
      RentalsAudience aud, Future<http.Response> Function() call) async {
    final http.Response res;
    try {
      res = await call();
    } on TimeoutException {
      reachable.value = false;
      throw RentalsApiException(
          0, 'The connection timed out. It will be tried again.');
    } on SocketException {
      reachable.value = false;
      throw RentalsApiException(0, 'No connection right now.');
    } on http.ClientException catch (e) {
      reachable.value = false;
      throw RentalsApiException(0, 'No connection right now. (${e.message})');
    }
    reachable.value = true;
    final decoded = _decode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      if (decoded is List) return {'data': decoded};
      return const {};
    }
    if (!aud.isClient && (res.statusCode == 401 || res.statusCode == 403)) {
      await _staff.handleAuthFailure(res.statusCode, res.body);
    }
    throw _error(res.statusCode, decoded);
  }

  static dynamic _decode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  static RentalsApiException _error(int status, dynamic decoded) {
    final body =
        decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    final fieldErrors = <String, String>{};
    // Laravel's `errors`, or the lease-renewal routes' `error` map.
    final errs = body['errors'] is Map ? body['errors'] : body['error'];
    if (errs is Map) {
      errs.forEach((k, v) {
        if (v is List && v.isNotEmpty) {
          fieldErrors[k.toString()] = v.first.toString();
        } else if (v != null) {
          fieldErrors[k.toString()] = v.toString();
        }
      });
    }
    var message = (body['message'] ?? '').toString().trim();
    if (message.isEmpty && fieldErrors.isNotEmpty) {
      message = fieldErrors.values.first;
    }
    if (message.isEmpty) message = _fallbackMessage(status);
    final code = body['code']?.toString();
    if (kDebugMode) debugPrint('[rentals] $status ${code ?? ''} $message');
    return RentalsApiException(status, message,
        code: code, body: body, fieldErrors: fieldErrors);
  }

  static String _fallbackMessage(int status) {
    switch (status) {
      case 401:
        return 'Please sign in again.';
      case 403:
        return 'You do not have access to this.';
      case 404:
        return 'This could not be found. It may have been removed.';
      case 410:
        return 'This has been withdrawn or archived.';
      case 422:
        return 'Please check the details and try again.';
      default:
        return status >= 500
            ? 'The server could not do this right now. It will be tried again.'
            : 'Something went wrong ($status).';
    }
  }
}
