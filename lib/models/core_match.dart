class WhatsAppShare {
  final String? waLink;
  final String? phone;
  final String message;
  final String? template;
  final String rendered;
  final String? shareUrl;
  final String? contactName;
  final String? firstName;
  final int whatsappCount;

  const WhatsAppShare({
    this.waLink,
    this.phone,
    this.message = '',
    this.template,
    this.rendered = '',
    this.shareUrl,
    this.contactName,
    this.firstName,
    this.whatsappCount = 0,
  });

  factory WhatsAppShare.fromJson(Map<String, dynamic> j) {
    int n(dynamic v) => v == null ? 0 : (v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0);
    return WhatsAppShare(
      waLink: j['wa_link']?.toString(),
      phone: j['phone']?.toString(),
      message: j['message']?.toString() ?? '',
      template: j['template']?.toString(),
      rendered: j['rendered']?.toString() ?? '',
      shareUrl: j['share_url']?.toString(),
      contactName: j['contact_name']?.toString(),
      firstName: j['first_name']?.toString(),
      whatsappCount: n(j['whatsapp_count']),
    );
  }
}

class FeedbackSummary {
  final int interested;
  final int notInterested;
  final int saved;

  const FeedbackSummary({
    this.interested = 0,
    this.notInterested = 0,
    this.saved = 0,
  });

  factory FeedbackSummary.fromJson(Map<String, dynamic> j) {
    int n(dynamic v) => v == null ? 0 : (v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0);
    return FeedbackSummary(
      interested: n(j['interested']),
      notInterested: n(j['not_interested']),
      saved: n(j['saved']),
    );
  }
}

class CoreMatchContact {
  final int id;
  final String fullName;
  final String? phone;
  final String? email;
  final String? type;

  const CoreMatchContact({
    required this.id,
    required this.fullName,
    this.phone,
    this.email,
    this.type,
  });

  factory CoreMatchContact.fromJson(Map<String, dynamic> j) => CoreMatchContact(
        id: (j['id'] as num).toInt(),
        fullName: j['full_name']?.toString() ?? '',
        phone: j['phone']?.toString(),
        email: j['email']?.toString(),
        type: j['type']?.toString(),
      );
}

class CoreMatchSummary {
  final int id;
  final int contactId;
  final String? name;
  final String? status;
  final String? listingType;
  final String? category;
  final String? propertyType;
  final int? priceMin;
  final int? priceMax;
  final int? bedsMin;
  final int? bathsMin;
  final int? garagesMin;
  final String? suburb;
  // Display-only. P24-canonical names auto-synced server-side from
  // [p24SuburbIds]. Index-aligned with [p24SuburbIds]. Do not submit.
  final List<String> suburbs;
  // Source of truth for the wishlist's location filter. Submit these in
  // PUT bodies as `p24_suburb_ids`. Empty == "any suburb".
  final List<int> p24SuburbIds;
  final FeedbackSummary feedbackSummary;
  final String? updatedAt;

  const CoreMatchSummary({
    required this.id,
    required this.contactId,
    this.name,
    this.status,
    this.listingType,
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
    this.feedbackSummary = const FeedbackSummary(),
    this.updatedAt,
  });

  factory CoreMatchSummary.fromJson(Map<String, dynamic> j) {
    int? n(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse(v.toString()));
    final subs = (j['suburbs'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
    final ids = (j['p24_suburb_ids'] as List? ?? const [])
        .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()) ?? 0)
        .where((v) => v != 0)
        .toList();
    final fs = j['feedback_summary'];
    return CoreMatchSummary(
      id: (j['id'] as num).toInt(),
      contactId: (j['contact_id'] as num).toInt(),
      name: j['name']?.toString(),
      status: j['status']?.toString(),
      listingType: j['listing_type']?.toString(),
      category: j['category']?.toString(),
      propertyType: j['property_type']?.toString(),
      priceMin: n(j['price_min']),
      priceMax: n(j['price_max']),
      bedsMin: n(j['beds_min']),
      bathsMin: n(j['baths_min']),
      garagesMin: n(j['garages_min']),
      suburb: j['suburb']?.toString(),
      suburbs: subs,
      p24SuburbIds: ids,
      feedbackSummary: fs is Map
          ? FeedbackSummary.fromJson(Map<String, dynamic>.from(fs))
          : const FeedbackSummary(),
      updatedAt: j['updated_at']?.toString(),
    );
  }

