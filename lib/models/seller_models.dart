// Models for the client-side "My Listings" seller dashboard.
// Wraps /api/v1/client/seller-properties and
// /api/v1/client/seller-properties/{property}/insights payloads.

/// One row in the seller's listing list. Carries just enough to render a card
/// (thumbnail, title, status, and the two headline stats).
class SellerProperty {
  final int id;
  final String? title;
  final String? address;
  final String? suburb;
  final String? role; // 'seller' | 'owner'
  final String? status;
  final num? price;
  final String? priceDisplay;
  final String? thumbnail;
  final SellerHeadline headline;

  SellerProperty({
    required this.id,
    this.title,
    this.address,
    this.suburb,
    this.role,
    this.status,
    this.price,
    this.priceDisplay,
    this.thumbnail,
    this.headline = const SellerHeadline(),
  });

  factory SellerProperty.fromJson(Map<String, dynamic> json) => SellerProperty(
        id: _asInt(json['id']) ?? 0,
        title: json['title']?.toString(),
        address: json['address']?.toString(),
        suburb: json['suburb']?.toString(),
        role: json['role']?.toString(),
        status: json['status']?.toString(),
        price: json['price'] is num ? json['price'] as num : null,
        priceDisplay: json['price_display']?.toString(),
        thumbnail: json['thumbnail']?.toString(),
        headline: SellerHeadline.fromJson(
          json['headline'] is Map
              ? Map<String, dynamic>.from(json['headline'] as Map)
              : null,
        ),
      );
}

class SellerHeadline {
  final int? viewings;
  final int? daysOnMarket;

  const SellerHeadline({this.viewings, this.daysOnMarket});

  factory SellerHeadline.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SellerHeadline();
    return SellerHeadline(
      viewings: _asInt(json['viewings']),
      daysOnMarket: _asInt(json['days_on_market']),
    );
  }
}

/// The full seller dashboard for one listing.
class SellerPropertyInsights {
  final SellerInsightProperty property;
  final String? role;
  final SellerAgency? agency;
  final SellerPerformance performance;
  final SellerFeedbackSummary feedbackSummary;
  final List<SellerAgentInsight> agentInsights;
  final List<SellerMarketingActivity> marketingActivity;
  final List<SellerComparable> comparables;
  final SellerPresentation? presentation;
  final SellerListingStatus listingStatus;
  final SellerAgent? agent;
  final String? lastRefreshedAt;

  SellerPropertyInsights({
    required this.property,
    this.role,
    this.agency,
    this.performance = const SellerPerformance(),
    this.feedbackSummary = const SellerFeedbackSummary(),
    this.agentInsights = const [],
    this.marketingActivity = const [],
    this.comparables = const [],
    this.presentation,
    this.listingStatus = const SellerListingStatus(),
    this.agent,
    this.lastRefreshedAt,
  });

