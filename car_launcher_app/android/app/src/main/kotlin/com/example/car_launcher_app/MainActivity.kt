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
 * Requirements from the task:
 * - singleInstance mode so it behaves like a system home launcher.
 * - MethodChannel intercepts Flutter triggers and sends media key events.
 * - Never request or steal audio focus.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.carapp.media/control"

    // Ensures launcher behaves like a system home host.
    // We use singleInstance mode on the Activity in AndroidManifest.


    // Hardware media key codes.
    private val KEYCODE_MEDIA_PLAY_PAUSE = KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
    private val KEYCODE_MEDIA_NEXT = KeyEvent.KEYCODE_MEDIA_NEXT
    private val KEYCODE_MEDIA_PREVIOUS = KeyEvent.KEYCODE_MEDIA_PREVIOUS

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // CRITICAL: ensure we do not request audio focus.
        // This app must never steal focus from Bluetooth playback.
        val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        audioManager.abandonAudioFocus(null)
    }

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
     * Dispatches a standard media hardware key event.
     *
     * Uses AudioManager.dispatchMediaKeyEvent which routes to the current
     * system media session (e.g., Bluetooth A2DP player).
     *
     * NOTE: We intentionally do NOT request audio focus.
     */
    private fun dispatchMediaKeyEvent(audioManager: AudioManager, keyCode: Int) {
        // Send both down/up to emulate hardware.
        val down = KeyEvent(KeyEvent.ACTION_DOWN, keyCode)
        val up = KeyEvent(KeyEvent.ACTION_UP, keyCode)
        audioManager.dispatchMediaKeyEvent(down)
        audioManager.dispatchMediaKeyEvent(up)
    }
}

