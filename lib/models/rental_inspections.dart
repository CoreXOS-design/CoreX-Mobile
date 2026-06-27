/// Mobile model for the rental inspection galleries exposed by the backend at
/// `/v1/mobile/properties/{id}/rental-images`.
///
/// The backend is the source of truth: every mutating call returns the full
/// `rental_images` structure, and the app always re-renders from the last
/// returned [RentalInspections] rather than mutating local state.
library;

/// The `section` value sent to the backend for a gallery. The two fixed
/// inspections use their own keys; every custom gallery uses the literal
/// `custom` and is disambiguated by its server-minted [RentalSection.customId].
enum RentalSectionType {
  inInspection('in_inspection'),
  outInspection('out_inspection'),
  custom('custom');

  const RentalSectionType(this.apiValue);

  /// The exact string sent as the `section` field on upload/save/delete.
  final String apiValue;
}

/// One gallery: a fixed inspection (In / Out) or a custom section.
class RentalSection {
  /// Which `section` literal this gallery maps to on the wire.
  final RentalSectionType type;

  /// Server-minted opaque id — present only for custom sections. Never
  /// generate this client-side; treat it as opaque.
  final String? customId;

  /// Display name. Fixed sections get a human label; custom sections carry
  /// the user-supplied name.
  final String name;

  /// Inspection date as `YYYY-MM-DD`, or null when unset.
  final String? date;

  /// Absolute image URLs — render directly.
  final List<String> images;

  const RentalSection({
    required this.type,
    this.customId,
    required this.name,
    this.date,
    this.images = const [],
  });

  bool get isCustom => type == RentalSectionType.custom;

  factory RentalSection.fixed(
    RentalSectionType type,
    String name,
    Map<String, dynamic>? json,
  ) {
    return RentalSection(
      type: type,
      name: name,
      date: _str(json?['date']),
      images: _images(json?['images']),
    );
  }

  /// Parses one custom section. Returns null when the server-minted `id` is
  /// missing/empty — without it we'd build `custom:null` keys and send
  /// `custom_id: null` requests, so such entries are dropped at parse time.
  static RentalSection? fromCustomJson(Map<String, dynamic> json) {
    final id = _str(json['id']);
    if (id == null) return null;
    return RentalSection(
      type: RentalSectionType.custom,
      customId: id,
      name: _str(json['name']) ?? 'Untitled section',
      date: _str(json['date']),
      images: _images(json['images']),
    );
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  static List<String> _images(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }
}

/// The full rental-images payload for one property.
class RentalInspections {
  final int propertyId;
  final String? listingType;
  final bool isLive;
  final bool available;

  final RentalSection inInspection;
  final RentalSection outInspection;
  final List<RentalSection> custom;

  const RentalInspections({
    required this.propertyId,
    this.listingType,
    this.isLive = false,
    this.available = false,
    required this.inInspection,
    required this.outInspection,
    this.custom = const [],
  });

  /// In Inspection, Out Inspection, then each custom section — render order.
  List<RentalSection> get sections => [inInspection, outInspection, ...custom];

  factory RentalInspections.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    Map<String, dynamic>? toMap(dynamic v) =>
        v is Map ? Map<String, dynamic>.from(v) : null;

    final images = toMap(json['rental_images']) ?? const {};
    final customRaw = images['custom'];
    final custom = customRaw is List
        ? customRaw
            .whereType<Map>()
            .map((e) => RentalSection.fromCustomJson(Map<String, dynamic>.from(e)))
            .whereType<RentalSection>()
            .toList()
        : <RentalSection>[];

    return RentalInspections(
      propertyId: toInt(json['property_id']),
      listingType: RentalSection._str(json['listing_type']),
      isLive: json['is_live'] == true,
      available: json['available'] == true,
      inInspection: RentalSection.fixed(
        RentalSectionType.inInspection,
        'In Inspection',
        toMap(images['in_inspection']),
      ),
      outInspection: RentalSection.fixed(
        RentalSectionType.outInspection,
        'Out Inspection',
        toMap(images['out_inspection']),
      ),
      custom: custom,
    );
  }
}
