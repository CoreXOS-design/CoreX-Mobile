import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/env.dart';
import 'api_service.dart';

/// Client for the AI-feature endpoints added on backend commit 9f8a9604.
///
/// These all live under `$baseUrl/v1/mobile/...`. Token is the same
/// `auth_token` SharedPreferences key that [ApiService] uses.
class AiApi {
  static String get _baseUrl => Env.apiBaseUrl;
  static const Duration _timeout = Duration(seconds: 15);
  static const Duration _voiceTimeout = Duration(seconds: 30);

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  Future<Map<String, String>> _headers({String? contentType}) async {
    final tok = await _token();
    return {
      'Accept': 'application/json',
      if (contentType != null) 'Content-Type': contentType,
      if (tok != null) 'Authorization': 'Bearer $tok',
    };
  }

  // --- Feature flags ---

  Future<MobileFeatureFlags> getFeatures() async {
    final url = '$_baseUrl/v1/mobile/features';
    final headers = await _headers();
    debugPrint('[ai_api] GET $url '
        '(auth=${headers['Authorization']?.substring(0, 16) ?? "<none>"}…)');
    final res = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(_timeout);
    debugPrint('[ai_api] ← ${res.statusCode} ${res.body}');
    if (res.statusCode == 200) {
      return MobileFeatureFlags.fromJson(
          Map<String, dynamic>.from(jsonDecode(res.body) as Map));
    }
    throw ApiException(res.statusCode, 'Failed to load mobile features');
  }

  // --- Ellie voice ---

  Future<EllieVoiceResult> sendVoice(File audio) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/v1/mobile/ellie/voice'),
    );
    req.headers.addAll(await _headers());
    req.files.add(await http.MultipartFile.fromPath('audio', audio.path));

    debugPrint('[ai_api] POST $_baseUrl/v1/mobile/ellie/voice '
        '(audio=${await audio.length()} bytes)');
    final streamed = await req.send().timeout(_voiceTimeout);
    final body = await streamed.stream.bytesToString();
    final status = streamed.statusCode;
    debugPrint('[ai_api] ← $status $body');

    Map<String, dynamic> json = const {};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) json = Map<String, dynamic>.from(decoded);
    } catch (_) {}

    if (status == 200 || status == 201) {
      return EllieVoiceResult.fromJson(json);
    }
    if (status == 403) {
      throw ApiException(403, json['error']?.toString() ?? 'Forbidden');
    }
    if (status == 422) {
      return EllieVoiceResult.fromJson(json);
    }
    throw ApiException(status, json['message']?.toString() ?? 'Ellie failed');
  }

  Future<void> undoEllieEvent(int eventId) async {
    final res = await http
        .delete(
            Uri.parse('$_baseUrl/v1/mobile/ellie/voice/events/$eventId'),
            headers: await _headers())
        .timeout(_timeout);
    if (res.statusCode == 200) return;
    String msg = 'Undo failed';
    try {
      final j = jsonDecode(res.body);
      if (j is Map && j['error'] is String) msg = j['error'] as String;
    } catch (_) {}
    throw ApiException(res.statusCode, msg);
  }

  // --- Image AI suggestions ---

  Future<AiSuggestions> getAiSuggestions(int propertyId) async {
    final res = await http
        .get(
            Uri.parse('$_baseUrl/v1/mobile/properties/$propertyId/ai-suggestions'),
            headers: await _headers())
        .timeout(_timeout);
    if (res.statusCode == 200) {
      return AiSuggestions.fromJson(
          Map<String, dynamic>.from(jsonDecode(res.body) as Map));
    }
    throw ApiException(res.statusCode, 'Failed to load AI suggestions');
  }

  Future<Map<String, dynamic>> mergeAiFeatures(
    int propertyId, {
    required List<String> confirmed,
    required List<String> rejected,
  }) async {
    final res = await http
        .post(
          Uri.parse(
              '$_baseUrl/v1/mobile/properties/$propertyId/features/merge-ai'),
          headers: await _headers(contentType: 'application/json'),
          body: jsonEncode({'confirmed': confirmed, 'rejected': rejected}),
        )
        .timeout(_timeout);
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      return body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
    }
    throw ApiException(res.statusCode, 'Failed to merge AI features');
  }
}

// ---------- Models ----------

class MobileFeatureFlags {
  final bool aiVoice;
  final bool aiImageRecognition;
  final int? agencyId;
  final int? userId;

  const MobileFeatureFlags({
    required this.aiVoice,
    required this.aiImageRecognition,
    this.agencyId,
    this.userId,
  });

  static const empty = MobileFeatureFlags(
    aiVoice: false,
    aiImageRecognition: false,
  );