  factory SellerPropertyInsights.fromJson(Map<String, dynamic> json) =>
      SellerPropertyInsights(
        property: SellerInsightProperty.fromJson(
            Map<String, dynamic>.from(json['property'] as Map)),
        role: json['role']?.toString(),
        agency: json['agency'] is Map
            ? SellerAgency.fromJson(
                Map<String, dynamic>.from(json['agency'] as Map))
            : null,
        performance: SellerPerformance.fromJson(
          json['performance'] is Map
              ? Map<String, dynamic>.from(json['performance'] as Map)
              : null,
        ),
        feedbackSummary: SellerFeedbackSummary.fromJson(
          json['feedback_summary'] is Map
              ? Map<String, dynamic>.from(json['feedback_summary'] as Map)
              : null,
        ),
        agentInsights: (json['agent_insights'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => SellerAgentInsight.fromJson(
                Map<String, dynamic>.from(e)))
            .toList(),
        marketingActivity: (json['marketing_activity'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => SellerMarketingActivity.fromJson(
                Map<String, dynamic>.from(e)))
            .toList(),
        comparables: (json['comparables'] as List? ?? const [])
            .whereType<Map>()
            .map((e) =>
                SellerComparable.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        presentation: json['presentation'] is Map
            ? SellerPresentation.fromJson(
                Map<String, dynamic>.from(json['presentation'] as Map))
            : null,
        listingStatus: SellerListingStatus.fromJson(
          json['listing_status'] is Map
              ? Map<String, dynamic>.from(json['listing_status'] as Map)
              : null,
        ),
        agent: json['agent'] is Map
            ? SellerAgent.fromJson(
                Map<String, dynamic>.from(json['agent'] as Map))
            : null,
        lastRefreshedAt: json['last_refreshed_at']?.toString(),
      );
}

class SellerInsightProperty {
  final int id;
  final String? title;
  final String? address;
  final String? suburb;
  final String? status;
  final String? listingType;
  final String? propertyType;
  final int? beds;
  final int? baths;
  final int? garages;
  final num? price;
  final String? priceDisplay;
  final String? thumbnail;
  final List<String> images;

  SellerInsightProperty({
    required this.id,
    this.title,
    this.address,
    this.suburb,
    this.status,
    this.listingType,
    this.propertyType,
    this.beds,
    this.baths,
    this.garages,
    this.price,
    this.priceDisplay,
    this.thumbnail,
    this.images = const [],
  });

  factory SellerInsightProperty.fromJson(Map<String, dynamic> json) =>
      SellerInsightProperty(
        id: _asInt(json['id']) ?? 0,
        title: json['title']?.toString(),
        address: json['address']?.toString(),
        suburb: json['suburb']?.toString(),
        status: json['status']?.toString(),
        listingType: json['listing_type']?.toString(),
        propertyType: json['property_type']?.toString(),
        beds: _asInt(json['beds']),
        baths: _asInt(json['baths']),
        garages: _asInt(json['garages']),
        price: json['price'] is num ? json['price'] as num : null,
        priceDisplay: json['price_display']?.toString(),
        thumbnail: json['thumbnail']?.toString(),
        images: (json['images'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

class SellerAgency {
  final String? name;
  final String? logoUrl;

  SellerAgency({this.name, this.logoUrl});

  factory SellerAgency.fromJson(Map<String, dynamic> json) => SellerAgency(
        name: json['name']?.toString(),
        logoUrl: json['logo_url']?.toString(),
      );
}

class SellerPerformance {
  final int? viewings;
  final int? daysOnMarket;
  final num? marketValue;
  final num? areaAverage;

  const SellerPerformance({
    this.viewings,
    this.daysOnMarket,
    this.marketValue,
    this.areaAverage,
  });

  factory SellerPerformance.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SellerPerformance();
    return SellerPerformance(
      viewings: _asInt(json['viewings']),
      daysOnMarket: _asInt(json['days_on_market']),
      marketValue:
          json['market_value'] is num ? json['market_value'] as num : null,
      areaAverage:
          json['area_average'] is num ? json['area_average'] as num : null,
    );
  }
}

class SellerFeedbackSummary {
  final int totalViewings;
  final int totalFeedbackRows;

  const SellerFeedbackSummary({
    this.totalViewings = 0,
    this.totalFeedbackRows = 0,
  });

  factory SellerFeedbackSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SellerFeedbackSummary();
    return SellerFeedbackSummary(
      totalViewings: _asInt(json['total_viewings']) ?? 0,
      totalFeedbackRows: _asInt(json['total_feedback_rows']) ?? 0,
    );
  }
}

class SellerAgentInsight {
  final String? title;
  final String? reasoning;

  SellerAgentInsight({this.title, this.reasoning});

  factory SellerAgentInsight.fromJson(Map<String, dynamic> json) =>
      SellerAgentInsight(
        title: json['title']?.toString(),
        reasoning: json['reasoning']?.toString(),
      );
}

class SellerMarketingActivity {
  final String? date;
  final String? type;
  final String? label;

  SellerMarketingActivity({this.date, this.type, this.label});

  factory SellerMarketingActivity.fromJson(Map<String, dynamic> json) =>
      SellerMarketingActivity(
        date: json['date']?.toString(),
        type: json['type']?.toString(),
        label: json['label']?.toString(),
      );
}

class SellerComparable {
  final String? title;
  final String? suburb;
  final num? price;
  final String? priceDisplay;
  final int? daysOnMarket;

  SellerComparable({
    this.title,
    this.suburb,
    this.price,
    this.priceDisplay,
    this.daysOnMarket,
  });

  factory SellerComparable.fromJson(Map<String, dynamic> json) =>
      SellerComparable(
        title: json['title']?.toString(),
        suburb: json['suburb']?.toString(),
        price: json['price'] is num ? json['price'] as num : null,
        priceDisplay: json['price_display']?.toString(),
        daysOnMarket: _asInt(json['days_on_market']),
      );
}

class SellerPresentation {
  final String? title;
  final String? generatedAt;

  SellerPresentation({this.title, this.generatedAt});

  factory SellerPresentation.fromJson(Map<String, dynamic> json) =>
      SellerPresentation(
        title: json['title']?.toString(),
        generatedAt: json['generated_at']?.toString(),
      );
}

class SellerListingStatus {
  final bool published;
  final bool mandateActive;

  const SellerListingStatus({
    this.published = false,
    this.mandateActive = false,
  });

  factory SellerListingStatus.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SellerListingStatus();
    return SellerListingStatus(
      published: json['published'] == true,
      mandateActive: json['mandate_active'] == true,
    );
  }
}

class SellerAgent {
  final String? name;
  final String? email;
  final String? phone;

  SellerAgent({this.name, this.email, this.phone});

  factory SellerAgent.fromJson(Map<String, dynamic> json) => SellerAgent(
        name: json['name']?.toString(),
        email: json['email']?.toString(),
        phone: json['phone']?.toString(),
      );
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}
