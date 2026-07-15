package com.example.car_launcher_app

import android.app.Service
import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.view.KeyEvent
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Bluetooth Media Service for TopWay TS7 Head Unit
 * ==================================================
 *
 * A dedicated Android service that manages Bluetooth A2DP audio connections and
 * provides real-time media playback control. This service:
 *
 * 1. Monitors Bluetooth A2DP connection state (connect/disconnect)
 * 2. Monitors active media session for now-playing track info
 * 3. Provides transport controls (play/pause/next/prev) routed to A2DP
 * 4. Tracks Bluetooth device metadata (name, address, connection state)
 * 5. Dispatches volume controls to the A2DP audio stream
 * 6. Uses MediaSessionManager to find and control the active BT player
 *
 * This is the primary service for all Bluetooth media interactions on the
 * TopWay TS7 with SC7731E and Bluetooth 5.0 BLE.
 */
class BluetoothMediaService : Service() {

    companion object {
        private const val TAG = "BTMediaService"
        private const val POLL_INTERVAL_MS = 1500L

        // Action broadcasts for Flutter MethodChannel bridge
        const val ACTION_BT_CONNECTION_CHANGED = "com.carapp.btmedia.CONNECTION_CHANGED"
        const val ACTION_BT_TRACK_CHANGED = "com.carapp.btmedia.TRACK_CHANGED"
        const val ACTION_BT_DEVICE_CHANGED = "com.carapp.btmedia.DEVICE_CHANGED"

        const val EXTRA_CONNECTED = "connected"
        const val EXTRA_DEVICE_NAME = "device_name"
        const val EXTRA_DEVICE_ADDRESS = "device_address"
        const val EXTRA_TRACK_TITLE = "title"
        const val EXTRA_TRACK_ARTIST = "artist"
        const val EXTRA_PLAYBACK_STATE = "is_playing"
    }

    // Bluetooth state
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var a2dpProxy: BluetoothA2dp? = null
    private var connectedDevice: BluetoothDevice? = null
    private var isConnected = false
    private var isPlaying = false

    // Media session tracking
    private var mediaSessionManager: MediaSessionManager? = null
    private var audioManager: AudioManager? = null
    private var currentTitle = ""
    private var currentArtist = ""
    private var currentPackageName = ""

    // Polling
    private val handler = Handler(Looper.getMainLooper())
    private var isPolling = false

    // Connected device listeners
    private val deviceListeners = CopyOnWriteArrayList<BluetoothProfile.ServiceListener>()

