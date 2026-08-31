/// Response of `GET /api/v1/mobile/properties/{id}/gallery/tags`.
///
/// - [availableTags] is the canonical ordered list of tags the agent may use
///   when uploading to this property. Derived server-side from the property's
///   spaces, so it changes as soon as the agent adds/removes a space.
/// - [tagCounts] is how many photos are currently filed under each tag.
/// - [untaggedCount] is the number of photos with no tag at all.
class GalleryTagsData {
  final int propertyId;
  final List<String> availableTags;
  final Map<String, int> tagCounts;
  final int untaggedCount;

  const GalleryTagsData({
    required this.propertyId,
    required this.availableTags,
    required this.tagCounts,
    required this.untaggedCount,
  });

  factory GalleryTagsData.empty(int propertyId) => GalleryTagsData(
        propertyId: propertyId,
        availableTags: const [],
        tagCounts: const {},
        untaggedCount: 0,
      );

  factory GalleryTagsData.fromJson(Map<String, dynamic> json) {
    final rawTags = json['available_tags'];
    final rawCounts = json['tag_counts'];
    return GalleryTagsData(
      propertyId: (json['property_id'] is int) ? json['property_id'] as int : 0,
      availableTags: (rawTags is List)
          ? rawTags.map((e) => e.toString()).toList()
          : const [],
      tagCounts: (rawCounts is Map)
          ? rawCounts.map((k, v) => MapEntry(
                k.toString(),
                (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? 0,
              ))
          : const {},
      untaggedCount:
          (json['untagged_count'] is num) ? (json['untagged_count'] as num).toInt() : 0,
    );
  }

  /// Returns a new [GalleryTagsData] with [availableTags] swapped — used when
  /// a 422 from the upload endpoint tells us the list has drifted.
  GalleryTagsData withAvailable(List<String> tags) => GalleryTagsData(
        propertyId: propertyId,
        availableTags: tags,
        tagCounts: tagCounts,
        untaggedCount: untaggedCount,
      );
}

/// Result of a successful `POST /api/v1/mobile/properties/{id}/images`.
///
/// [analysisId] is non-null only when image-AI is enabled for the user +
/// agency; the caller uses it to drive the `/ai-suggestions` poll batch.
class UploadedImage {
  final String url;

  /// The tag the server actually filed the photo under — **only meaningful
  /// when [duplicate] is false**. See [duplicate].
  final String? roomTag;
  final int? analysisId;

  /// True when the server recognised our `client_upload_id` and returned the
  /// already-stored record instead of filing a second copy (HTTP 200, not 201).
  ///
  /// Matters because `MobilePropertyController::uploadImage`'s fast-path dedupe
  /// answers with `room_tag: null` regardless of how the photo was actually
  /// filed. Reading [roomTag] on a duplicate therefore reports "Unsorted" for a
  /// correctly-tagged photo — which is precisely the shape a retried upload
  /// takes, so any tag check must sit this response out rather than trust it.
  final bool duplicate;

  const UploadedImage({
    required this.url,
    this.roomTag,
    this.analysisId,
    this.duplicate = false,
  });
}

/// The `gallery_categories` block on the mobile property payload.
///
/// ```json
/// { "categories": { "Bathroom 3": ["https://.../a.jpg"] },
///   "unsorted":   ["https://.../b.jpg"] }
/// ```
///
/// [unsorted] is the bucket of photos that reached the property with no
/// `room_tag`. It used to be absent from the payload entirely, which is how an
/// untagged photo could be stored server-side and still appear on no screen —
/// the agent's "some didn't upload" report was really "uploaded, nowhere to
/// look". Parse it even when the key is missing (older servers) so callers can
/// treat "no unsorted section" and "an empty one" the same way.
///
/// [fromJson] is deliberately generous, because this endpoint has emitted
/// several shapes over its life and a property created under an older one is
/// still in the database:
///
///   - `{ categories: { Tag: [url, ...] }, unsorted: [url, ...] }`  (current)
///   - `{ categories: { Tag: [{ url, ... }, ...] } }`               (objects)
///   - `{ categories: { Tag: [...], Unsorted: [...] } }`            (legacy
///     bucket nested as an ordinary category — folded into [unsorted])
///   - `{ Tag: [...] }`                                             (flat)
class GalleryCategories {
  /// Tag → photo URLs, in server order. Never contains the unsorted bucket.
  final Map<String, List<String>> categories;

  /// Photos on the property with no room tag.
  final List<String> unsorted;

  const GalleryCategories({
    required this.categories,
    required this.unsorted,
  });

  static const GalleryCategories empty =
      GalleryCategories(categories: {}, unsorted: []);

  /// The key older servers used for the untagged bucket, before `unsorted`
  /// became a sibling of `categories`. Matched case-insensitively.
  static const String _legacyUnsortedKey = 'unsorted';

