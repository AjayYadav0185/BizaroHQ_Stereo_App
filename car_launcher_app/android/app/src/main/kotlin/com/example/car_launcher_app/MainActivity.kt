package com.example.car_launcher_app

import android.media.AudioManager
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
 * - MethodChannel intercepts Flutter triggers and dispatches media key events
 * - Explicitly abandons audio focus to never interrupt Bluetooth playback
 *
 * The MethodChannel 'com.carapp.media/control' handles:
 * - mediaPrevious: Skip to previous track
 * - mediaToggle: Play/Pause toggle
 * - mediaNext: Skip to next track
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.carapp.media/control"

    // Hardware media key codes for universal media control.
    private val KEYCODE_MEDIA_PLAY_PAUSE = KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
    private val KEYCODE_MEDIA_NEXT = KeyEvent.KEYCODE_MEDIA_NEXT
    private val KEYCODE_MEDIA_PREVIOUS = KeyEvent.KEYCODE_MEDIA_PREVIOUS

    /**
     * onCreate: Initialize the activity and abandon audio focus.
     *
     * CRITICAL: We abandon audio focus immediately on creation to ensure
     * this app never requests or steals focus from background Bluetooth
     * playback (Spotify, YouTube Music, etc.).
     */
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "mediaPrevious" -> {
                            dispatchMediaKeyEvent(audioManager, KEYCODE_MEDIA_PREVIOUS)
                            result.success(null)
                        }
                        "mediaToggle" -> {
                            dispatchMediaKeyEvent(audioManager, KEYCODE_MEDIA_PLAY_PAUSE)
                            result.success(null)
                        }
                        "mediaNext" -> {
                            dispatchMediaKeyEvent(audioManager, KEYCODE_MEDIA_NEXT)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (t: Throwable) {
                    result.error("MEDIA_ERROR", t.message, null)
                }
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
}