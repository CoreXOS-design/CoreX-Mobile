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

  /// Largest source image, in pixels, we will decode in-process.
  ///
  /// `package:image` has no scaled decode: it materialises the whole frame as
  /// 3 bytes per pixel, on top of the coefficient blocks the JPEG decoder holds
  /// while it works — call it ~6 bytes per source pixel at peak. 24 MP is
  /// therefore around 150 MB, which a phone can carry; a 50 MP still (some
  /// Android sensors expose one to CameraX without entering high-resolution
  /// mode) would be 300 MB and is a plausible way to be killed for memory.
  ///
  /// The cap costs nothing in output quality. Everything above [maxEdge] is
  /// discarded by the downscale anyway — 24 MP is already ~5x the pixels that
  /// survive it — so this only ever bounds work we were going to throw away.
  ///
  /// Over the cap, [prepareForUpload] uploads the original untouched and lets
  /// the server do the orientation bake and downscale it already performs.
  static const int maxDecodePixels = 24 * 1000 * 1000;
}
