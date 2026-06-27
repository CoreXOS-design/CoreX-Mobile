class Property {
  final int id;
  final String address;
  final String? title;
  final int? beds;
  final num? baths;
  final int? garages;
  final String? status;
  final String? propertyType;
  final String? category;
  final String? listingType;
  final int? price;
  final String? priceDisplay;
  final String? thumbnail;
  final String? updatedAt;
  /// Primary / lead agent id for this listing. When this differs from the
  /// logged-in user's id, the user is a co-listing (secondary) agent — the
  /// API already scoped the list, so we only render this, never filter on it.
  final int? agentId;
  // Detail-only fields
  final String? streetNumber;
  final String? streetName;
  final String? suburb;
  final String? city;
  final String? province;
  final String? region;
  final String? district;
  // Property24 cascade ids — drive the create/edit location picker. The
  // human-readable suburb/city/province strings above stay authoritative
  // for read-only display everywhere else.
  final int? p24ProvinceId;
  final int? p24CityId;
  final int? p24SuburbId;
  /// True when the stored suburb string can't be matched to a P24 suburb
  /// (legacy / hand-typed). The form opens the suburb picker empty so the
  /// agent can pick a real one.
  final bool p24SuburbMismatch;
  final String? complexName;
  final String? unitNumber;
  final String? sizeM2;
  final String? erfSizeM2;
  final String? mandateType;
  final String? excerpt;
  final String? description;
  // Rental fields — only used when listingType == 'rental'
  final int? rentalAmount;
  final int? depositAmount;
  final String? leaseStartDate;
  final String? leaseEndDate;
  // Commission / fees
  final num? commissionPercent;
  final num? adminFee;
  final num? marketingFee;
  final List<String> features;
  final List<String> galleryImages;
  final Map<String, dynamic>? galleryCategories;
  /// Ordered list of tags currently valid on this property (derived from
  /// the spaces the agent has added). Mirrors `/gallery/tags`'s
  /// `available_tags` so the detail screen can render gallery groups
  /// without an extra round-trip.
  final List<String> galleryTags;

  Property({
    required this.id,
    required this.address,
    this.title,
    this.beds,
    this.baths,
    this.garages,
    this.status,
    this.propertyType,
    this.category,
    this.listingType,
    this.price,
    this.priceDisplay,
    this.thumbnail,
    this.updatedAt,
    this.agentId,
    this.streetNumber,
    this.streetName,
    this.suburb,
    this.city,
    this.province,
    this.region,
    this.district,
    this.p24ProvinceId,
    this.p24CityId,
    this.p24SuburbId,
    this.p24SuburbMismatch = false,
    this.complexName,
    this.unitNumber,
    this.sizeM2,
    this.erfSizeM2,
    this.mandateType,
    this.excerpt,
    this.description,
    this.rentalAmount,
    this.depositAmount,
    this.leaseStartDate,
    this.leaseEndDate,
    this.commissionPercent,
    this.adminFee,
    this.marketingFee,
    this.features = const [],
    this.galleryImages = const [],
    this.galleryCategories,
    this.galleryTags = const [],
  });

  factory Property.fromJson(Map<String, dynamic> json) {
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

    return Property(
      id: toInt(json['id']) ?? 0,
      address: json['address'] as String? ?? '',
      title: json['title'] as String?,
      beds: toInt(json['beds']),
      baths: toNum(json['baths']),
      garages: toInt(json['garages']),
      status: json['status'] as String?,
      propertyType: json['property_type'] as String?,
      category: json['category'] as String?,
      listingType: json['listing_type'] as String?,
      price: toInt(json['price']),
      priceDisplay: json['price_display'] as String?,
      thumbnail: json['thumbnail'] as String?,
      updatedAt: json['updated_at'] as String?,
      agentId: toInt(json['agent_id']),
      streetNumber: json['street_number'] as String?,
      streetName: json['street_name'] as String?,
      suburb: json['suburb'] as String?,
      city: json['city'] as String?,
      province: json['province'] as String?,
      region: json['region'] as String?,
      district: json['district'] as String?,
      p24ProvinceId: toInt(json['p24_province_id']),
      p24CityId: toInt(json['p24_city_id']),
      p24SuburbId: toInt(json['p24_suburb_id']),
      p24SuburbMismatch: json['p24_suburb_mismatch'] == true,
      complexName: json['complex_name'] as String?,
      unitNumber: json['unit_number'] as String?,
      sizeM2: json['size_m2']?.toString(),
      erfSizeM2: json['erf_size_m2']?.toString(),
      mandateType: json['mandate_type'] as String?,
      excerpt: json['excerpt'] as String?,
      description: json['description'] as String?,
      rentalAmount: toInt(json['rental_amount']),
      depositAmount: toInt(json['deposit_amount']),
      leaseStartDate: json['lease_start_date']?.toString(),
      leaseEndDate: json['lease_end_date']?.toString(),
      commissionPercent: toNum(json['commission_percent']),
      adminFee: toNum(json['admin_fee']),
      marketingFee: toNum(json['marketing_fee']),
      features: json['features'] != null
          ? List<String>.from(json['features'])
          : const [],
      galleryImages: json['gallery_images'] != null
          ? List<String>.from(json['gallery_images'])
          : const [],
      galleryCategories: json['gallery_categories'] as Map<String, dynamic>?,
      galleryTags: json['gallery_tags'] != null
          ? List<String>.from(json['gallery_tags'])
          : const [],
    );
  }
}
