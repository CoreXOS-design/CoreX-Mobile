/// One node in the Property24 location cascade (province / city / suburb).
///
/// `id` is the CoreX-side identifier — that's what we POST/PUT back as
/// `p24_province_id` / `p24_city_id` / `p24_suburb_id`. `p24Id` is
/// Property24's own id; we keep it for display/debug only and never
/// submit it.
class P24Location {
  final int id;
  final String name;
  final int? p24Id;

  const P24Location({required this.id, required this.name, this.p24Id});

  factory P24Location.fromJson(Map<String, dynamic> json) {
    return P24Location(
      id: json['id'] is num
          ? (json['id'] as num).toInt()
          : int.tryParse('${json['id']}') ?? 0,
      name: (json['name'] ?? '').toString(),
      p24Id: json['p24_id'] is int
          ? json['p24_id'] as int
          : int.tryParse('${json['p24_id']}'),
    );
  }

  @override
  bool operator ==(Object other) => other is P24Location && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