  factory MobileFeatureFlags.fromJson(Map<String, dynamic> j) =>
      MobileFeatureFlags(
        aiVoice: j['ai_voice'] == true,
        aiImageRecognition: j['ai_image_recognition'] == true,
        agencyId: (j['agency_id'] is num) ? (j['agency_id'] as num).toInt() : null,
        userId: (j['user_id'] is num) ? (j['user_id'] as num).toInt() : null,
      );
}

class EllieVoiceResult {
  final String transcript;
  final String intent;
  final String? action;
  final int? eventId;
  final Map<String, dynamic>? event;
  final String message;

  const EllieVoiceResult({
    required this.transcript,
    required this.intent,
    required this.message,
    this.action,
    this.eventId,
    this.event,
  });

  bool get created => action == 'created' && eventId != null;
  bool get failed => action == 'failed';
  bool get unknown => intent == 'unknown';

  factory EllieVoiceResult.fromJson(Map<String, dynamic> j) {
    final ev = j['event'];
    final evMap = ev is Map ? Map<String, dynamic>.from(ev) : null;
    final eid = j['event_id'];
    return EllieVoiceResult(
      transcript: j['transcript']?.toString() ?? '',
      intent: j['intent']?.toString() ?? 'unknown',
      action: j['action']?.toString(),
      eventId: eid is num
          ? eid.toInt()
          : (eid is String ? int.tryParse(eid) : null),
      event: evMap,
      message: j['message']?.toString() ?? '',
    );
  }
}

class AiSuggestionToken {
  final String token;
  final double confidence;
  final int? count;
  final List<AiSuggestionSource> sources;

  const AiSuggestionToken({
    required this.token,
    required this.confidence,
    required this.sources,
    this.count,
  });

  factory AiSuggestionToken.fromJson(Map<String, dynamic> j) {
    final raw = j['sources'];
    return AiSuggestionToken(
      token: j['token']?.toString() ?? '',
      confidence: (j['confidence'] is num)
          ? (j['confidence'] as num).toDouble()
          : double.tryParse(j['confidence']?.toString() ?? '') ?? 0.0,
      count: (j['count'] is num) ? (j['count'] as num).toInt() : null,
      sources: (raw is List)
          ? raw
              .whereType<Map>()
              .map((e) =>
                  AiSuggestionSource.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

class AiSuggestionSource {
  final int? analysisId;
  final String imagePath;
  final double confidence;

  const AiSuggestionSource({
    required this.imagePath,
    required this.confidence,
    this.analysisId,
  });

  factory AiSuggestionSource.fromJson(Map<String, dynamic> j) =>
      AiSuggestionSource(
        analysisId: (j['analysis_id'] is num)
            ? (j['analysis_id'] as num).toInt()
            : null,
        imagePath: j['image_path']?.toString() ?? '',
        confidence: (j['confidence'] is num)
            ? (j['confidence'] as num).toDouble()
            : double.tryParse(j['confidence']?.toString() ?? '') ?? 0.0,
      );
}

class AiSuggestions {
  final int total;
  final int queued;
  final int processing;
  final int complete;
  final int failed;
  final List<AiSuggestionToken> features;
  final List<AiSuggestionToken> spaces;
  final Map<String, dynamic> featuresMetaCurrent;

  const AiSuggestions({
    required this.total,
    required this.queued,
    required this.processing,
    required this.complete,
    required this.failed,
    required this.features,
    required this.spaces,
    required this.featuresMetaCurrent,
  });

  bool get stillRunning => queued > 0 || processing > 0;

  static const empty = AiSuggestions(
    total: 0,
    queued: 0,
    processing: 0,
    complete: 0,
    failed: 0,
    features: [],
    spaces: [],
    featuresMetaCurrent: {},
  );

  factory AiSuggestions.fromJson(Map<String, dynamic> j) {
    List<AiSuggestionToken> parse(dynamic x) => (x is List)
        ? x
            .whereType<Map>()
            .map((e) =>
                AiSuggestionToken.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const [];
    final meta = j['features_meta_current'];
    return AiSuggestions(
      total: (j['total'] is num) ? (j['total'] as num).toInt() : 0,
      queued: (j['queued'] is num) ? (j['queued'] as num).toInt() : 0,
      processing: (j['processing'] is num) ? (j['processing'] as num).toInt() : 0,
      complete: (j['complete'] is num) ? (j['complete'] as num).toInt() : 0,
      failed: (j['failed'] is num) ? (j['failed'] as num).toInt() : 0,
      features: parse(j['features']),
      spaces: parse(j['spaces']),
      featuresMetaCurrent:
          meta is Map ? Map<String, dynamic>.from(meta) : const {},
    );
  }
}
