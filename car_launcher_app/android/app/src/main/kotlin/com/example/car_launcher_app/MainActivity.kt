package com.example.car_launcher_app

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.KeyEvent
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Native Android host for the Flutter BizaroHQ Stereo.
 *
 * Production-ready implementation for TopWay TS7 head unit (API 26-28 / Android 8-9).
 * Unisoc SC7731E ARMv7 processor, PT2313 Audio IC, Bluetooth 5.0 BLE.
 *
 * Key Features:
 * - singleInstance mode for seamless home launcher behavior
 * - MethodChannel intercepts Flutter triggers and dispatches media commands
 * - Explicitly abandons audio focus to never interrupt Bluetooth playback
 * - Targets the active Bluetooth (A2DP) media session directly via MediaSessionManager
 * - PT2313 Audio IC control (volume, bass, treble, balance, fader, mute, input)
 * - Bluetooth 5.0 BLE scanning and connectivity
 * - Dedicated Bluetooth A2DP Media Service with real-time track monitoring
 * - Synchronous Bluetooth A2DP connection detection
 * - Proper API level guards for Android 8-10 (API 26-30) compatibility
 *
 * MethodChannel 'com.carapp.btmedia/control' handles ALL Bluetooth A2DP media:
 * - bt_isConnected: Check if A2DP device is connected
 * - bt_getDeviceName: Get connected device name
 * - bt_getDeviceAddress: Get connected device address
 * - bt_getTrackTitle: Get current track title
 * - bt_getTrackArtist: Get current track artist
 * - bt_isPlaying: Check if media is currently playing
 * - bt_getActivePackage: Get active media player package name
 * - bt_playPause: Toggle play/pause
 * - bt_next: Skip to next track
 * - bt_previous: Skip to previous track
 * - bt_volumeUp: Raise volume
 * - bt_volumeDown: Lower volume
 *
 * MethodChannel 'com.carapp.audio/pt2313' handles PT2313 hardware audio IC
 * MethodChannel 'com.carapp.ble/control' handles BLE 5.0
 */
class MainActivity : FlutterActivity() {

    private val btMediaChannelName = "com.carapp.btmedia/control"
    private val pt2313ChannelName = "com.carapp.audio/pt2313"
    private val bleChannelName = "com.carapp.ble/control"

    companion object {
        private const val BT_PERMISSION_REQUEST_CODE = 1001
        private const val TAG = "BizaroHQ"
    }

    // PT2313 Audio service instance
    private var pt2313Service: PT2313AudioService? = null

    // BLE service instance
    private var bleService: BluetoothLeService? = null

    // Bluetooth A2DP media service - dedicated BT media controller
    private var btMediaService: BluetoothMediaService? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Abandon audio focus to prevent interrupting Bluetooth playback
        val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        audioManager.abandonAudioFocus(null)

        // Initialize PT2313 Audio IC service
        initPT2313Audio()

        // Initialize Bluetooth 5.0 BLE service
        initBluetoothLE()

        // Initialize dedicated Bluetooth A2DP Media Service
        initBluetoothMedia()

        // Request Bluetooth permission (Android 12+)
        requestBluetoothPermission()

