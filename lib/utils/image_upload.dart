/// Shared tuning for property/rental photo uploads.
///
/// Passing [quality] (and the max dimensions) to `image_picker` makes it
/// re-encode the picked asset to JPEG. This matters for two reasons:
///
///  * On iOS it transcodes HEIC originals to JPEG, so the backend never
///    receives a `.heic` file its decoder can't process.
///  * It shrinks multi-MB camera/gallery originals ~5-10x, keeping uploads
///    under the server's size limit and inside the request timeout.
///
/// Values are a balance for real-estate listing photos: large enough to stay
/// crisp on the web, small enough to upload reliably over a mobile uplink.
class ImageUploadConfig {
  ImageUploadConfig._();

  /// Longest-edge cap in logical pixels.
  static const int maxEdge = 2560;

  /// Same cap expressed as doubles for `image_picker` (which pre-downscales at
  /// pick time so we never decode a 48MP original in the `image` package and
  /// risk an out-of-memory crash on low-end devices). Keep in sync with
  /// [maxEdge].
  static const double maxWidth = 2560;
  static const double maxHeight = 2560;

  /// JPEG quality (0-100). 82 is visually near-lossless for photos.
  static const int quality = 82;
}
