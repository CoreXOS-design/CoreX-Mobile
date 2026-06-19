// Models for the Client-side auth + portal flow.
// Wraps /api/v1/client-auth/* and /api/v1/client/* payloads.

class ClientLookupResult {
  final bool exists;
  final bool requiresOtp;
  final bool requiresPassword;
  final bool mustChangePassword;
  final String? message;
  final List<ClientAgency> agencies;

  ClientLookupResult({
    required this.exists,
    required this.requiresOtp,
    required this.requiresPassword,
    required this.mustChangePassword,
    this.message,
    required this.agencies,
  });

  factory ClientLookupResult.fromJson(Map<String, dynamic> json) =>
      ClientLookupResult(
        exists: json['exists'] == true,
        requiresOtp: json['requires_otp'] == true,
        requiresPassword: json['requires_password'] == true,
        mustChangePassword: json['must_change_password'] == true,
        message: json['message']?.toString(),
        agencies: (json['agencies'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => ClientAgency.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class ClientAgency {
  final int id;
  final String name;
  final String slug;
  final bool isPreferred;
  final bool isLocked;

  ClientAgency({
    required this.id,
    required this.name,
    required this.slug,
    this.isPreferred = false,
    this.isLocked = false,
  });

  factory ClientAgency.fromJson(Map<String, dynamic> json) => ClientAgency(
        id: (json['id'] as num).toInt(),
        name: json['name']?.toString() ?? '',
        slug: json['slug']?.toString() ?? '',
        isPreferred: json['is_preferred'] == true,
        isLocked: json['is_locked'] == true,
      );
}

class ClientProfile {
  final int id;
  final String email;
  final bool hasPassword;
  final bool passwordMustChange;
  final int? preferredAgencyId;
  final int? lockedToAgencyId;
  final int? currentAgencyId;
  final String? lastLoginAt;

  ClientProfile({
    required this.id,
    required this.email,
    required this.hasPassword,
    required this.passwordMustChange,
    this.preferredAgencyId,
    this.lockedToAgencyId,
    this.currentAgencyId,
    this.lastLoginAt,
  });

  factory ClientProfile.fromJson(Map<String, dynamic> json) => ClientProfile(
        id: (json['id'] as num).toInt(),
        email: json['email']?.toString() ?? '',
        hasPassword: json['has_password'] == true,
        passwordMustChange: json['password_must_change'] == true,
        preferredAgencyId: _asInt(json['preferred_agency_id']),
        lockedToAgencyId: _asInt(json['locked_to_agency_id']),
        currentAgencyId: _asInt(json['current_agency_id']),
        lastLoginAt: json['last_login_at']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'has_password': hasPassword,
        'password_must_change': passwordMustChange,
        'preferred_agency_id': preferredAgencyId,
        'locked_to_agency_id': lockedToAgencyId,
        'current_agency_id': currentAgencyId,
        'last_login_at': lastLoginAt,
      };
}

class ClientContact {
  final int id;
  final String? firstName;
  final String? lastName;
  final String fullName;
  final String? email;
  final String? phone;
  final int? agencyId;

  ClientContact({
    required this.id,
    this.firstName,
    this.lastName,
    required this.fullName,
    this.email,
    this.phone,
    this.agencyId,
  });

  factory ClientContact.fromJson(Map<String, dynamic> json) {
    final first = json['first_name']?.toString().trim() ?? '';
    final last = json['last_name']?.toString().trim() ?? '';
    final full = json['full_name']?.toString().trim() ?? '';
    // Prefer the server-composed name, but fall back to first + last so a
    // payload that only carries the parts still yields a usable name.
    final resolved =
        full.isNotEmpty ? full : [first, last].where((s) => s.isNotEmpty).join(' ');
    return ClientContact(
      id: (json['id'] as num).toInt(),
      firstName: first.isEmpty ? null : first,
      lastName: last.isEmpty ? null : last,
      fullName: resolved,
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      agencyId: _asInt(json['agency_id']),
    );
  }
}

/// The client's assigned agent for their current agency, surfaced on
/// `/v1/client/me` so the home screen can show a contact card. Optional —
/// older payloads (or clients with no assigned agent) omit it.
class ClientAgent {
  final int? id;
  final String fullName;
  final String? title;
  final String? phone;
  final String? whatsapp;
  final String? email;
  final String? photoUrl;
  final String? agencyName;

  ClientAgent({
    this.id,
    required this.fullName,
    this.title,
    this.phone,
    this.whatsapp,
    this.email,
    this.photoUrl,
    this.agencyName,
  });

  bool get hasContact =>
      (phone != null && phone!.isNotEmpty) ||
      (whatsapp != null && whatsapp!.isNotEmpty) ||
      (email != null && email!.isNotEmpty);

  factory ClientAgent.fromJson(Map<String, dynamic> json) {
    final first = json['first_name']?.toString().trim() ?? '';
    final last = json['last_name']?.toString().trim() ?? '';
    final full = json['full_name']?.toString().trim() ?? '';
    final resolved = full.isNotEmpty
        ? full
        : [first, last].where((s) => s.isNotEmpty).join(' ');
    // Backends vary on the phone key — accept the common aliases so the Call
    // button shows up regardless of which one the API uses.
    final phone = _firstNonEmpty(json, const [
      'phone',
      'mobile',
      'cell',
      'cell_number',
      'phone_number',
      'contact_number',
      'telephone',
    ]);
    // A dedicated WhatsApp number is rare; default to the phone number, which
    // is what agents almost always use for WhatsApp anyway.
    final whatsapp = _firstNonEmpty(json, const [
          'whatsapp',
          'whatsapp_number',
          'wa_number',
        ]) ??
        phone;
    return ClientAgent(
      id: _asInt(json['id']),
      fullName: resolved,
      title: json['title']?.toString(),
      phone: phone,
      whatsapp: whatsapp,
      email: _firstNonEmpty(json, const ['email', 'email_address']),
      photoUrl: _firstNonEmpty(json, const ['photo_url', 'photo', 'avatar_url']),
      agencyName: json['agency_name']?.toString(),
    );
  }
}

/// Returns the first non-empty string value among [keys], or null if none.
String? _firstNonEmpty(Map<String, dynamic> json, List<String> keys) {
  for (final k in keys) {
    final v = json[k]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}

class ClientLoginResponse {
  final String token;
  final List<ClientAgency> agencies;
  final ClientProfile client;

  ClientLoginResponse({
    required this.token,
    required this.agencies,
    required this.client,
  });

  factory ClientLoginResponse.fromJson(Map<String, dynamic> json) =>
      ClientLoginResponse(
        token: json['token']?.toString() ?? '',
        agencies: (json['agencies'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => ClientAgency.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        client: ClientProfile.fromJson(
            Map<String, dynamic>.from(json['client'] as Map)),
      );
}

class ClientFeedbackSummary {
  final int interested;
  final int notInterested;
  final int saved;

  const ClientFeedbackSummary({
    this.interested = 0,
    this.notInterested = 0,
    this.saved = 0,
  });

  factory ClientFeedbackSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ClientFeedbackSummary();
    return ClientFeedbackSummary(
      interested: _asInt(json['interested']) ?? 0,
      notInterested: _asInt(json['not_interested']) ?? 0,
      saved: _asInt(json['saved']) ?? 0,
    );
  }
}

class ClientMatch {
  final int id;
  final String? name;
  final String status;
  final String? listingType;
  final String? createdAt;
  final String? updatedAt;
  final String? lastEngagedAt;
  final ClientFeedbackSummary feedbackSummary;

  // Filter fields (present on detail; mostly null on list)
  final String? category;
  final String? propertyType;
  final num? priceMin;
  final num? priceMax;
  final int? bedsMin;
  final int? bathsMin;
  final int? garagesMin;
  final String? suburb;
  // Display-only P24-canonical names, index-aligned with [p24SuburbIds].
  final List<String> suburbs;
  // Source of truth for the wishlist's location filter.
  final List<int> p24SuburbIds;
  final List<String> mustHaveFeatures;
  final String? notes;

  ClientMatch({
    required this.id,
    this.name,
    required this.status,
    this.listingType,
    this.createdAt,
    this.updatedAt,
    this.lastEngagedAt,
    this.feedbackSummary = const ClientFeedbackSummary(),
    this.category,
    this.propertyType,
    this.priceMin,
    this.priceMax,
    this.bedsMin,
    this.bathsMin,
    this.garagesMin,
    this.suburb,
    this.suburbs = const [],
    this.p24SuburbIds = const [],
    this.mustHaveFeatures = const [],
    this.notes,
  });

  factory ClientMatch.fromJson(Map<String, dynamic> json) => ClientMatch(
        id: (json['id'] as num).toInt(),
        name: json['name']?.toString(),
        status: json['status']?.toString() ?? '',
        listingType: json['listing_type']?.toString(),
        createdAt: json['created_at']?.toString(),
        updatedAt: json['updated_at']?.toString(),
        lastEngagedAt: json['last_engaged_at']?.toString(),
        feedbackSummary: ClientFeedbackSummary.fromJson(
          json['feedback_summary'] is Map
              ? Map<String, dynamic>.from(json['feedback_summary'] as Map)
              : null,
        ),
        category: json['category']?.toString(),
        propertyType: json['property_type']?.toString(),
        priceMin: json['price_min'] is num ? json['price_min'] as num : null,
        priceMax: json['price_max'] is num ? json['price_max'] as num : null,
        bedsMin: _asInt(json['beds_min']),
        bathsMin: _asInt(json['baths_min']),
        garagesMin: _asInt(json['garages_min']),
        suburb: json['suburb']?.toString(),
        suburbs: (json['suburbs'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        p24SuburbIds: (json['p24_suburb_ids'] as List? ?? const [])
            .map((e) =>
                e is num ? e.toInt() : int.tryParse(e.toString()) ?? 0)
            .where((v) => v != 0)
            .toList(),
        mustHaveFeatures: (json['must_have_features'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        notes: json['notes']?.toString(),
      );
}

class ClientMatchResult {
  final int id;
  final String address;
  final String? suburb;
  final int? beds;
  final int? baths;
  final int? garages;
  final num? price;
  final String? priceDisplay;
  final String? thumbnail;
  final int? matchScore;
  final bool hidden;
  final String? reaction; // 'interested' | 'not_interested' | 'saved' | null
  final String? reactionNote;

  ClientMatchResult({
    required this.id,
    required this.address,
    this.suburb,
    this.beds,
    this.baths,
    this.garages,
    this.price,
    this.priceDisplay,
    this.thumbnail,
    this.matchScore,
    this.hidden = false,
    this.reaction,
    this.reactionNote,
  });

  ClientMatchResult copyWith({
    String? reaction,
    String? reactionNote,
    bool clearReactionNote = false,
  }) =>
      ClientMatchResult(
        id: id,
        address: address,
        suburb: suburb,
        beds: beds,
        baths: baths,
        garages: garages,
        price: price,
        priceDisplay: priceDisplay,
        thumbnail: thumbnail,
        matchScore: matchScore,
        hidden: hidden,
        reaction: reaction ?? this.reaction,
        reactionNote:
            clearReactionNote ? null : (reactionNote ?? this.reactionNote),
      );

  factory ClientMatchResult.fromJson(Map<String, dynamic> json) =>
      ClientMatchResult(
        id: (json['id'] as num).toInt(),
        address: json['address']?.toString() ?? '',
        suburb: json['suburb']?.toString(),
        beds: _asInt(json['beds']),
        baths: _asInt(json['baths']),
        garages: _asInt(json['garages']),
        price: json['price'] is num ? json['price'] as num : null,
        priceDisplay: json['price_display']?.toString(),
        thumbnail: json['thumbnail']?.toString(),
        matchScore: _asInt(json['match_score']),
        hidden: json['hidden'] == true,
        reaction: json['reaction']?.toString(),
        reactionNote: json['reaction_note']?.toString(),
      );
}

class ClientMatchDetail {
  final ClientMatch match;
  final List<ClientMatchResult> results;

  ClientMatchDetail({required this.match, required this.results});

  factory ClientMatchDetail.fromJson(Map<String, dynamic> json) =>
      ClientMatchDetail(
        match: ClientMatch.fromJson(
            Map<String, dynamic>.from(json['match'] as Map)),
        results: (json['results'] as List? ?? const [])
            .whereType<Map>()
            .map((e) =>
                ClientMatchResult.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class ClientPropertyAgent {
  final String? name;
  final String? phone;
  final String? email;
  ClientPropertyAgent({this.name, this.phone, this.email});
  factory ClientPropertyAgent.fromJson(Map<String, dynamic> json) =>
      ClientPropertyAgent(
        name: json['name']?.toString(),
        phone: json['phone']?.toString(),
        email: json['email']?.toString(),
      );
}

class ClientPropertyDetail {
  final int id;
  final String? title;
  final String? address;
  final String? suburb;
  final int? beds;
  final int? baths;
  final int? garages;
  final int? parking;
  final num? floorSize;
  final num? erfSize;
  final String? propertyType;
  final String? category;
  final String? listingType;
  final String? status;
  final num? price;
  final String? priceDisplay;
  final String? description;
  final List<String> features;
  final List<String> images;
  final String? thumbnail;
  final ClientPropertyAgent? agent;
  final String? branch;
  final String? webPreviewUrl;

  ClientPropertyDetail({
    required this.id,
    this.title,
    this.address,
    this.suburb,
    this.beds,
    this.baths,
    this.garages,
    this.parking,
    this.floorSize,
    this.erfSize,
    this.propertyType,
    this.category,
    this.listingType,
    this.status,
    this.price,
    this.priceDisplay,
    this.description,
    this.features = const [],
    this.images = const [],
    this.thumbnail,
    this.agent,
    this.branch,
    this.webPreviewUrl,
  });

  factory ClientPropertyDetail.fromJson(Map<String, dynamic> json) =>
      ClientPropertyDetail(
        id: (json['id'] as num).toInt(),
        title: json['title']?.toString(),
        address: json['address']?.toString(),
        suburb: json['suburb']?.toString(),
        beds: _asInt(json['beds']),
        baths: _asInt(json['baths']),
        garages: _asInt(json['garages']),
        parking: _asInt(json['parking']),
        floorSize: json['floor_size'] is num ? json['floor_size'] as num : null,
        erfSize: json['erf_size'] is num ? json['erf_size'] as num : null,
        propertyType: json['property_type']?.toString(),
        category: json['category']?.toString(),
        listingType: json['listing_type']?.toString(),
        status: json['status']?.toString(),
        price: json['price'] is num ? json['price'] as num : null,
        priceDisplay: json['price_display']?.toString(),
        description: json['description']?.toString(),
        features: (json['features'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        images: (json['images'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        thumbnail: json['thumbnail']?.toString(),
        agent: json['agent'] is Map
            ? ClientPropertyAgent.fromJson(
                Map<String, dynamic>.from(json['agent'] as Map))
            : null,
        branch: json['branch']?.toString(),
        webPreviewUrl: json['web_preview_url']?.toString(),
      );
}

class ClientMatchOptions {
  final List<String> listingTypes;
  final List<String> propertyTypes;
  final List<String> categories;
  final List<String> suburbs;

  ClientMatchOptions({
    this.listingTypes = const [],
    this.propertyTypes = const [],
    this.categories = const [],
    this.suburbs = const [],
  });

  factory ClientMatchOptions.fromJson(Map<String, dynamic> json) =>
      ClientMatchOptions(
        listingTypes: (json['listing_types'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        propertyTypes: (json['property_types'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        categories: (json['categories'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        suburbs: (json['suburbs'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

class ClientMatchInput {
  final String? name;
  final String? listingType;
  final String? category;
  final String? propertyType;
  final num? priceMin;
  final num? priceMax;
  final int? bedsMin;
  final int? bathsMin;
  final int? garagesMin;
  // P24 suburb IDs — source of truth. Empty == "any suburb".
  // The validator rejects `suburb` / `suburbs` on write, so we only send IDs.
  final List<int> p24SuburbIds;
  final List<String> mustHaveFeatures;
  final String? notes;

  const ClientMatchInput({
    this.name,
    this.listingType,
    this.category,
    this.propertyType,
    this.priceMin,
    this.priceMax,
    this.bedsMin,
    this.bathsMin,
    this.garagesMin,
    this.p24SuburbIds = const [],
    this.mustHaveFeatures = const [],
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (listingType != null) 'listing_type': listingType,
        if (category != null) 'category': category,
        if (propertyType != null) 'property_type': propertyType,
        if (priceMin != null) 'price_min': priceMin,
        if (priceMax != null) 'price_max': priceMax,
        if (bedsMin != null) 'beds_min': bedsMin,
        if (bathsMin != null) 'baths_min': bathsMin,
        if (garagesMin != null) 'garages_min': garagesMin,
        'p24_suburb_ids': p24SuburbIds,
        'must_have_features': mustHaveFeatures,
        if (notes != null) 'notes': notes,
      };
}

/// A testimonial the signed-in client has written about their connected agent.
/// Created unpublished — the agency curates what goes public, so [published]
/// stays false until they flip it live on the website. The app must never
/// imply it's instantly public.
class ClientTestimonial {
  final int id;
  final String body;
  final int? rating; // 1–5, optional
  final String? displayName;
  final bool published;
  final String? createdAt;

  ClientTestimonial({
    required this.id,
    required this.body,
    this.rating,
    this.displayName,
    this.published = false,
    this.createdAt,
  });

  factory ClientTestimonial.fromJson(Map<String, dynamic> json) =>
      ClientTestimonial(
        id: (json['id'] as num).toInt(),
        body: json['body']?.toString() ?? '',
        rating: _asInt(json['rating']),
        displayName: json['display_name']?.toString(),
        published: json['published'] == true,
        createdAt: json['created_at']?.toString(),
      );
}

/// Write payload for `POST /v1/client/testimonials`. The client never sets the
/// agent — the server attributes it to the connected agent automatically, so
/// this only carries the review text, an optional rating and display name.
class ClientTestimonialInput {
  final String body;
  final int? rating;
  final String? displayName;

  const ClientTestimonialInput({
    required this.body,
    this.rating,
    this.displayName,
  });

  Map<String, dynamic> toJson() => {
        'body': body,
        if (rating != null) 'rating': rating,
        if (displayName != null && displayName!.isNotEmpty)
          'display_name': displayName,
      };
}

/// One row in the client-facing POPIA/CPA consent ledger — the SAME ledger the
/// agent sees on the web, so a change here is instantly visible to them and
/// vice versa. [group] sections the UI ("channel" | "marketing" |
/// "compliance"); [decision] is "given" | "declined" | null (not yet recorded).
class ClientConsent {
  final String type;
  final String label;
  final String group;
  final String? decision;
  final String? recordedAt;

  const ClientConsent({
    required this.type,
    required this.label,
    required this.group,
    this.decision,
    this.recordedAt,
  });

  bool get isGiven => decision == 'given';
  bool get isDeclined => decision == 'declined';
  bool get isSet => isGiven || isDeclined;

  factory ClientConsent.fromJson(Map<String, dynamic> json) {
    final raw = json['decision']?.toString();
    return ClientConsent(
      type: json['type']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      group: json['group']?.toString() ?? '',
      // Anything other than the two known states is treated as "not recorded".
      decision: (raw == 'given' || raw == 'declined') ? raw : null,
      recordedAt: json['recorded_at']?.toString(),
    );
  }

  /// Local optimistic copy. [decision] of `'clear'`/null and [clearMeta] both
  /// reset to not-recorded; the server response replaces this either way.
  ClientConsent copyWith({String? decision, String? recordedAt}) {
    final next = decision == 'clear' ? null : (decision ?? this.decision);
    return ClientConsent(
      type: type,
      label: label,
      group: group,
      decision: next,
      recordedAt: next == null ? null : (recordedAt ?? this.recordedAt),
    );
  }
}

class ClientConsentResult {
  final int agencyId;
  final List<ClientConsent> consents;

  const ClientConsentResult({required this.agencyId, required this.consents});

  factory ClientConsentResult.fromJson(Map<String, dynamic> json) =>
      ClientConsentResult(
        agencyId: _asInt(json['agency_id']) ?? 0,
        consents: (json['consents'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => ClientConsent.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class AgentQrAgency {
  final int id;
  final String name;
  final String slug;
  AgentQrAgency({required this.id, required this.name, required this.slug});
  factory AgentQrAgency.fromJson(Map<String, dynamic> json) => AgentQrAgency(
        id: (json['id'] as num).toInt(),
        name: json['name']?.toString() ?? '',
        slug: json['slug']?.toString() ?? '',
      );
}

class AgentQrAgent {
  final String firstName;
  final String lastName;
  final String fullName;
  final String? photoUrl;
  final AgentQrAgency? agency;

  AgentQrAgent({
    required this.firstName,
    required this.lastName,
    required this.fullName,
    this.photoUrl,
    this.agency,
  });

  factory AgentQrAgent.fromJson(Map<String, dynamic> json) => AgentQrAgent(
        firstName: json['first_name']?.toString() ?? '',
        lastName: json['last_name']?.toString() ?? '',
        fullName: json['full_name']?.toString() ?? '',
        photoUrl: json['photo_url']?.toString(),
        agency: json['agency'] is Map
            ? AgentQrAgency.fromJson(
                Map<String, dynamic>.from(json['agency'] as Map))
            : null,
      );
}

class AgentQrRegisterResponse {
  final bool existing;

  /// When true, the email already belongs to a client in this agent's agency.
  /// The server has linked them to the agent but withheld a session token —
  /// the app must verify ownership via OTP → set-password before sign-in.
  final bool requiresVerification;

  /// The verification channel the server expects (currently always 'otp').
  final String? verification;

  /// Session token. Empty when [requiresVerification] is true.
  final String token;
  final String? message;
  final AgentQrAgent agent;
  final AgentQrAgency? agency;

  AgentQrRegisterResponse({
    required this.existing,
    this.requiresVerification = false,
    this.verification,
    required this.token,
    this.message,
    required this.agent,
    this.agency,
  });

  factory AgentQrRegisterResponse.fromJson(Map<String, dynamic> json) =>
      AgentQrRegisterResponse(
        existing: json['existing'] == true,
        requiresVerification: json['requires_verification'] == true,
        verification: json['verification']?.toString(),
        token: json['token']?.toString() ?? '',
        message: json['message']?.toString(),
        agent: AgentQrAgent.fromJson(
            Map<String, dynamic>.from(json['agent'] as Map)),
        agency: json['agency'] is Map
            ? AgentQrAgency.fromJson(
                Map<String, dynamic>.from(json['agency'] as Map))
            : null,
      );
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}