  factory GalleryCategories.fromJson(dynamic raw) {
    if (raw is! Map) return empty;
    final hasCategoriesKey = raw['categories'] is Map;
    final cats = hasCategoriesKey ? raw['categories'] as Map : raw;

    final out = <String, List<String>>{};
    final unsorted = <String>[];

    cats.forEach((k, v) {
      final key = k.toString();
      // A flat-shaped payload has `unsorted` sitting alongside the tags; don't
      // mistake it for a room called "unsorted".
      final isUnsorted = key.trim().toLowerCase() == _legacyUnsortedKey;
      final urls = _urlList(v);
      if (isUnsorted) {
        unsorted.addAll(urls);
      } else {
        out[key] = urls;
      }
    });

    // The modern shape. Read it only when `categories` was its own key —
    // otherwise `cats` IS the root map and we already consumed it above.
    if (hasCategoriesKey) {
      unsorted.addAll(_urlList(raw[_legacyUnsortedKey]));
    }

    return GalleryCategories(
      categories: out,
      // The same photo can arrive from both the legacy nested bucket and the
      // modern sibling key on a server mid-migration.
      unsorted: unsorted.toSet().toList(),
    );
  }

  /// Image URLs from the mobile property API are already absolute
  /// (https://host/storage/...), so entries are used as-is — no host-prefixing.
  static List<String> _urlList(dynamic v) {
    if (v is! List) return const [];
    final urls = <String>[];
    for (final item in v) {
      if (item is String) {
        if (item.isNotEmpty) urls.add(item);
      } else if (item is Map) {
        final u = item['url'] ?? item['src'] ?? item['path'];
        if (u is String && u.isNotEmpty) urls.add(u);
      }
    }
    return urls;
  }

  int get totalCount =>
      unsorted.length +
      categories.values.fold<int>(0, (sum, v) => sum + v.length);
}

/// Response of `PUT /api/v1/mobile/properties/{id}/gallery/assign`.
///
/// The server answers every outcome — full success, partial, and the 422s —
/// with the property's freshly recomputed [categories] and [availableTags], so
/// a caller re-renders straight from this and never needs a follow-up GET.
///
/// [unknownImages] being non-empty alongside a positive [moved] is a *partial*
/// success (HTTP 200): those URLs are no longer on this property, so the
/// caller's list is stale. Show what moved, then refresh.
class GalleryAssignResult {
  final String message;
  final int moved;
  final List<String> unknownImages;

  /// The tag the photos were filed under; `null` means they were moved back
  /// to Unsorted.
  final String? roomTag;
  final GalleryCategories categories;
  final List<String> availableTags;

  const GalleryAssignResult({
    required this.message,
    required this.moved,
    required this.unknownImages,
    required this.roomTag,
    required this.categories,
    required this.availableTags,
  });

  bool get isPartial => moved > 0 && unknownImages.isNotEmpty;

  factory GalleryAssignResult.fromJson(Map<String, dynamic> json) {
    final moved = json['moved'];
    return GalleryAssignResult(
      message: json['message']?.toString() ?? 'Photos filed.',
      moved: moved is num ? moved.toInt() : int.tryParse('$moved') ?? 0,
      unknownImages: (json['unknown_images'] is List)
          ? (json['unknown_images'] as List).map((e) => e.toString()).toList()
          : const [],
      roomTag: json['room_tag']?.toString(),
      categories: GalleryCategories.fromJson(json['gallery_categories']),
      availableTags: (json['available_tags'] is List)
          ? (json['available_tags'] as List).map((e) => e.toString()).toList()
          : const [],
    );
  }
}

/// Outcome of [ApiService.deletePropertyImages].
///
/// [deleted] is the number the server actually removed; [unknownIds] are the
/// keys it could not match. A key comes back unknown when the photo was never
/// on this property, or was already deleted — both of which mean the caller's
/// list is stale, not that the delete failed.
///
/// The server also returns the property's recomputed gallery, which this
/// deliberately does not model: the one caller is the camera's review grid,
/// which has no gallery to re-render. Add it here rather than re-fetching if a
/// gallery-side delete ever needs it.
class DeletedImages {
  final String message;
  final int deleted;
  final List<String> unknownIds;

  const DeletedImages({
    required this.message,
    required this.deleted,
    required this.unknownIds,
  });

  /// Nothing matched. The photo is not on the property — usually because it
  /// never landed, occasionally because someone else removed it first.
  bool get matchedNothing => deleted == 0;

  factory DeletedImages.fromJson(Map<String, dynamic> json) {
    final deleted = json['deleted'];
    return DeletedImages(
      message: json['message']?.toString() ?? 'Photo deleted.',
      deleted: deleted is num ? deleted.toInt() : int.tryParse('$deleted') ?? 0,
      unknownIds: (json['unknown_ids'] is List)
          ? (json['unknown_ids'] as List).map((e) => e.toString()).toList()
          : const [],
    );
  }
}