        Log.d(TAG, "=== BizaroHQ Stereo initialized for TopWay TS7 ===")
        Log.d(TAG, "PT2313 Audio IC: ${if (pt2313Service != null) "OK" else "FAILED"}")
        Log.d(TAG, "Bluetooth 5.0 BLE: ${if (bleService != null) "OK" else "FAILED"}")
        Log.d(TAG, "Bluetooth A2DP Media: ${if (btMediaService != null) "OK" else "FAILED"}")
    }

    private fun initPT2313Audio() {
        try {
            pt2313Service = PT2313AudioService()
            pt2313Service?.onCreate()
        } catch (e: Exception) {
            Log.e(TAG, "PT2313 init failed: ${e.message}")
            pt2313Service = null
        }
    }

    private fun initBluetoothLE() {
        try {
            bleService = BluetoothLeService()
            bleService?.onCreate()
            val bleIntent = Intent(this, BluetoothLeService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(bleIntent)
            } else {
                startService(bleIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "BLE init failed: ${e.message}")
            bleService = null
        }
    }

    /**
     * Initialize the dedicated Bluetooth A2DP Media Service.
     * This service handles all Bluetooth media interactions:
     * - Real-time A2DP connection monitoring via BroadcastReceiver
     * - Active media session polling for now-playing track info
     * - Transport controls (play/pause/next/prev) routed to A2DP
     */
    private fun initBluetoothMedia() {
        try {
            btMediaService = BluetoothMediaService()
            btMediaService?.onCreate()
            val btIntent = Intent(this, BluetoothMediaService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(btIntent)
            } else {
                startService(btIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "BT Media init failed: ${e.message}")
            btMediaService = null
        }
    }

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
    }

    /**
     * configureFlutterEngine: Set up MethodChannels for BT media, PT2313, and BLE control.
     */
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ---- BLUETOOTH A2DP MEDIA CONTROL CHANNEL (Primary BT media control) ----
        // All Bluetooth media playback commands go through this dedicated channel.
        // The BluetoothMediaService handles real-time A2DP connection monitoring,
        // now-playing track polling, and transport controls.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, btMediaChannelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        // Connection state
                        "bt_isConnected" -> {
                            result.success(btMediaService?.isBluetoothConnected() ?: false)
                        }
                        "bt_getDeviceName" -> {
                            result.success(btMediaService?.getConnectedDeviceName() ?: "")
                        }
                        "bt_getDeviceAddress" -> {
                            result.success(btMediaService?.getConnectedDeviceAddress() ?: "")
                        }

                        // Now-playing metadata
                        "bt_getTrackTitle" -> {
                            result.success(btMediaService?.getCurrentTitle() ?: "")
                        }
                        "bt_getTrackArtist" -> {
                            result.success(btMediaService?.getCurrentArtist() ?: "")
                        }
                        "bt_isPlaying" -> {
                            result.success(btMediaService?.isMediaPlaying() ?: false)
                        }
                        "bt_getActivePackage" -> {
                            result.success(btMediaService?.getActivePackageName() ?: "")
                        }

                        // Transport controls - routed to A2DP via MediaService
                        "bt_playPause" -> {
                            btMediaService?.togglePlayPause()
                            result.success(true)
                        }
                        "bt_next" -> {
                            btMediaService?.nextTrack()
                            result.success(true)
                        }
                        "bt_previous" -> {
                            btMediaService?.previousTrack()
                            result.success(true)
                        }

                        // Volume control - routed to A2DP audio stream
                        "bt_volumeUp" -> {
                            btMediaService?.adjustVolume(true)
                            result.success(true)
                        }
                        "bt_volumeDown" -> {
                            btMediaService?.adjustVolume(false)
                            result.success(true)
                        }

                        else -> result.notImplemented()
                    }
                } catch (t: Throwable) {
                    result.error("BT_MEDIA_ERROR", t.message, null)
                }
            }

        // ---- PT2313 AUDIO IC CHANNEL ----
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pt2313ChannelName)
            .setMethodCallHandler { call, result ->
                if (pt2313Service == null) {
                    result.error("PT2313_ERROR", "PT2313 Audio IC not available", null)
                    return@setMethodCallHandler
                }

                try {
                    when (call.method) {
                        "pt2313_setVolume" -> {
                            val volume = call.argument<Int>("volume") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "volume required", null)
                            pt2313Service?.setVolume(volume)
                            result.success(true)
                        }
                        "pt2313_getVolume" -> result.success(pt2313Service?.getVolume() ?: 0)
                        "pt2313_setMute" -> {
                            val mute = call.argument<Boolean>("mute") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "mute required", null)
                            pt2313Service?.setMute(mute)
                            result.success(true)
                        }
                        "pt2313_isMuted" -> result.success(pt2313Service?.isMuted() ?: false)
                        "pt2313_setBass" -> {
                            val bass = call.argument<Int>("bass") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "bass required", null)
                            result.success(pt2313Service?.setBass(bass) ?: false)
                        }
                        "pt2313_getBass" -> result.success(pt2313Service?.getBass() ?: 8)
                        "pt2313_setTreble" -> {
                            val treble = call.argument<Int>("treble") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "treble required", null)
                            result.success(pt2313Service?.setTreble(treble) ?: false)
                        }
                        "pt2313_getTreble" -> result.success(pt2313Service?.getTreble() ?: 8)
                        "pt2313_setBalance" -> {
                            val balance = call.argument<Int>("balance") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "balance required", null)
                            result.success(pt2313Service?.setBalance(balance) ?: false)
                        }
                        "pt2313_getBalance" -> result.success(pt2313Service?.getBalance() ?: 0)
                        "pt2313_setFader" -> {
                            val fader = call.argument<Int>("fader") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "fader required", null)
                            result.success(pt2313Service?.setFader(fader) ?: false)
                        }
                        "pt2313_getFader" -> result.success(pt2313Service?.getFader() ?: 0)
                        "pt2313_setInputSource" -> {
                            val source = call.argument<Int>("source") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "source required", null)
                            result.success(pt2313Service?.setInputSource(source) ?: false)
                        }
                        "pt2313_getInputSource" -> result.success(pt2313Service?.getInputSource() ?: 0)
                        "pt2313_getInputSourceNames" -> result.success(pt2313Service?.getInputSourceNames() ?: emptyMap<Int, String>())
                        "pt2313_reset" -> {
                            pt2313Service?.resetToDefaults()
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (t: Throwable) {
                    result.error("PT2313_ERROR", t.message, null)
                }
            }

        // ---- BLUETOOTH LE CHANNEL ----
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, bleChannelName)
            .setMethodCallHandler { call, result ->
                if (bleService == null) {
                    result.error("BLE_ERROR", "Bluetooth LE not available", null)
                    return@setMethodCallHandler
                }

                try {
                    when (call.method) {
                        "ble_isSupported" -> result.success(bleService?.isBLESupported() ?: false)
                        "ble_isEnabled" -> result.success(bleService?.isBluetoothEnabled() ?: false)
                        "ble_startScan" -> result.success(bleService?.startScanning() ?: false)
                        "ble_stopScan" -> {
                            bleService?.stopScanning()
                            result.success(true)
                        }
                        "ble_isScanning" -> result.success(bleService?.isScanning() ?: false)
                        "ble_connect" -> {
                            val address = call.argument<String>("address") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "address required", null)
                            val autoConnect = call.argument<Boolean>("autoConnect") ?: false
                            result.success(bleService?.connect(address, autoConnect) ?: false)
                        }
                        "ble_disconnect" -> {
                            bleService?.disconnect()
                            result.success(true)
                        }
                        "ble_getConnectedDevices" -> {
                            val devices = bleService?.getConnectedDevices()?.map {
                                mapOf("address" to it.address, "name" to (it.name ?: "Unknown"))
                            } ?: emptyList()
                            result.success(devices)
                        }
                        "ble_getDiscoveredDevices" -> result.success(bleService?.getDiscoveredDevices()?.toList() ?: emptyList<String>())
                        else -> result.notImplemented()
                    }
                } catch (t: Throwable) {
                    result.error("BLE_ERROR", t.message, null)
                }
            }
    }
}