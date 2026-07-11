package com.example.car_launcher_app

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Native Android host for the Flutter car stereo launcher.
 *
 * Production-ready implementation for Android head units (API 24+ / Android 7+).
 *
 * Key Features:
 * - singleInstance mode for seamless home launcher behavior
 * - MethodChannel intercepts Flutter triggers and dispatches media commands
 * - Explicitly abandons audio focus to never interrupt Bluetooth playback
 * - Targets the active Bluetooth (A2DP) media session directly via MediaSessionManager
 *   so the hardware-style buttons reliably control Spotify / YouTube Music / etc.
 *   playing on the connected car stereo, with AudioManager fallback.
 * - Synchronous Bluetooth A2DP connection detection (fixes async getProfileProxy bug)
 * - Proper API level guards for Android 8-10 (API 26-30) compatibility
 *
 * The MethodChannel 'com.carapp.media/control' handles:
 * - mediaPrevious: Skip to previous track
 * - mediaToggle: Play/Pause toggle
 * - mediaNext: Skip to next track
 * - mediaVolumeUp: Increase device/media volume by one step
 * - mediaVolumeDown: Decrease device/media volume by one step
 * - getNowPlaying: Returns the current track title/artist from the active media session
 * - isBluetoothConnected: Returns true if a Bluetooth A2DP audio device is connected
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.carapp.media/control"

    companion object {
        private const val BT_PERMISSION_REQUEST_CODE = 1001
    }

    // Hardware media key codes for universal media control.
    private val KEYCODE_MEDIA_PLAY_PAUSE = KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
    private val KEYCODE_MEDIA_NEXT = KeyEvent.KEYCODE_MEDIA_NEXT
    private val KEYCODE_MEDIA_PREVIOUS = KeyEvent.KEYCODE_MEDIA_PREVIOUS

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Abandon audio focus to prevent interrupting Bluetooth playback.
        // This is called before any audio could be requested.
        val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        audioManager.abandonAudioFocus(null)

        // On Android 12+ (API 31+) BLUETOOTH_CONNECT is a dangerous runtime
        // permission and MUST be granted at runtime, not just declared in the
        // manifest. Request it so the media card can read the A2DP state
        // without throwing a fatal SecurityException.
        // On Android 8-10 (API 26-30) this permission is not needed at runtime.
        requestBluetoothPermission()
    }

    /**
     * Returns true if we are allowed to access Bluetooth connection info.
     * On Android 8-10 (API < 31) the permission is not required at runtime.
     */
    private fun hasBluetoothConnectPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.BLUETOOTH_CONNECT
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestBluetoothPermission() {
        if (hasBluetoothConnectPermission()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.BLUETOOTH_CONNECT),
                BT_PERMISSION_REQUEST_CODE
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        // No action needed; the media card simply polls state on a timer and
        // will reflect the connection once (if) the permission is granted.
    }

    /**
     * configureFlutterEngine: Set up MethodChannel for media control communication.
     */
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        val sessionManager =
            getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "mediaPrevious" -> {
                            dispatchMediaAction(sessionManager, audioManager, KEYCODE_MEDIA_PREVIOUS) {
                                it.transportControls.skipToPrevious()
                            }
                            result.success(null)
                        }
                        "mediaToggle" -> {
                            dispatchMediaAction(sessionManager, audioManager, KEYCODE_MEDIA_PLAY_PAUSE) {
                                // TransportControls has no playPause() method;
                                // emulate the hardware key which toggles play/pause
                                // on the active media session.
                                dispatchMediaKeyEvent(audioManager, KEYCODE_MEDIA_PLAY_PAUSE)
                            }
                            result.success(null)
                        }
                        "mediaNext" -> {
                            dispatchMediaAction(sessionManager, audioManager, KEYCODE_MEDIA_NEXT) {
                                it.transportControls.skipToNext()
                            }
                            result.success(null)
                        }
                        "mediaVolumeUp" -> {
                            dispatchVolumeKey(audioManager, KeyEvent.KEYCODE_VOLUME_UP)
                            result.success(null)
                        }
                        "mediaVolumeDown" -> {
                            dispatchVolumeKey(audioManager, KeyEvent.KEYCODE_VOLUME_DOWN)
                            result.success(null)
                        }
                        "getNowPlaying" -> {
                            result.success(getNowPlaying(sessionManager))
                        }
                        "isBluetoothConnected" -> {
                            result.success(isBluetoothA2dpConnected())
                        }
                        "requestBluetoothPermission" -> {
                            requestBluetoothPermission()
                            result.success(hasBluetoothConnectPermission())
                        }
                        else -> result.notImplemented()
                    }
                } catch (t: Throwable) {
                    result.error("MEDIA_ERROR", t.message, null)
                }
            }
    }

    /**
     * Resolves the active Bluetooth (or foreground) media session and performs the
     * requested [action] on its [MediaController.TransportControls].
     *
     * If no suitable media session is found (e.g. nothing is playing yet), it
     * falls back to dispatching a raw hardware media key event through the
     * [AudioManager] so the press still reaches the default active player.
     */
    private fun dispatchMediaAction(
        sessionManager: MediaSessionManager,
        audioManager: AudioManager,
        keyCode: Int,
        action: (MediaController) -> Unit
    ) {
        if (!hasBluetoothConnectPermission()) {
            // No permission: fall back to a raw hardware key event so the press
            // still reaches the default active player without crashing.
            dispatchMediaKeyEvent(audioManager, keyCode)
            return
        }
        val controllers = sessionManager.getActiveSessions(null)
        // Prefer a controller whose package looks like a Bluetooth / remote player;
        // otherwise use the first active controller if any.
        val target = controllers.firstOrNull { isLikelyBluetooth(it) } ?: controllers.firstOrNull()

        if (target != null) {
            action(target)
        } else {
            // Fallback: emulate a hardware key press on the system media session.
            dispatchMediaKeyEvent(audioManager, keyCode)
        }
    }

    /**
     * Heuristic to detect a Bluetooth / remote media session.
     *
     * Bluetooth A2DP players normally expose a package name containing common
     * streaming/BT identifiers, or report a non-empty package that is not this
     * launcher. We treat any external, non-launcher package as a candidate.
     */
    private fun isLikelyBluetooth(controller: MediaController): Boolean {
        val pkg = controller.packageName ?: return false
        if (pkg == packageName) return false
        return pkg.contains("bluetooth", ignoreCase = true) ||
                pkg.contains("a2dp", ignoreCase = true) ||
                pkg.contains("spotify", ignoreCase = true) ||
                pkg.contains("youtube", ignoreCase = true) ||
                pkg.contains("music", ignoreCase = true) ||
                pkg.contains("media", ignoreCase = true) ||
                pkg.contains("android", ignoreCase = true)
    }

    /**
     * Returns true when a Bluetooth A2DP (audio) device is currently connected.
     *
     * FIXED: Uses synchronous getProfileConnectionState() instead of the broken
     * async getProfileProxy() approach. getProfileConnectionState() is available
     * from API 14+ (Android 4.0+) and returns the connection state immediately.
     *
     * For Android 8-10 (API 26-30): BLUETOOTH_CONNECT permission is not required,
     * so this works without runtime permission grants.
     */
    private fun isBluetoothA2dpConnected(): Boolean {
        if (!hasBluetoothConnectPermission()) return false
        val adapter = BluetoothAdapter.getDefaultAdapter() ?: return false
        if (!adapter.isEnabled) return false
        return try {
            // Synchronous check - works on API 14+ (all supported Android versions)
            val state = adapter.getProfileConnectionState(BluetoothProfile.A2DP)
            state == BluetoothProfile.STATE_CONNECTED
        } catch (_: Throwable) {
            // Fallback: try the async method for edge cases
            fallbackBluetoothCheck()
        }
    }

    /**
     * Fallback Bluetooth check using the async profile proxy approach.
     * This is only reached if the synchronous method throws an exception.
     */
    private fun fallbackBluetoothCheck(): Boolean {
        return try {
            val adapter = BluetoothAdapter.getDefaultAdapter() ?: return false
            if (!adapter.isEnabled) return false
            var connected = false
            val latch = java.util.concurrent.CountDownLatch(1)
            val profileListener = object : BluetoothProfile.ServiceListener {
                override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                    if (profile == BluetoothProfile.A2DP) {
                        connected = proxy.connectedDevices.isNotEmpty()
                    }
                    latch.countDown()
                }

                override fun onServiceDisconnected(profile: Int) {
                    latch.countDown()
                }
            }
            adapter.getProfileProxy(this, profileListener, BluetoothProfile.A2DP)
            // Wait up to 2 seconds for the async callback
            latch.await(2, java.util.concurrent.TimeUnit.SECONDS)
            connected
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * Dispatches a standard media hardware key event to the system.
     *
     * Uses AudioManager.dispatchMediaKeyEvent which routes to the current
     * active media session (e.g., Bluetooth A2DP player like Spotify).
     *
     * This method sends both KEY_DOWN and KEY_UP events to properly emulate
     * hardware media button presses.
     *
     * IMPORTANT: We do NOT request audio focus before dispatching, ensuring
     * background music continues uninterrupted.
     *
     * @param audioManager System AudioManager service
     * @param keyCode The Android KeyEvent keycode for the media action
     */
    private fun dispatchMediaKeyEvent(audioManager: AudioManager, keyCode: Int) {
        // Send both down and up events to emulate hardware button press.
        val downEvent = KeyEvent(KeyEvent.ACTION_DOWN, keyCode)
        val upEvent = KeyEvent(KeyEvent.ACTION_UP, keyCode)
        audioManager.dispatchMediaKeyEvent(downEvent)
        audioManager.dispatchMediaKeyEvent(upEvent)
    }

    /**
     * Adjusts the device (media) volume by one step, exactly like pressing the
     * hardware volume rocker. This changes the volume of the active Bluetooth
     * audio output. AUDIO_SERVICE stream is used with FLAG_SHOW_UI so the user
     * sees the system volume indicator.
     */
    private fun dispatchVolumeKey(audioManager: AudioManager, keyCode: Int) {
        val direction = if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            AudioManager.ADJUST_RAISE
        } else {
            AudioManager.ADJUST_LOWER
        }
        audioManager.adjustStreamVolume(
            AudioManager.STREAM_MUSIC,
            direction,
            AudioManager.FLAG_SHOW_UI
        )
    }

    /**
     * Reads the current track metadata (title/artist) from the active media
     * session, preferring the Bluetooth/remote player. Returns a map that the
     * Flutter UI uses for the scrolling "now playing" marquee.
     *
     * On Android 8-10 (API 26-30): Works without BLUETOOTH_CONNECT permission
     * since MediaSessionManager.getActiveSessions() is available from API 21+.
     */
    private fun getNowPlaying(sessionManager: MediaSessionManager): Map<String, String> {
        if (!hasBluetoothConnectPermission()) return mapOf("title" to "", "artist" to "")
        val controllers = sessionManager.getActiveSessions(null)
        val target = controllers.firstOrNull { isLikelyBluetooth(it) } ?: controllers.firstOrNull()
        val meta = target?.metadata
        val title = meta?.getString(android.media.MediaMetadata.METADATA_KEY_TITLE)
        val artist = meta?.getString(android.media.MediaMetadata.METADATA_KEY_ARTIST)
        return mapOf(
            "title" to (title ?: ""),
            "artist" to (artist ?: "")
        )
    }
}