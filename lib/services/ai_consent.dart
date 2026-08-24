import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the user has agreed to CoreX sending their data to its AI provider.
///
/// App Store guidelines 5.1.1(i) / 5.1.2(i): permission must be obtained
/// *before* personal data reaches a third-party AI service, not disclosed
/// afterwards. This is the one flag both AI surfaces check.
///
/// [unknown] is the pre-answer state and is deliberately distinct from
/// [declined] — the UI offers on first use, and must not read a fresh install
/// as a refusal (or a refusal as "ask again next time").
enum AiConsentState { unknown, granted, declined }

/// Single source of truth for AI consent.
///
/// **Scope of what this can actually enforce.** Ellie voice is fully gated
/// here: the app decides whether to POST the audio at all, so withholding
/// consent genuinely prevents the send. Property photos are not — the server
/// dispatches `AnalysePropertyImageJob` on upload, so by the time any panel in
/// the app could refuse, the image has already gone. The upload call therefore
/// sends an `ai_analysis` field carrying this flag, and the backend must honour
/// it for the photo half of this promise to be true. See the note in
/// [ApiService.uploadPropertyImage].
///
/// **Storage.** Plain [SharedPreferences], not the secure vault: this is a
/// preference, not a secret, and the vault has a documented history of silently
/// dropping writes on some Android builds — a consent flag that fails to
/// persist would re-prompt forever or, far worse, read as granted when it
/// wasn't.
///
/// **Lifetime.** Cleared on sign-out ([AuthProvider.logout]) rather than keyed
/// per user id. Agents share devices; the next person to sign in must answer
/// for themselves rather than inherit a colleague's agreement. The cost is that
/// signing out and back in asks again, which is the safe direction to err.
///
/// **Swapping in a server flag.** Only [_read] and [_write] touch storage.
/// Point them at a `GET/PUT /v1/me/ai-consent` pair (the `/v1/me/theme` shape)
/// and consent follows the user across devices, with the server able to refuse
/// the AI call itself — which is what makes the guarantee real rather than
/// client-side politeness.
class AiConsent extends ChangeNotifier {
  AiConsent._();
  static final AiConsent instance = AiConsent._();

  static const String _key = 'ai_consent_v1';

  AiConsentState _state = AiConsentState.unknown;
  bool _loaded = false;

  AiConsentState get state => _state;

  /// True only on an explicit yes. [AiConsentState.unknown] is not consent.
  bool get granted => _state == AiConsentState.granted;

  /// Reads the stored answer once per process. Safe to call repeatedly.
  Future<AiConsentState> ensureLoaded() async {
    if (_loaded) return _state;
    _state = await _read();
    _loaded = true;
    notifyListeners();
    return _state;
  }

  /// Records the user's answer. [granted] false stores an explicit refusal, so
  /// the sheet isn't shown again unprompted — Settings is where they change it.
  Future<void> set(bool granted) async {
    _state = granted ? AiConsentState.granted : AiConsentState.declined;
    _loaded = true;
    await _write(_state);
    debugPrint('[ai-consent] set to $_state');
    notifyListeners();
  }

  /// Back to [AiConsentState.unknown] — the next AI surface will ask again.
  /// Called on sign-out.
  Future<void> clear() async {
    _state = AiConsentState.unknown;
    _loaded = true;
    await _write(_state);
    notifyListeners();
  }

  // --- storage seam -------------------------------------------------------

  Future<AiConsentState> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getBool(_key);
      if (value == null) return AiConsentState.unknown;
      return value ? AiConsentState.granted : AiConsentState.declined;
    } catch (e) {
      // Unreadable storage must never fail open — an unanswered prompt is a
      // recoverable annoyance, sending data the user never agreed to is not.
      debugPrint('[ai-consent] read failed ($e) — treating as unanswered');
      return AiConsentState.unknown;
    }
  }

  Future<void> _write(AiConsentState state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (state == AiConsentState.unknown) {
        await prefs.remove(_key);
      } else {
        await prefs.setBool(_key, state == AiConsentState.granted);
      }
    } catch (e) {
      debugPrint('[ai-consent] write failed: $e');
    }
  }
}