  String get displayName {
    if (name != null && name!.trim().isNotEmpty) return name!;
    final lt = (listingType ?? '').toLowerCase() == 'rental' ? 'Rental' : 'Sale';
    String price = '';
    if (priceMin != null || priceMax != null) {
      final lo = priceMin == null ? '' : 'R${fmtPrice(priceMin!)}';
      final hi = priceMax == null ? '' : 'R${fmtPrice(priceMax!)}';
      price = ' $lo–$hi';
    }
    final loc = (suburb != null && suburb!.isNotEmpty)
        ? ' in $suburb'
        : (suburbs.isNotEmpty ? ' in ${suburbs.first}' : '');
    return '$lt$price$loc'.replaceAll('  ', ' ').trim();
  }

  static String fmtPrice(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }
}

class CoreMatchGroup {
  final CoreMatchContact contact;
  final List<CoreMatchSummary> matches;

  const CoreMatchGroup({required this.contact, required this.matches});

  factory CoreMatchGroup.fromJson(Map<String, dynamic> j) => CoreMatchGroup(
        contact: CoreMatchContact.fromJson(
            Map<String, dynamic>.from(j['contact'] as Map)),
        matches: (j['matches'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => CoreMatchSummary.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class CoreMatch extends CoreMatchSummary {
  final List<String> mustHaveFeatures;
  final String? notes;
  final List<int> hiddenPropertyIds;
  final Map<int, String> hiddenPropertyReasons;
  final String? shareUrl;

  const CoreMatch({
    required super.id,
    required super.contactId,
    super.name,
    super.status,
    super.listingType,
    super.category,
    super.propertyType,
    super.priceMin,
    super.priceMax,
    super.bedsMin,
    super.bathsMin,
    super.garagesMin,
    super.suburb,
    super.suburbs,
    super.p24SuburbIds,
    super.feedbackSummary,
    super.updatedAt,
    this.mustHaveFeatures = const [],
    this.notes,
    this.hiddenPropertyIds = const [],
    this.hiddenPropertyReasons = const {},
    this.shareUrl,
  });

  factory CoreMatch.fromJson(Map<String, dynamic> j) {
    final base = CoreMatchSummary.fromJson(j);
    final feats = (j['must_have_features'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
    final hidden = (j['hidden_property_ids'] as List? ?? const [])
        .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()) ?? 0)
        .where((v) => v != 0)
        .toList();
    final reasonsRaw = j['hidden_property_reasons'];
    final reasons = <int, String>{};
    if (reasonsRaw is Map) {
      reasonsRaw.forEach((k, v) {
        final id = k is num ? k.toInt() : int.tryParse(k.toString());
        if (id != null && v != null) reasons[id] = v.toString();
      });
    }
    return CoreMatch(
      id: base.id,
      contactId: base.contactId,
      name: base.name,
      status: base.status,
      listingType: base.listingType,
      category: base.category,
      propertyType: base.propertyType,
      priceMin: base.priceMin,
      priceMax: base.priceMax,
      bedsMin: base.bedsMin,
      bathsMin: base.bathsMin,
      garagesMin: base.garagesMin,
      suburb: base.suburb,
      suburbs: base.suburbs,
      p24SuburbIds: base.p24SuburbIds,
      feedbackSummary: base.feedbackSummary,
      updatedAt: base.updatedAt,
      mustHaveFeatures: feats,
      notes: j['notes']?.toString(),
      hiddenPropertyIds: hidden,
      hiddenPropertyReasons: reasons,
      shareUrl: j['share_url']?.toString(),
    );
  }
}

class CoreMatchResult {
  final int id;
  final String? address;
  final String? suburb;
  final int? beds;
  final int? baths;
  final int? garages;
  final int? price;
  final String? priceDisplay;
  final String? thumbnail;
  final bool hidden;
  final String? hiddenReason;
  final String? reaction;
  final String? reactionNote;
  // Match engine score 0–100. Null only for legacy payloads that predate
  // tiered matching.
  final int? matchScore;
  // "strong" (≥80), "good" (65–79) or "fair" (50–64). New field; null on
  // legacy payloads.
  final String? matchTier;

  const CoreMatchResult({
    required this.id,
    this.address,
    this.suburb,
    this.beds,
    this.baths,
    this.garages,
    this.price,
    this.priceDisplay,
    this.thumbnail,
    this.hidden = false,
    this.hiddenReason,
    this.reaction,
    this.reactionNote,
    this.matchScore,
    this.matchTier,
  });

  CoreMatchResult copyWith({bool? hidden, String? hiddenReason}) =>
      CoreMatchResult(
        id: id,
        address: address,
        suburb: suburb,
        beds: beds,
        baths: baths,
        garages: garages,
        price: price,
        priceDisplay: priceDisplay,
        thumbnail: thumbnail,
        hidden: hidden ?? this.hidden,
        hiddenReason: hiddenReason,
        reaction: reaction,
        reactionNote: reactionNote,
        matchScore: matchScore,
        matchTier: matchTier,
      );

  factory CoreMatchResult.fromJson(Map<String, dynamic> j) {
    int? n(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse(v.toString()));
    return CoreMatchResult(
      id: (j['id'] as num).toInt(),
      address: j['address']?.toString(),
      suburb: j['suburb']?.toString(),
      beds: n(j['beds']),
      baths: n(j['baths']),
      garages: n(j['garages']),
      price: n(j['price']),
      priceDisplay: j['price_display']?.toString(),
      thumbnail: j['thumbnail']?.toString(),
      hidden: j['hidden'] == true,
      hiddenReason: j['hidden_reason']?.toString(),
      reaction: j['reaction']?.toString(),
      reactionNote: j['reaction_note']?.toString(),
      matchScore: n(j['match_score']),
      matchTier: j['match_tier']?.toString(),
    );
  }
}

class CoreMatchScope {
  final bool allowCrossAgent;
  final bool showOtherAgents;

  const CoreMatchScope({
    this.allowCrossAgent = false,
    this.showOtherAgents = false,
  });

  factory CoreMatchScope.fromJson(Map<String, dynamic> j) => CoreMatchScope(
        allowCrossAgent: j['allow_cross_agent'] == true,
        showOtherAgents: j['show_other_agents'] == true,
      );
}

class CoreMatchDetail {
  final CoreMatch match;
  final CoreMatchContact contact;
  final List<CoreMatchResult> results;
  final CoreMatchScope scope;

  const CoreMatchDetail({
    required this.match,
    required this.contact,
    required this.results,
    this.scope = const CoreMatchScope(),
  });

  factory CoreMatchDetail.fromJson(Map<String, dynamic> j) {
    final scopeRaw = j['scope'];
    return CoreMatchDetail(
      match: CoreMatch.fromJson(Map<String, dynamic>.from(j['match'] as Map)),
      contact: CoreMatchContact.fromJson(
          Map<String, dynamic>.from(j['contact'] as Map)),
      results: (j['results'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => CoreMatchResult.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      scope: scopeRaw is Map
          ? CoreMatchScope.fromJson(Map<String, dynamic>.from(scopeRaw))
          : const CoreMatchScope(),
    );
  }
}
