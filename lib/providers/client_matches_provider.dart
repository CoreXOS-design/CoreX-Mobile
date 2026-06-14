import 'package:flutter/foundation.dart';

import '../models/client_models.dart';
import '../services/api_service.dart' show ApiException;
import '../services/client_auth_service.dart';

/// One matched property surfaced in the home "Matched for you" carousel,
/// tagged with the search (match) it came from so the property screen can
/// record reactions against the right match.
class MatchedListing {
  final int matchId;
  final ClientMatchResult result;
  const MatchedListing({required this.matchId, required this.result});
}

/// Loads the client's Core Match searches and aggregates their top matched
/// listings for the home-screen carousel. Hidden / "not interested" results
/// are dropped; the rest are de-duped by property and ranked by match score.
///
/// Mirrors [SellerListingsProvider]: auth/agency/server errors collapse to an
/// empty list (the Core Matches screen handles those states when opened).
class ClientMatchesProvider extends ChangeNotifier {
  final ClientAuthService _api = ClientAuthService();

  // Cap the detail fan-out so a client with many searches doesn't trigger a
  // request storm on every home open.
  static const _maxMatchesToScan = 4;
  static const _maxListings = 12;

  bool _loading = false;
  bool _loaded = false;
  bool _hasMatches = false;
  List<MatchedListing> _listings = const [];

  bool get isLoading => _loading;
  bool get loaded => _loaded;

  /// Whether the client has at least one Core Match search (regardless of
  /// whether any properties have matched it yet).
  bool get hasMatches => _hasMatches;

  /// Top matched properties across the client's searches, for the carousel.
  List<MatchedListing> get listings => _listings;

  /// Re-load matches and their top results. Safe to call on every home open;
  /// collapses concurrent calls.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      final result = await _api.matches();
      final matches = result.matches;
      _hasMatches = matches.isNotEmpty;

      // Most recently engaged searches first, then bound the fan-out.
      final ordered = [...matches]
        ..sort((a, b) => _recency(b).compareTo(_recency(a)));
      final scan = ordered.take(_maxMatchesToScan).toList();

      final details = await Future.wait(scan.map((m) async {
        try {
          final d = await _api.matchDetail(m.id);
          return (matchId: m.id, results: d.results);
        } catch (_) {
          return (matchId: m.id, results: const <ClientMatchResult>[]);
        }
      }));

      // De-dupe by property id, keeping the highest-scoring appearance.
      final byId = <int, MatchedListing>{};
      for (final d in details) {
        for (final r in d.results) {
          if (r.hidden || r.reaction == 'not_interested') continue;
          final existing = byId[r.id];
          if (existing == null ||
              (r.matchScore ?? 0) > (existing.result.matchScore ?? 0)) {
            byId[r.id] = MatchedListing(matchId: d.matchId, result: r);
          }
        }
      }
      final list = byId.values.toList()
        ..sort((a, b) =>
            (b.result.matchScore ?? 0).compareTo(a.result.matchScore ?? 0));
      _listings = list.take(_maxListings).toList();
    } on ApiException catch (e) {
      debugPrint('[client-matches] ApiException ${e.statusCode}: ${e.message}');
      _hasMatches = false;
      _listings = const [];
    } catch (e) {
      debugPrint('[client-matches] error: $e');
      _hasMatches = false;
      _listings = const [];
    }
    _loading = false;
    _loaded = true;
    notifyListeners();
  }

  /// Clear on sign-out so a different client never inherits stale matches.
  void reset() {
    _listings = const [];
    _hasMatches = false;
    _loaded = false;
    _loading = false;
    notifyListeners();
  }

  static DateTime _recency(ClientMatch m) {
    final iso = m.lastEngagedAt ?? m.updatedAt ?? m.createdAt;
    return DateTime.tryParse(iso ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }
}
