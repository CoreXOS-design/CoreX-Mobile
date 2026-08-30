package za.co.corex_mobile

import android.app.Activity
import android.view.OrientationEventListener
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Reports how the phone is *physically* being held, from the accelerometer.
 *
 * The in-app camera pins its UI to portrait, and that is precisely what blinds
 * the camera plugin: on Android (camera_android_camerax — see the note below)
 * the capture rotation defaults to `Display.getRotation()`, which the portrait
 * lock freezes. Every shot was therefore written as if the phone were upright,
 * so a landscape photo came out as a landscape scene turned 90 degrees into a
 * portrait frame — with EXIF Orientation stamped 1, because as far as the
 * pipeline knew the pixels were already correct.
 *
 * `OrientationEventListener` reads the accelerometer directly and is unaffected
 * by the screen-orientation lock, which makes it the only source on Android
 * that still knows which way the phone was tilted. No permission is required.
 *
 * iOS needs none of this: camera_avfoundation calls
 * `beginGeneratingDeviceOrientationNotifications()` and applies
 * `UIDevice.current.orientation` at capture, which follows the hardware
 * regardless of what the app's interface is pinned to.
 */
class DeviceRotationBridge(activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "corex/device_rotation"
    }

    /**
     * Last known clockwise rotation of the device from its natural position,
     * rounded to 0/90/180/270. Written from the sensor callback, read from the
     * platform-channel call.
     *
     * Deliberately NOT cleared by [stop]: the last real reading is the best
     * information we have, and a device that is lying flat when the camera
     * opens (shooting straight down at a floor is a normal listing shot) would
     * otherwise report "unknown" for the whole session and silently fall back
     * to the frozen display rotation — the very bug this class exists to end.
     * The listener re-reports within a frame or two of any movement, so the
     * only staleness window is "rotated while the app was backgrounded".
     */
    @Volatile
    private var rotation: Int? = null

    private val listener = object : OrientationEventListener(activity.applicationContext) {
        override fun onOrientationChanged(orientation: Int) {
            // ORIENTATION_UNKNOWN means the device is lying flat and the
            // accelerometer can't resolve a rotation — e.g. shooting straight
            // down at a floor. Keep the last real reading rather than guessing.
            if (orientation == ORIENTATION_UNKNOWN) return
            rotation = ((orientation + 45) / 90 * 90) % 360
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                if (listener.canDetectOrientation()) listener.enable()
                result.success(null)
            }
            "stop" -> {
                listener.disable()
                result.success(null)
            }
            "read" -> result.success(read())
            else -> result.notImplemented()
        }
    }

    /**
     * The current reading, or null when the sensor has never reported (or
     * can't). Callers must treat null as "don't know" and never as "upright".
     */
    private fun read(): Map<String, Any>? {
        val clockwise = rotation ?: return null
        return mapOf(
            "rotation" to clockwise,
            "orientation" to orientationName(clockwise),
        )
    }

    /**
     * Converts a physical rotation into the `DeviceOrientation` name that
     * `lockCaptureOrientation` will turn back into the target rotation we want.
     *
     * WHICH PLUGIN: this app resolves `camera: ^0.11.0+2`, whose Android
     * implementation is **camera_android_camerax** (check pubspec.lock — there
     * is no `camera_android` entry). Its
     * `_getRotationConstantFromDeviceOrientation` is a fixed table, independent
     * of the device's natural orientation:
     *
     *   portraitUp -> ROTATION_0    landscapeLeft  -> ROTATION_90
     *   portraitDown -> ROTATION_180 landscapeRight -> ROTATION_270
     *
     * which it hands to `ImageCapture.setTargetRotation`. So the name we return
     * is just an encoding of a Surface rotation constant, and this table must
     * be the exact inverse of that one — NOT of the plugin's
     * `DeviceOrientationManager.getUiOrientation()`, which additionally consults
     * `Configuration.orientation` and therefore disagrees with the lock table on
     * a landscape-natural device. Reproducing getUiOrientation() here is what
     * turned every tablet photo 90 degrees: natural (0 degrees clockwise) came
     * back as landscapeLeft and was captured at ROTATION_90.
     *
     * Display rotation runs opposite to physical rotation — `getRotation()` is
     * documented as the rotation of the drawn graphics, "the opposite direction
     * of the physical rotation of the device" — hence the 360 - clockwise. The
     * result matches Android's own documented snippet for feeding
     * OrientationEventListener into CameraX's target rotation:
     *
     *   45..134 -> ROTATION_270, 135..224 -> ROTATION_180,
     *   225..314 -> ROTATION_90, else -> ROTATION_0
     *
     * The resulting sense (a 90 degree CLOCKWISE turn of the phone is
     * landscapeRight, not landscapeLeft) is confirmed by camerax's own lock
     * table above and by camera_avfoundation passing
     * UIDeviceOrientationLandscapeLeft (home button on the right, i.e. turned
     * counter-clockwise) straight through as landscapeLeft.
     */
    private fun orientationName(clockwise: Int): String {
        return when ((360 - clockwise) % 360) {
            90 -> "landscapeLeft"
            180 -> "portraitDown"
            270 -> "landscapeRight"
            else -> "portraitUp"
        }
    }
}
