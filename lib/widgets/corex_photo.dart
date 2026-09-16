import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../services/image_cache.dart';
import '../services/image_cache_diagnostics.dart';

/// A property photo, loaded and disk-cached at the size it is shown at.
///
/// This is the only way photos should be rendered in the app — it is what
/// keeps the cache small. There are two shapes:
///
/// * [CoreXPhoto.thumb] — anything that is a cell, a card, a strip or a
///   hero: fetches the server's 500px thumbnail ([CoreXImageCache.thumbUrl])
///   into the long-lived thumbnail store. If the thumb doesn't exist (a photo
///   the backfill hasn't reached) it quietly falls back to the original,
///   fetched into the small full-size store so one un-backfilled property
///   can't bloat the working set — and remembers the 404 for the session so
///   the cell doesn't re-ask for the missing thumb every time it scrolls into
///   view. A URL that isn't a property photo at all (an avatar, an agency
///   logo, an already-thumb URL) is fetched as-is into the thumbnail store:
///   it *is* the working set, and the full store's forty slots belong to the
///   viewer.
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
    if (_full) return _original(px, CoreXImageCache.full);

    final thumb = CoreXImageCache.thumbUrl(url);
    // Not a property photo (or already a thumb): there is nothing smaller to
    // ask for, and it belongs with the other thumbnails, not in the viewer's
    // short-lived store.
    if (thumb == url) return _original(px, CoreXImageCache.manager);
    // Known-missing thumb: skip straight to the original rather than paying
    // for the same 404 on every rebuild.
    if (CoreXImageCache.isThumbMissing(thumb)) {
      return _original(px, CoreXImageCache.full);
    }

    return CachedNetworkImage(
      imageUrl: thumb,
      cacheManager: CoreXImageCache.manager,
      memCacheWidth: px,
      // Recorded under the thumb path so a tester's report shows "thumbs/"
      // — a run of these means the backfill hasn't reached that property,
      // not that the photo is broken.
      errorListener: (e) {
        CoreXImageCache.noteThumbFailure(thumb, e);
        ImageCacheDiagnostics.recordFailure(thumb, e);
      },
      fit: fit,
      width: width,
      height: height,
      placeholder: placeholder == null ? null : (ctx, _) => placeholder!(ctx),
      errorWidget: (_, __, ___) => _original(px, CoreXImageCache.full),
    );
  }

  Widget _original(int px, CacheManager store) {
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: store,
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
