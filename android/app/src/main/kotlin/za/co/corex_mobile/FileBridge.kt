package za.co.corex_mobile

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Saves downloads into the public Downloads collection and opens them again.
 *
 * Writing to `/storage/emulated/0/Download` with the plain File API succeeds on
 * Android 11+, but the file is never registered with MediaStore — and the Files
 * and Downloads apps list MediaStore rows, not directory contents. The download
 * therefore lands on disk and is invisible to the user, which is
 * indistinguishable from it having failed. Going through MediaStore indexes it
 * on the way in.
 *
 * The insert also hands back a `content://` URI, which ACTION_VIEW can open with
 * a per-intent read grant. That sidesteps open_filex, whose pre-FileProvider
 * gate demands a READ_MEDIA_* permission before it will open an image or video
 * that sits outside the app sandbox — permissions we deliberately don't hold,
 * because Google Play reserves them for apps whose core purpose is media access.
 */
class FileBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "corex/files"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "saveToDownloads" -> saveToDownloads(call, result)
            "saveToGallery" -> saveToGallery(call, result)
            "openUri" -> openUri(call, result)
            else -> result.notImplemented()
        }
    }

    /**
     * Inserts an image into the Pictures collection so it shows up in the
     * gallery.
     *
     * Exists because gal derives the file extension by asking Apache Commons
     * Imaging to guess the format from the bytes. When the guess comes back
     * UNKNOWN the extension is empty, and the resulting extension-less entry
     * either fails to insert or never gets indexed as an image — a silent
     * "saved but not in the gallery". The caller here already knows the format,
     * so nothing needs guessing.
     *
     * Returns the `content://` URI, or null below API 29 where RELATIVE_PATH
     * doesn't exist and the caller should fall back to gal.
     */
    private fun saveToGallery(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(null)
            return
        }

        val bytes = call.argument<ByteArray>("bytes")
        val fileName = call.argument<String>("fileName")
        val mimeType = call.argument<String>("mimeType")
        val album = call.argument<String>("album")
        if (bytes == null || fileName.isNullOrEmpty()) {
            result.error("bad_args", "bytes and fileName are required", null)
            return
        }

        // Into an album subfolder, not the root of Pictures. Many OEM galleries
        // — Honor/Huawei EMUI and MagicOS among them — build their album list
        // from directories and never show images sitting loose in Pictures/,
        // even though the MediaStore row is perfectly valid. The file then
        // "saves" and is invisible, which is the same class of bug as writing
        // to Downloads without a MediaStore entry.
        val relativePath = if (album.isNullOrEmpty()) {
            Environment.DIRECTORY_PICTURES
        } else {
            "${Environment.DIRECTORY_PICTURES}/$album"
        }

        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
            put(
                MediaStore.Images.Media.MIME_TYPE,
                if (mimeType.isNullOrEmpty()) "image/png" else mimeType,
            )
            put(MediaStore.Images.Media.RELATIVE_PATH, relativePath)
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }

        var uri: Uri? = null
        try {
            uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            if (uri == null) {
                result.success(null)
                return
            }

            val wrote = resolver.openOutputStream(uri)?.use { stream ->
                stream.write(bytes)
                true
            } ?: false
            if (!wrote) {
                runCatching { resolver.delete(uri, null, null) }
                result.success(null)
                return
            }

            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            result.success(uri.toString())
        } catch (e: Exception) {
            uri?.let { runCatching { resolver.delete(it, null, null) } }
            result.error("save_failed", e.message ?: e.toString(), null)
        }
    }

    /**
     * Returns `{uri, fileName}` on success, or null when this device predates
     * MediaStore Downloads (API < 29) or the insert was refused — the Dart side
     * treats null as "fall back to a plain file write" rather than an error.
     */
    private fun saveToDownloads(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(null)
            return
        }

        val bytes = call.argument<ByteArray>("bytes")
        val fileName = call.argument<String>("fileName")
        val mimeType = call.argument<String>("mimeType")
        if (bytes == null || fileName.isNullOrEmpty()) {
            result.error("bad_args", "bytes and fileName are required", null)
            return
        }

        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            if (!mimeType.isNullOrEmpty()) {
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
            }
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            // Hides the row until the bytes are on disk, so nothing can open a
            // half-written file.
            put(MediaStore.Downloads.IS_PENDING, 1)
        }

        var uri: Uri? = null
        try {
            uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            if (uri == null) {
                result.success(null)
                return
            }

            val wrote = resolver.openOutputStream(uri)?.use { stream ->
                stream.write(bytes)
                true
            } ?: false
            if (!wrote) {
                runCatching { resolver.delete(uri, null, null) }
                result.success(null)
                return
            }

            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)

            // MediaStore uniquifies a clashing name itself (`Mandate (1).pdf`),
            // so report back what it actually chose rather than what we asked
            // for — the snackbar would otherwise name a file that isn't there.
            result.success(
                mapOf(
                    "uri" to uri.toString(),
                    "fileName" to (displayNameOf(uri) ?: fileName),
                )
            )
        } catch (e: Exception) {
            uri?.let { runCatching { resolver.delete(it, null, null) } }
            result.success(null)
        }
    }

    private fun displayNameOf(uri: Uri): String? {
        return try {
            context.contentResolver.query(
                uri,
                arrayOf(MediaStore.Downloads.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (e: Exception) {
            null
        }
    }

    /** Hands the URI to whichever app claims the type. False if nothing does. */
    private fun openUri(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString.isNullOrEmpty()) {
            result.success(false)
            return
        }
        val mimeType = call.argument<String>("mimeType")

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(
                Uri.parse(uriString),
                if (mimeType.isNullOrEmpty()) "*/*" else mimeType,
            )
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            // The bridge holds an application context, which has no task of its
            // own to launch into.
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        result.success(
            try {
                context.startActivity(intent)
                true
            } catch (e: Exception) {
                false
            }
        )
    }
}
