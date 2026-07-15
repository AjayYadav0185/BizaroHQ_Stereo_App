package com.example.car_launcher_app

import android.app.Service
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.os.IBinder
import java.io.File
import java.io.RandomAccessFile

/**
 * PT2313 Audio IC Service for TopWay TS7 Head Unit
 * ==================================================
 *
 * The PT2313 is a 4-channel audio processor with I2C control interface
 * commonly used in car head units. It provides:
 * - Volume control (0-63 steps)
 * - Bass boost
 * - Treble control
 * - Balance (left/right)
 * - Fader (front/rear)
 * - Mute function
 * - Input source selection (4 channels)
 *
 * On TopWay TS7 (SC7731E), the PT2313 is typically controlled via
 * I2C bus (SDA/SCL) through the kernel's I2C device interface or
 * through the device's sysfs/audio control nodes.
 *
 * This implementation provides:
 * 1. Direct I2C control via /dev/i2c-* (requires root on some devices)
 * 2. Sysfs-based audio control (common on TopWay/Ts7 units)
 * 3. Android AudioManager fallback for volume
 */
class PT2313AudioService : Service() {

    companion object {
        private const val TAG = "PT2313Audio"

        // PT2313 I2C address (0x44 or 0x84 depending on ADDR pin)
        private const val PT2313_I2C_ADDR = 0x44

        // PT2313 register addresses
        private const val REG_INPUT_SEL = 0x00
        private const val REG_VOLUME = 0x40
        private const val REG_BASS = 0x60
        private const val REG_TREBLE = 0x70
        private const val REG_BALANCE = 0x80
        private const val REG_FADER = 0x90
        private const val REG_ATTENUATION = 0xA0

        // Input source selection values
        const val INPUT_SOURCE_1 = 0x00  // Typically Radio
        const val INPUT_SOURCE_2 = 0x01  // Typically USB/SD
        const val INPUT_SOURCE_3 = 0x02  // Typically AUX
        const val INPUT_SOURCE_4 = 0x03  // Typically Bluetooth

        // Sysfs control paths common on TopWay/Ts7 devices
        private val SYSFS_PATHS = listOf(
            "/sys/class/audio/volume",
            "/sys/devices/platform/audio/volume",
            "/sys/class/misc/audio/volume",
            "/proc/audio/volume"
        )

        // I2C device paths
        private val I2C_DEVICES = listOf(
            "/dev/i2c-0",
            "/dev/i2c-1",
            "/dev/i2c-2",
            "/dev/i2c-3"
        )

        // Default audio settings for car stereo
        const val DEFAULT_VOLUME = 40     // 0-63 range
        const val DEFAULT_BASS = 8        // 0-14 range
        const val DEFAULT_TREBLE = 8      // 0-14 range
        const val DEFAULT_BALANCE = 0     // -7 to +7 (0 = center)
        const val DEFAULT_FADER = 0       // -7 to +7 (0 = center)
    }

    private var audioManager: AudioManager? = null
    private var currentVolume = DEFAULT_VOLUME
    private var currentBass = DEFAULT_BASS
    private var currentTreble = DEFAULT_TREBLE
    private var currentBalance = DEFAULT_BALANCE
    private var currentFader = DEFAULT_FADER
    private var currentInputSource = INPUT_SOURCE_1
    private var isMuted = false
    private var mutedVolume = DEFAULT_VOLUME

