import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

import '../services/image_cache.dart';
import '../services/image_cache_diagnostics.dart';

/// A property photo, loaded and disk-cached at the size it is shown at.
///
/// This is the only way photos should be rendered in the app — it is what
/// keeps the cache small. There are two shapes:
///
/// * [CoreXPhoto.thumb] — anything that is a cell, a card, a strip or a
///   hero: fetches the server's 500px thumbnail ([CoreXImageCache.thumbUrl])
///   into the long-lived thumbnail store. If the thumb doesn't exist yet
///   (photos that predate the backfill) it quietly falls back to the
///   original, fetched into the small full-size store so one un-backfilled
///   property can't bloat the working set.
/// * [CoreXPhoto.full] — the full-screen viewer and the client carousel:
///   the original, in the small, short-lived full-size store.
///
/// [logicalWidth] is the width the photo is *displayed* at, in logical
/// pixels; it bounds the decoded bitmap so a 3-column grid never decodes
/// ninety 12MP bitmaps (see [CoreXImageCache.thumbPx]).
class CoreXPhoto extends StatelessWidget {
  const CoreXPhoto.thumb({
    super.key,
    required this.url,
    required this.logicalWidth,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  }) : _full = false;

  const CoreXPhoto.full({
    super.key,
    required this.url,
    required this.logicalWidth,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  }) : _full = true;

  /// The photo's original URL, as the API returned it. Never pass a thumb
  /// URL — the rewrite is applied here.
  final String url;
  final double logicalWidth;
  final BoxFit fit;
  final double? width;
  final double? height;
  final WidgetBuilder? placeholder;
  final WidgetBuilder? errorWidget;
  final bool _full;

  @override
  Widget build(BuildContext context) {
    final px = CoreXImageCache.thumbPx(context, logicalWidth);
    final thumb = _full ? url : CoreXImageCache.thumbUrl(url);
    if (thumb == url) return _original(px);
    return CachedNetworkImage(
      imageUrl: thumb,
      cacheManager: CoreXImageCache.manager,
      memCacheWidth: px,
      // Recorded under the thumb path so a tester's report shows "thumbs/"
      // — a run of these means the backfill hasn't been run for that
      // property, not that the photo is broken.
      errorListener: (e) => ImageCacheDiagnostics.recordFailure(thumb, e),
      fit: fit,
      width: width,
      height: height,
      placeholder: placeholder == null ? null : (ctx, _) => placeholder!(ctx),
      errorWidget: (_, __, ___) => _original(px),
    );
  }

  Widget _original(int px) {
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: CoreXImageCache.full,
      memCacheWidth: px,
      errorListener: (e) => ImageCacheDiagnostics.recordFailure(url, e),
      fit: fit,
      width: width,
      height: height,
      placeholder: placeholder == null ? null : (ctx, _) => placeholder!(ctx),
      errorWidget:
          errorWidget == null ? null : (ctx, _, __) => errorWidget!(ctx),
    );
  }
}
