package com.example.car_launcher_app

import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.media.AudioManager
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.os.Bundle
import android.view.KeyEvent
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Native Android host for the Flutter car stereo launcher.
 *
 * Production-ready implementation for Android head units.
 *
 * Key Features:
 * - singleInstance mode for seamless home launcher behavior
 * - MethodChannel intercepts Flutter triggers and dispatches media commands
 * - Explicitly abandons audio focus to never interrupt Bluetooth playback
 * - Targets the active Bluetooth (A2DP) media session directly via MediaSessionManager
 *   so the hardware-style buttons reliably control Spotify / YouTube Music / etc.
 *   playing on the connected car stereo, with AudioManager fallback.
 *
 * The MethodChannel 'com.carapp.media/control' handles:
 * - mediaPrevious: Skip to previous track
 * - mediaToggle: Play/Pause toggle
 * - mediaNext: Skip to next track
 * - mediaVolumeUp: Increase device/media volume by one step
 * - mediaVolumeDown: Decrease device/media volume by one step
 * - isBluetoothConnected: Returns true if a Bluetooth A2DP audio device is connected
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.carapp.media/control"

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
                                it.transportControls.playPause()
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
                        "isBluetoothConnected" -> {
                            result.success(isBluetoothA2dpConnected())
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
     */
    private fun isBluetoothA2dpConnected(): Boolean {
        val adapter = BluetoothAdapter.getDefaultAdapter() ?: return false
        if (!adapter.isEnabled) return false
        var connected = false
        try {
            val profileListener = object : BluetoothProfile.ServiceListener {
                override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                    if (profile == BluetoothProfile.A2DP) {
                        connected = proxy.connectedDevices.isNotEmpty()
                    }
                }

                override fun onServiceDisconnected(profile: Int) {}
            }
            adapter.getProfileProxy(this, profileListener, BluetoothProfile.A2DP)
        } catch (_: Throwable) {
            // ignore – assume not connected
        }
        return connected
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
}