    override fun onCreate() {
        super.onCreate()
        audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        initializePT2313()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /**
     * Initialize the PT2313 audio IC with default settings.
     * Attempts I2C direct control first, falls back to sysfs, then AudioManager.
     */
    private fun initializePT2313() {
        try {
            // Try I2C direct control
            if (initI2C()) {
                setVolume(DEFAULT_VOLUME)
                setBass(DEFAULT_BASS)
                setTreble(DEFAULT_TREBLE)
                setBalance(DEFAULT_BALANCE)
                setFader(DEFAULT_FADER)
                return
            }

            // Fallback to sysfs
            if (initSysfs()) {
                setVolumeSysfs(DEFAULT_VOLUME)
                return
            }

            // Final fallback: Android AudioManager
            initAudioManager()
        } catch (_: Exception) {
            initAudioManager()
        }
    }

    /**
     * Initialize I2C communication with PT2313.
     * Requires root access on most devices.
     */
    private fun initI2C(): Boolean {
        for (i2cPath in I2C_DEVICES) {
            try {
                val file = File(i2cPath)
                if (file.exists() && file.canWrite()) {
                    return true
                }
            } catch (_: Exception) {
                continue
            }
        }
        return false
    }

    /**
     * Write a byte to the PT2313 via I2C.
     */
    private fun writeI2C(data: Int): Boolean {
        for (i2cPath in I2C_DEVICES) {
            try {
                val file = File(i2cPath)
                if (file.exists()) {
                    // I2C write: address + data byte
                    // Format depends on kernel driver implementation
                    RandomAccessFile(file, "rw").use { raf ->
                        raf.writeByte(PT2313_I2C_ADDR)
                        raf.writeByte(data)
                    }
                    return true
                }
            } catch (_: Exception) {
                continue
            }
        }
        return false
    }

    /**
     * Initialize sysfs-based audio control.
     * Common on TopWay/Ts7 devices with kernel audio drivers.
     */
    private fun initSysfs(): Boolean {
        for (path in SYSFS_PATHS) {
            try {
                val file = File(path)
                if (file.exists() && file.canWrite()) {
                    return true
                }
            } catch (_: Exception) {
                continue
            }
        }
        return false
    }

    /**
     * Write volume to sysfs control node.
     */
    private fun setVolumeSysfs(volume: Int): Boolean {
        val clampedVolume = volume.coerceIn(0, 63)
        for (path in SYSFS_PATHS) {
            try {
                val file = File(path)
                if (file.exists()) {
                    file.writeText(clampedVolume.toString())
                    return true
                }
            } catch (_: Exception) {
                continue
            }
        }
        return false
    }

    /**
     * Initialize Android AudioManager as fallback.
     */
    private fun initAudioManager() {
        audioManager?.let { am ->
            val maxVol = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            val targetVol = (DEFAULT_VOLUME * maxVol) / 63
            am.setStreamVolume(AudioManager.STREAM_MUSIC, targetVol, 0)
        }
    }

    /**
     * Set master volume (0-63).
     * PT2313 volume register: 0x40 | (63 - volume)
     */
    fun setVolume(volume: Int): Boolean {
        currentVolume = volume.coerceIn(0, 63)
        isMuted = false

        // Try I2C direct control
        val i2cData = REG_VOLUME or (63 - currentVolume)
        if (writeI2C(i2cData)) return true

        // Try sysfs
        if (setVolumeSysfs(currentVolume)) return true

        // Fallback to AudioManager
        audioManager?.let { am ->
            val maxVol = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            val targetVol = (currentVolume * maxVol) / 63
            am.setStreamVolume(AudioManager.STREAM_MUSIC, targetVol, 0)
        }
        return true
    }

    /**
     * Get current volume level (0-63).
     */
    fun getVolume(): Int = currentVolume

    /**
     * Mute/unmute audio.
     * PT2313 mute: sets volume to 0 (attenuation register)
     */
    fun setMute(mute: Boolean) {
        if (mute && !isMuted) {
            mutedVolume = currentVolume
            isMuted = true
            // Set attenuation (mute) via I2C
            writeI2C(REG_ATTENUATION or 0x01)
            // Also try sysfs
            setVolumeSysfs(0)
            // AudioManager fallback
            audioManager?.setStreamVolume(AudioManager.STREAM_MUSIC, 0, 0)
        } else if (!mute && isMuted) {
            isMuted = false
            // Remove attenuation
            writeI2C(REG_ATTENUATION or 0x00)
            setVolume(mutedVolume)
        }
    }

    /**
     * Check if audio is muted.
     */
    fun isMuted(): Boolean = isMuted

    /**
     * Set bass level (0-14).
     * PT2313 bass register: 0x60 | bass_value
     */
    fun setBass(bass: Int): Boolean {
        currentBass = bass.coerceIn(0, 14)
        return writeI2C(REG_BASS or currentBass)
    }

    /**
     * Get current bass level.
     */
    fun getBass(): Int = currentBass

    /**
     * Set treble level (0-14).
     * PT2313 treble register: 0x70 | treble_value
     */
    fun setTreble(treble: Int): Boolean {
        currentTreble = treble.coerceIn(0, 14)
        return writeI2C(REG_TREBLE or currentTreble)
    }

    /**
     * Get current treble level.
     */
    fun getTreble(): Int = currentTreble

    /**
     * Set balance (-7 to +7, 0 = center).
     * PT2313 balance register: 0x80 | (balance + 7)
     */
    fun setBalance(balance: Int): Boolean {
        currentBalance = balance.coerceIn(-7, 7)
        return writeI2C(REG_BALANCE or (currentBalance + 7))
    }

    /**
     * Get current balance.
     */
    fun getBalance(): Int = currentBalance

    /**
     * Set fader (-7 to +7, 0 = center).
     * PT2313 fader register: 0x90 | (fader + 7)
     */
    fun setFader(fader: Int): Boolean {
        currentFader = fader.coerceIn(-7, 7)
        return writeI2C(REG_FADER or (currentFader + 7))
    }

    /**
     * Get current fader.
     */
    fun getFader(): Int = currentFader

    /**
     * Select audio input source.
     * 0 = Radio, 1 = USB/SD, 2 = AUX, 3 = Bluetooth
     */
    fun setInputSource(source: Int): Boolean {
        currentInputSource = source.coerceIn(0, 3)
        return writeI2C(REG_INPUT_SEL or currentInputSource)
    }

    /**
     * Get current input source.
     */
    fun getInputSource(): Int = currentInputSource

    /**
     * Get available input sources as display names.
     */
    fun getInputSourceNames(): Map<Int, String> = mapOf(
        INPUT_SOURCE_1 to "Radio",
        INPUT_SOURCE_2 to "USB/SD",
        INPUT_SOURCE_3 to "AUX",
        INPUT_SOURCE_4 to "Bluetooth"
    )

    /**
     * Reset PT2313 to default settings.
     */
    fun resetToDefaults() {
        setVolume(DEFAULT_VOLUME)
        setBass(DEFAULT_BASS)
        setTreble(DEFAULT_TREBLE)
        setBalance(DEFAULT_BALANCE)
        setFader(DEFAULT_FADER)
        setInputSource(INPUT_SOURCE_1)
        setMute(false)
    }
}