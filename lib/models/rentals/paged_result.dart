/// A decoded rentals JSON object (read with the `MapRead` helpers).
typedef Json = Map<String, dynamic>;

/// One page of a `{data, meta}` rentals list response:
/// `meta{page, per_page, total, last_page, empty_reason}`, 25 per page.
class PagedResult<T> {
  final List<T> items;
  final int page;
  final int lastPage;
  final int total;
  final String? emptyReason;

  const PagedResult({
    required this.items,
    required this.page,
    required this.lastPage,
    required this.total,
    this.emptyReason,
  });

  static PagedResult<T> parse<T>(
      Map<String, dynamic> body, T Function(Map<String, dynamic>) item) {
    final data = (body['data'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => item(Map<String, dynamic>.from(e)))
        .toList();
    final meta = body['meta'] is Map
        ? Map<String, dynamic>.from(body['meta'] as Map)
        : const <String, dynamic>{};
    final page = (meta['page'] as num?)?.toInt() ?? 1;
    return PagedResult<T>(
      items: data,
      page: page,
      lastPage: (meta['last_page'] as num?)?.toInt() ??
          _lastPageFrom(meta, page),
      total: (meta['total'] as num?)?.toInt() ?? data.length,
      emptyReason: meta['empty_reason']?.toString(),
    );
  }
}


/// Some lists (e.g. `/mobile/rentals/waiting`) send `total` and `per_page`
/// but no `last_page`.
int _lastPageFrom(Map<String, dynamic> meta, int page) {
  final total = (meta['total'] as num?)?.toInt();
  final per = (meta['per_page'] as num?)?.toInt();
  if (total == null || per == null || per <= 0) return page;
  final pages = (total + per - 1) ~/ per;
  return pages < page ? page : pages;
}

/// Small helpers for reading loosely-typed payloads.
extension MapRead on Map<String, dynamic> {
  String? str(String k) {
    final v = this[k];
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  int? integer(String k) {
    final v = this[k];
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  bool flag(String k) => this[k] == true || this[k] == 1 || this[k] == '1';

  Map<String, dynamic>? obj(String k) => this[k] is Map
      ? Map<String, dynamic>.from(this[k] as Map)
      : null;

  List<Map<String, dynamic>> objs(String k) => (this[k] as List? ?? const [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}
