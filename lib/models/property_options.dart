/// Single selectable option in one of the property dropdowns. [display] is
/// what the user sees, [submit] is what we actually send to the server when
/// saving. For most groups they're the same string (`name`); for
/// `statuses` they differ (display=name, submit=value slug); for
/// `listing_types` they also differ (display=label, submit=value slug).
class PropertyOption {
  final String display;
  final String submit;
  final bool isDefault;

  const PropertyOption({
    required this.display,
    required this.submit,
    this.isDefault = false,
  });
}

/// All dropdown option lists returned by `GET /api/v1/mobile/properties/options`.
/// The API already sorts by `sort_order` then `name`; preserve the order.
class PropertyOptions {
  final List<PropertyOption> categories;
  final List<PropertyOption> propertyTypes;
  final List<PropertyOption> statuses;
  final List<PropertyOption> mandateTypes;
  final List<PropertyOption> listingTypes;

  const PropertyOptions({
    required this.categories,
    required this.propertyTypes,
    required this.statuses,
    required this.mandateTypes,
    required this.listingTypes,
  });

  static const empty = PropertyOptions(
    categories: [],
    propertyTypes: [],
    statuses: [],
    mandateTypes: [],
    listingTypes: [],
  );

  factory PropertyOptions.fromJson(Map<String, dynamic> json) {
    List<PropertyOption> nameBased(dynamic raw) {
      if (raw is! List) return const [];
      return raw.whereType<Map>().map((e) {
        final name = e['name']?.toString() ?? '';
        return PropertyOption(
          display: name,
          submit: name,
          isDefault: e['is_default'] == true,
        );
      }).toList();
    }

    List<PropertyOption> statusBased(dynamic raw) {
      if (raw is! List) return const [];
      return raw.whereType<Map>().map((e) {
        return PropertyOption(
          display: e['name']?.toString() ?? '',
          submit: e['value']?.toString() ?? '',
          isDefault: e['is_default'] == true,
        );
      }).toList();
    }

    List<PropertyOption> listingBased(dynamic raw) {
      if (raw is! List) return const [];
      return raw.whereType<Map>().map((e) {
        return PropertyOption(
          display: e['label']?.toString() ?? '',
          submit: e['value']?.toString() ?? '',
        );
      }).toList();
    }

    return PropertyOptions(
      categories: nameBased(json['categories']),
      propertyTypes: nameBased(json['property_types']),
      statuses: statusBased(json['statuses']),
      mandateTypes: nameBased(json['mandate_types']),
      listingTypes: listingBased(json['listing_types']),
    );
  }
}

extension PropertyOptionListX on List<PropertyOption> {
  /// First item flagged `is_default`, else the first item, else null.
  PropertyOption? get defaultOption {
    if (isEmpty) return null;
    for (final o in this) {
      if (o.isDefault) return o;
    }
    return first;
  }

  String? get defaultSubmit => defaultOption?.submit;
}
