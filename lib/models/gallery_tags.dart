/// Response of `GET /api/mobile/properties/{id}/gallery/tags`.
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

/// Result of a successful `POST /api/mobile/properties/{id}/images`.
///
/// [analysisId] is non-null only when image-AI is enabled for the user +
/// agency; the caller uses it to drive the `/ai-suggestions` poll batch.
class UploadedImage {
  final String url;
  final String? roomTag;
  final int? analysisId;

  const UploadedImage({required this.url, this.roomTag, this.analysisId});
}
