/// A single portal placement from the canonical `portal_links` array.
///
/// This is the portal-agnostic shape: the backend owns the ordered list and
/// any new portal simply appears as another entry. The app renders by
/// iterating — it never hardcodes or switches on [portal] to decide whether a
/// row shows. [portal] is used ONLY to pick an icon (with a generic fallback).
class PortalLink {
  /// Stable machine key (website / property24 / private_property / …).
  /// Use only to choose an icon — never to filter rows.
  final String portal;

  /// Display text. Always present.
  final String label;

  /// "live" or "not_published".
  final String status;

  /// Public page URL. Non-null only when live. Open this exact value — never
  /// build a portal URL in the app.
  final String? url;

  /// Portal listing reference (display/support). May be null.
  final String? ref;

  const PortalLink({
    required this.portal,
    required this.label,
    this.status = 'not_published',
    this.url,
    this.ref,
  });

  /// Live ⇔ a working public page exists. Treat a missing/empty url as
  /// not-openable defensively, even if status claims "live".
  bool get isLive => status == 'live' && url != null && url!.isNotEmpty;

  factory PortalLink.fromJson(Map<String, dynamic> j) {
    final rawUrl = j['url']?.toString();
    final rawRef = j['ref']?.toString();
    return PortalLink(
      portal: j['portal']?.toString() ?? '',
      label: j['label']?.toString() ?? '',
      status: j['status']?.toString() ?? 'not_published',
      url: (rawUrl == null || rawUrl.isEmpty) ? null : rawUrl,
      ref: (rawRef == null || rawRef.isEmpty) ? null : rawRef,
    );
  }

  /// Bridge a legacy [Placement] (live-only) into the portal-link shape so a
  /// response that still only returns `placements` keeps rendering.
  factory PortalLink.fromPlacement(Placement p) => PortalLink(
        portal: p.key,
        label: p.label,
        status: p.live ? 'live' : 'not_published',
        url: p.url.isEmpty ? null : p.url,
      );
}

/// DEPRECATED legacy placement shape (live-only). Kept so older responses
/// still parse; new code reads [PropertyOverview.portalLinks] instead.
class Placement {
  final String key;
  final String label;
  final String url;
  final bool live;

  const Placement({
    required this.key,
    required this.label,
    required this.url,
    required this.live,
  });

  factory Placement.fromJson(Map<String, dynamic> j) => Placement(
        key: j['key']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        url: j['url']?.toString() ?? '',
        live: j['live'] == true,
      );
}

class ContactRef {
  final int? id;
  final String name;
  final String? phone;
  final String? email;
  final String? photoUrl;

  const ContactRef({
    this.id,
    required this.name,
    this.phone,
    this.email,
    this.photoUrl,
  });

  factory ContactRef.fromJson(Map<String, dynamic> j) => ContactRef(
        id: j['id'] is int ? j['id'] as int : int.tryParse(j['id']?.toString() ?? ''),
        name: j['name']?.toString() ?? '',
        phone: j['phone']?.toString(),
        email: j['email']?.toString(),
        photoUrl: j['photo_url']?.toString(),
      );
}

class KeyDates {
  final String? listed;
  final String? expires;
  final String? loaded;
  final String? modified;

  const KeyDates({this.listed, this.expires, this.loaded, this.modified});

  factory KeyDates.fromJson(Map<String, dynamic> j) => KeyDates(
        listed: j['listed']?.toString(),
        expires: j['expires']?.toString(),
        loaded: j['loaded']?.toString(),
        modified: j['modified']?.toString(),
      );
}

class PropertyOverview {
  final int id;
  final String? title;
  final String? status;
  final String? coverImage;
  final String? suburb;
  final String? city;
  final String? priceDisplay;
  final int? daysOnMarket;
  final int? beds;
  final num? baths;
  final int? garages;
  final String? sizeM2;
  final String? erfSizeM2;
  final int? photosCount;
  final String? mandateType;
  final String? description;
  final String? livePreviewUrl;
  final String? virtualTourUrl;

  /// Canonical, ordered, portal-agnostic placement list. Render by iterating.
  final List<PortalLink> portalLinks;

  /// DEPRECATED legacy live-only list. Retained for back-compat; prefer
  /// [portalLinks].
  final List<Placement> placements;
  final ContactRef? agent;
  final ContactRef? owner;
  final KeyDates keyDates;

  const PropertyOverview({
    required this.id,
    this.title,
    this.status,
    this.coverImage,
    this.suburb,
    this.city,
    this.priceDisplay,
    this.daysOnMarket,
    this.beds,
    this.baths,
    this.garages,
    this.sizeM2,
    this.erfSizeM2,
    this.photosCount,
    this.mandateType,
    this.description,
    this.livePreviewUrl,
    this.virtualTourUrl,
    this.portalLinks = const [],
    this.placements = const [],
    this.agent,
    this.owner,
    this.keyDates = const KeyDates(),
  });

  factory PropertyOverview.fromJson(Map<String, dynamic> j) {
    int? toInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    num? toNum(dynamic v) {
      if (v == null) return null;
      if (v is num) return v;
      return num.tryParse(v.toString());
    }

    final placementsRaw = j['placements'];
    final placements = placementsRaw is List
        ? placementsRaw
            .whereType<Map>()
            .map((e) => Placement.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <Placement>[];

    // Prefer the canonical `portal_links` array (live + not_published). Fall
    // back to deriving from the deprecated `placements` (live-only) so older
    // responses still show their portals.
    final portalLinksRaw = j['portal_links'];
    final portalLinks = portalLinksRaw is List
        ? portalLinksRaw
            .whereType<Map>()
            .map((e) => PortalLink.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : placements.map(PortalLink.fromPlacement).toList();

    final agentRaw = j['agent'];
    final ownerRaw = j['owner'];
    final kdRaw = j['key_dates'];

    return PropertyOverview(
      id: toInt(j['id']) ?? 0,
      title: j['title']?.toString(),
      status: j['status']?.toString(),
      coverImage: j['cover_image']?.toString(),
      suburb: j['suburb']?.toString(),
      city: j['city']?.toString(),
      priceDisplay: j['price_display']?.toString(),
      daysOnMarket: toInt(j['days_on_market']),
      beds: toInt(j['beds']),
      baths: toNum(j['baths']),
      garages: toInt(j['garages']),
      sizeM2: j['size_m2']?.toString(),
      erfSizeM2: j['erf_size_m2']?.toString(),
      photosCount: toInt(j['photos_count'] ?? j['photos']),
      mandateType: j['mandate_type']?.toString(),
      description: j['description']?.toString(),
      livePreviewUrl: j['live_preview_url']?.toString(),
      virtualTourUrl: j['virtual_tour_url']?.toString(),
      portalLinks: portalLinks,
      placements: placements,
      agent: agentRaw is Map
          ? ContactRef.fromJson(Map<String, dynamic>.from(agentRaw))
          : null,
      owner: ownerRaw is Map
          ? ContactRef.fromJson(Map<String, dynamic>.from(ownerRaw))
          : null,
      keyDates: kdRaw is Map
          ? KeyDates.fromJson(Map<String, dynamic>.from(kdRaw))
          : const KeyDates(),
    );
  }
}
