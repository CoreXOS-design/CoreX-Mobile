import 'package:flutter/foundation.dart';
import '../services/ai_api.dart';
import '../services/api_service.dart';

/// Mobile feature flags (AI voice + image recognition). Cached for 5 minutes;
/// callers should invoke [refresh] after login / agency switch and after a
/// 403 from a gated endpoint (the flag was disabled mid-session).
class FeatureFlagsProvider extends ChangeNotifier {
  final AiApi _api = AiApi();

  MobileFeatureFlags _flags = MobileFeatureFlags.empty;
  DateTime? _fetchedAt;
  Future<void>? _inflight;

  static const _ttl = Duration(minutes: 5);

  MobileFeatureFlags get flags => _flags;
  bool get aiVoice => _flags.aiVoice;
  bool get aiImageRecognition => _flags.aiImageRecognition;

  bool get _stale =>
      _fetchedAt == null || DateTime.now().difference(_fetchedAt!) > _ttl;

  Future<void> ensureFresh() async {
    if (!_stale) return;
    return refresh();
  }

  Future<void> refresh() {
    return _inflight ??= _doRefresh().whenComplete(() => _inflight = null);
  }

  Future<void> _doRefresh() async {
    try {
      final fresh = await _api.getFeatures();
      _flags = fresh;
      _fetchedAt = DateTime.now();
      notifyListeners();
    } on ApiException catch (e) {
      debugPrint('[features] refresh failed: $e');
      // Silent — UI just won't show AI features.
    } catch (e) {
      debugPrint('[features] refresh failed: $e');
    }
  }

  /// Wipe on logout so the next user starts with a clean state.
  void reset() {
    _flags = MobileFeatureFlags.empty;
    _fetchedAt = null;
    notifyListeners();
  }
}