    // Bluetooth broadcast receiver for connection state changes
    private val bluetoothReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                BluetoothAdapter.ACTION_CONNECTION_STATE_CHANGED -> {
                    val state = intent.getIntExtra(BluetoothAdapter.EXTRA_CONNECTION_STATE, BluetoothAdapter.STATE_DISCONNECTED)
                    val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                    handleConnectionStateChange(state, device)
                }
                BluetoothDevice.ACTION_ACL_CONNECTED -> {
                    val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                    Log.d(TAG, "ACL connected: ${device?.name}")
                }
                BluetoothDevice.ACTION_ACL_DISCONNECTED -> {
                    val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                    Log.d(TAG, "ACL disconnected: ${device?.name}")
                    if (device?.address == connectedDevice?.address) {
                        updateConnectionState(false, null)
                    }
                }
            }
        }
    }

    // A2DP profile listener for connection state
    private val a2dpServiceListener = object : BluetoothProfile.ServiceListener {
        override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
            if (profile == BluetoothProfile.A2DP) {
                a2dpProxy = proxy as BluetoothA2dp
                checkA2dpConnection()
                Log.d(TAG, "A2DP profile connected")
            }
        }

        override fun onServiceDisconnected(profile: Int) {
            if (profile == BluetoothProfile.A2DP) {
                a2dpProxy = null
                updateConnectionState(false, null)
                Log.d(TAG, "A2DP profile disconnected")
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "BluetoothMediaService created")

        bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
        audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        mediaSessionManager = getSystemService(MEDIA_SESSION_SERVICE) as MediaSessionManager

        // Register Bluetooth broadcast receivers
        val filter = IntentFilter().apply {
            addAction(BluetoothAdapter.ACTION_CONNECTION_STATE_CHANGED)
            addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
            addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
            addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        }
        registerReceiver(bluetoothReceiver, filter)

        // Connect to A2DP profile
        bluetoothAdapter?.getProfileProxy(this, a2dpServiceListener, BluetoothProfile.A2DP)

        // Start polling for media session updates
        startPolling()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Handle explicit commands if needed
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        stopPolling()
        try {
            unregisterReceiver(bluetoothReceiver)
        } catch (_: Exception) {}
        bluetoothAdapter?.closeProfileProxy(BluetoothProfile.A2DP, a2dpProxy)
        a2dpProxy = null
        Log.d(TAG, "BluetoothMediaService destroyed")
    }

    /**
     * Check A2DP connection state through the profile proxy.
     */
    private fun checkA2dpConnection() {
        try {
            val proxy = a2dpProxy ?: return
            val devices = proxy.connectedDevices
            if (devices.isNotEmpty()) {
                val device = devices[0]
                if (device != connectedDevice) {
                    updateConnectionState(true, device)
                }
            } else {
                updateConnectionState(false, null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking A2DP connection: ${e.message}")
        }
    }

    /**
     * Handle Bluetooth connection state changes from broadcast receiver.
     */
    private fun handleConnectionStateChange(state: Int, device: BluetoothDevice?) {
        when (state) {
            BluetoothAdapter.STATE_CONNECTED -> {
                Log.d(TAG, "Bluetooth connected: ${device?.name}")
                // Also verify via A2DP
                checkA2dpConnection()
            }
            BluetoothAdapter.STATE_DISCONNECTED -> {
                Log.d(TAG, "Bluetooth disconnected: ${device?.name}")
                updateConnectionState(false, null)
            }
        }
    }

    /**
     * Update the connection state and broadcast to Flutter.
     */
    private fun updateConnectionState(connected: Boolean, device: BluetoothDevice?) {
        if (connected == isConnected && device?.address == connectedDevice?.address) return

        isConnected = connected
        connectedDevice = device

        if (connected && device != null) {
            Log.d(TAG, "A2DP connected to: ${device.name} (${device.address})")
            broadcastConnectionState(true, device.name ?: "Unknown Device", device.address ?: "")
        } else {
            Log.d(TAG, "A2DP disconnected")
            currentTitle = ""
            currentArtist = ""
            currentPackageName = ""
            isPlaying = false
            broadcastConnectionState(false, "", "")
        }
    }

    /**
     * Start polling for active media session updates.
     */
    private fun startPolling() {
        if (isPolling) return
        isPolling = true
        pollMediaSession()
    }

    /**
     * Stop polling.
     */
    private fun stopPolling() {
        isPolling = false
        handler.removeCallbacksAndMessages(null)
    }

    /**
     * Poll the active media session for now-playing metadata.
     * Uses MediaSessionManager to read the current track info from
     * whatever A2DP media player is active (Spotify, YouTube Music, etc).
     */
    private fun pollMediaSession() {
        if (!isPolling) return

        try {
            // Check A2DP connection state periodically
            if (a2dpProxy != null) {
                checkA2dpConnection()
            }

            if (isConnected) {
                // Read active media session metadata
                val controllers = mediaSessionManager?.getActiveSessions(null) ?: emptyList()

                // Find the Bluetooth/A2DP media session
                val targetController = findBluetoothMediaSession(controllers)

                if (targetController != null) {
                    val packageName = targetController.packageName ?: ""
                    val meta = targetController.metadata
                    val playbackState = targetController.playbackState

                    val title = meta?.getString(android.media.MediaMetadata.METADATA_KEY_TITLE) ?: ""
                    val artist = meta?.getString(android.media.MediaMetadata.METADATA_KEY_ARTIST) ?: ""

                    // Check playback state
                    val state = playbackState?.state ?: android.media.session.PlaybackState.STATE_NONE
                    val playing = (state == android.media.session.PlaybackState.STATE_PLAYING)

                    // Update if changed
                    if (title != currentTitle || artist != currentArtist || playing != isPlaying || packageName != currentPackageName) {
                        currentTitle = title
                        currentArtist = artist
                        isPlaying = playing
                        currentPackageName = packageName
                        broadcastTrackChange()
                    }
                } else if (currentTitle.isNotEmpty() || currentArtist.isNotEmpty()) {
                    // No active session found but we have data - clear it
                    currentTitle = ""
                    currentArtist = ""
                    isPlaying = false
                    currentPackageName = ""
                    broadcastTrackChange()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error polling media session: ${e.message}")
        }

        // Schedule next poll
        handler.postDelayed({ pollMediaSession() }, POLL_INTERVAL_MS)
    }

    /**
     * Find the active Bluetooth/A2DP media session from the list of controllers.
     * Prefers sessions from known media apps or Bluetooth packages.
     */
    private fun findBluetoothMediaSession(controllers: List<MediaController>): MediaController? {
        if (controllers.isEmpty()) return null

        // First, look for a Bluetooth-specific session
        val btSession = controllers.firstOrNull { controller ->
            val pkg = controller.packageName ?: ""
            pkg.contains("bluetooth", ignoreCase = true) ||
            pkg.contains("a2dp", ignoreCase = true)
        }
        if (btSession != null) return btSession

        // Next, look for known media apps
        val mediaApp = controllers.firstOrNull { controller ->
            val pkg = controller.packageName ?: ""
            pkg.contains("spotify", ignoreCase = true) ||
            pkg.contains("youtube", ignoreCase = true) ||
            pkg.contains("music", ignoreCase = true) ||
            pkg.contains("player", ignoreCase = true) ||
            pkg.contains("pandora", ignoreCase = true) ||
            pkg.contains("deezer", ignoreCase = true) ||
            pkg.contains("tidal", ignoreCase = true)
        }
        if (mediaApp != null) return mediaApp

        // Fall back to any active session that is not our own
        return controllers.firstOrNull { controller ->
            controller.packageName != packageName &&
            controller.playbackState?.state != android.media.session.PlaybackState.STATE_NONE
        }
    }

    // ---- PUBLIC API FOR FLUTTER BRIDGE ----

    /**
     * Check if a Bluetooth A2DP device is currently connected.
     */
    fun isBluetoothConnected(): Boolean = isConnected

    /**
     * Get the name of the connected Bluetooth device.
     */
    fun getConnectedDeviceName(): String = connectedDevice?.name ?: ""

    /**
     * Get the address of the connected Bluetooth device.
     */
    fun getConnectedDeviceAddress(): String = connectedDevice?.address ?: ""

    /**
     * Get the current track title.
     */
    fun getCurrentTitle(): String = currentTitle

    /**
     * Get the current track artist.
     */
    fun getCurrentArtist(): String = currentArtist

    /**
     * Check if media is currently playing.
     */
    fun isMediaPlaying(): Boolean = isPlaying

    /**
     * Get the package name of the active media player.
     */
    fun getActivePackageName(): String = currentPackageName

    /**
     * Dispatches a PLAY/PAUSE toggle command to the active A2DP media session.
     * Uses MediaSessionManager TransportControls if available, falls back
     * to hardware key event dispatch via AudioManager.
     */
    fun togglePlayPause() {
        try {
            val controllers = mediaSessionManager?.getActiveSessions(null) ?: emptyList()
            val target = findBluetoothMediaSession(controllers)
            if (target != null) {
                if (isPlaying) {
                    target.transportControls.pause()
                } else {
                    target.transportControls.play()
                }
                Log.d(TAG, "Toggled play/pause via transport controls")
            } else {
                // Fallback to hardware key event
                dispatchMediaKeyEvent(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
                Log.d(TAG, "Toggled play/pause via hardware key")
            }
        } catch (e: Exception) {
            // Fallback
            dispatchMediaKeyEvent(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
        }
    }

    /**
     * Skip to the next track on the active A2DP media session.
     */
    fun nextTrack() {
        try {
            val controllers = mediaSessionManager?.getActiveSessions(null) ?: emptyList()
            val target = findBluetoothMediaSession(controllers)
            if (target != null) {
                target.transportControls.skipToNext()
            } else {
                dispatchMediaKeyEvent(KeyEvent.KEYCODE_MEDIA_NEXT)
            }
        } catch (_: Exception) {
            dispatchMediaKeyEvent(KeyEvent.KEYCODE_MEDIA_NEXT)
        }
    }

    /**
     * Skip to the previous track on the active A2DP media session.
     */
    fun previousTrack() {
        try {
            val controllers = mediaSessionManager?.getActiveSessions(null) ?: emptyList()
            val target = findBluetoothMediaSession(controllers)
            if (target != null) {
                target.transportControls.skipToPrevious()
            } else {
                dispatchMediaKeyEvent(KeyEvent.KEYCODE_MEDIA_PREVIOUS)
            }
        } catch (_: Exception) {
            dispatchMediaKeyEvent(KeyEvent.KEYCODE_MEDIA_PREVIOUS)
        }
    }

    /**
     * Adjust the volume of the A2DP audio stream.
     */
    fun adjustVolume(up: Boolean) {
        val direction = if (up) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER
        audioManager?.adjustStreamVolume(AudioManager.STREAM_MUSIC, direction, AudioManager.FLAG_SHOW_UI)
    }

    /**
     * Dispatch a hardware media key event through AudioManager.
     * This is the most reliable way to control A2DP playback on Android 8-10.
     */
    private fun dispatchMediaKeyEvent(keyCode: Int) {
        audioManager?.let { am ->
            val downEvent = KeyEvent(KeyEvent.ACTION_DOWN, keyCode)
            val upEvent = KeyEvent(KeyEvent.ACTION_UP, keyCode)
            am.dispatchMediaKeyEvent(downEvent)
            am.dispatchMediaKeyEvent(upEvent)
        }
    }

    /**
     * Broadcast Bluetooth connection state to Flutter.
     */
    private fun broadcastConnectionState(connected: Boolean, deviceName: String, deviceAddress: String) {
        val intent = Intent(ACTION_BT_CONNECTION_CHANGED).apply {
            putExtra(EXTRA_CONNECTED, connected)
            putExtra(EXTRA_DEVICE_NAME, deviceName)
            putExtra(EXTRA_DEVICE_ADDRESS, deviceAddress)
        }
        sendBroadcast(intent)
    }

    /**
     * Broadcast track change to Flutter.
     */
    private fun broadcastTrackChange() {
        val intent = Intent(ACTION_BT_TRACK_CHANGED).apply {
            putExtra(EXTRA_TRACK_TITLE, currentTitle)
            putExtra(EXTRA_TRACK_ARTIST, currentArtist)
            putExtra(EXTRA_PLAYBACK_STATE, isPlaying)
        }
        sendBroadcast(intent)
    }
}