import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;

import '../models/seller_models.dart';
import '../services/api_service.dart' show ApiException;
import '../services/client_auth_service.dart';

/// Backs the conditional "My Listings" navigation entry. Probes
/// /v1/client/seller-properties so the home screen + drawer can decide whether
/// to surface the seller dashboard at all (hidden when the client owns nothing).
///
/// Auth/agency errors are swallowed into an empty list: a client with no
/// listings, an expired token, or an unselected agency all simply mean "no
/// entry" — the dedicated screens handle those states when actually opened.
class SellerListingsProvider extends ChangeNotifier {
  final ClientAuthService _api = ClientAuthService();

  bool _loading = false;
  bool _loaded = false;
  List<SellerProperty> _properties = const [];

  bool get isLoading => _loading;
  bool get loaded => _loaded;
  List<SellerProperty> get properties => _properties;
  bool get hasListings => _properties.isNotEmpty;

  /// Re-probe the list endpoint. Safe to call repeatedly (e.g. on every home
  /// open); collapses concurrent calls.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      final result = await _api.sellerProperties();
      _properties = result.properties;
      debugPrint('[seller-listings] loaded ${_properties.length} '
          'property(ies) for agency ${result.agencyId}');
    } on ApiException catch (e) {
      // 401 (token expired), 409 (no agency), or any server error → no entry.
      debugPrint('[seller-listings] ApiException ${e.statusCode}: ${e.message}');
      _properties = const [];
    } catch (e) {
      debugPrint('[seller-listings] error: $e');
      _properties = const [];
    }
    _loading = false;
    _loaded = true;
    notifyListeners();
  }

  /// Clear on sign-out so a different client never inherits stale listings.
  void reset() {
    _properties = const [];
    _loaded = false;
    _loading = false;
    notifyListeners();
  }
}
