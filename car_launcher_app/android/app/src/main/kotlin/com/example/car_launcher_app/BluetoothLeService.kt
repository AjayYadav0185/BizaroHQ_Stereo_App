package com.example.car_launcher_app

import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log

/**
 * Bluetooth 5.0 BLE Service for TopWay TS7 Head Unit
 * ====================================================
 *
 * Provides Bluetooth Low Energy 5.0 support for:
 * - BLE device scanning and discovery
 * - GATT connection management
 * - BLE peripheral communication
 * - BLE beacon scanning
 * - LE Audio (if available) readiness
 *
 * TopWay TS7 uses Unisoc SC7731E with integrated Bluetooth 5.0 BLE.
 * This service leverages the Android BLE APIs available from API 18+.
 */
class BluetoothLeService : Service() {

    companion object {
        private const val TAG = "BluetoothLE"

        // BLE scan constants
        private const val SCAN_PERIOD_MS = 10000L
        private const val SCAN_INTERVAL_MS = 2000L

        // Action broadcasts
        const val ACTION_BLE_DEVICE_FOUND = "com.example.car_launcher_app.BLE_DEVICE_FOUND"
        const val ACTION_BLE_CONNECTED = "com.example.car_launcher_app.BLE_CONNECTED"
        const val ACTION_BLE_DISCONNECTED = "com.example.car_launcher_app.BLE_DISCONNECTED"
        const val ACTION_BLE_DATA_RECEIVED = "com.example.car_launcher_app.BLE_DATA_RECEIVED"
        const val ACTION_BLE_SCAN_STARTED = "com.example.car_launcher_app.BLE_SCAN_STARTED"
        const val ACTION_BLE_SCAN_STOPPED = "com.example.car_launcher_app.BLE_SCAN_STOPPED"

        // Extra keys for broadcasts
        const val EXTRA_DEVICE_ADDRESS = "device_address"
        const val EXTRA_DEVICE_NAME = "device_name"
        const val EXTRA_DEVICE_RSSI = "device_rssi"
        const val EXTRA_DATA = "data"
        const val EXTRA_STATUS = "status"
    }

    private var bluetoothManager: BluetoothManager? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bluetoothLeScanner: BluetoothLeScanner? = null
    private var bluetoothGatt: BluetoothGatt? = null
    private var isScanning = false
    private val handler = Handler(Looper.getMainLooper())

    // Connected BLE devices
    private val connectedDevices = mutableListOf<BluetoothDevice>()
    private val discoveredDevices = mutableSetOf<String>()

    // Scan callback
    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            super.onScanResult(callbackType, result)
            result?.let { processScanResult(it) }
        }

        override fun onScanFailed(errorCode: Int) {
            super.onScanFailed(errorCode)
            Log.e(TAG, "BLE scan failed with error code: $errorCode")
            isScanning = false
        }
    }

    // GATT callback
    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
            super.onConnectionStateChange(gatt, status, newState)
            val deviceAddress = gatt?.device?.address ?: "unknown"

            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    Log.d(TAG, "Connected to GATT server: $deviceAddress")
                    connectedDevices.add(gatt!!.device)
                    broadcastUpdate(ACTION_BLE_CONNECTED, deviceAddress)
                    // Discover services after connection
                    gatt?.discoverServices()
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    Log.d(TAG, "Disconnected from GATT server: $deviceAddress")
                    connectedDevices.remove(gatt?.device)
                    broadcastUpdate(ACTION_BLE_DISCONNECTED, deviceAddress)
                    gatt?.close()
                    bluetoothGatt = null
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
            super.onServicesDiscovered(gatt, status)
            if (status == BluetoothGatt.GATT_SUCCESS) {
                Log.d(TAG, "Services discovered for: ${gatt?.device?.address}")
            }
        }

        override fun onCharacteristicRead(
            gatt: BluetoothGatt?,
            characteristic: BluetoothGattCharacteristic?,
            status: Int
        ) {
            super.onCharacteristicRead(gatt, characteristic, status)
            if (status == BluetoothGatt.GATT_SUCCESS) {
                characteristic?.value?.let { value ->
                    broadcastUpdate(ACTION_BLE_DATA_RECEIVED, value)
                }
            }
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt?,
            characteristic: BluetoothGattCharacteristic?
        ) {
            super.onCharacteristicChanged(gatt, characteristic)
            characteristic?.value?.let { value ->
                broadcastUpdate(ACTION_BLE_DATA_RECEIVED, value)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        initialize()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /**
     * Initialize Bluetooth adapter and BLE scanner.
     */
    private fun initialize(): Boolean {
        bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = bluetoothManager?.adapter

        if (bluetoothAdapter == null) {
            Log.e(TAG, "Bluetooth not supported on this device")
            return false
        }

        bluetoothLeScanner = bluetoothAdapter?.bluetoothLeScanner
        return true
    }

    /**
     * Check if Bluetooth is enabled.
     */
    fun isBluetoothEnabled(): Boolean {
        return bluetoothAdapter?.isEnabled == true
    }

    /**
     * Check if BLE is supported on this device.
     */
    fun isBLESupported(): Boolean {
        return bluetoothAdapter != null && packageManager.hasSystemFeature(
            "android.hardware.bluetooth_le"
        )
    }

    /**
     * Start BLE device scanning.
     * Discovers nearby BLE peripherals.
     */
    fun startScanning(): Boolean {
        if (isScanning) return true
        if (bluetoothLeScanner == null || !isBluetoothEnabled()) return false

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setReportDelay(0)
            .apply {
                // Bluetooth 5.0 advertising extensions (API 26+)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    setLegacy(false)
                }
            }
            .build()

        discoveredDevices.clear()
        bluetoothLeScanner?.startScan(null, settings, scanCallback)
        isScanning = true

        broadcastUpdate(ACTION_BLE_SCAN_STARTED)

        // Auto-stop scanning after period
        handler.postDelayed({
            if (isScanning) {
                stopScanning()
            }
        }, SCAN_PERIOD_MS)

        Log.d(TAG, "BLE scanning started")
        return true
    }

    /**
     * Stop BLE scanning.
     */
    fun stopScanning() {
        if (!isScanning) return
        bluetoothLeScanner?.stopScan(scanCallback)
        isScanning = false
        broadcastUpdate(ACTION_BLE_SCAN_STOPPED)
        Log.d(TAG, "BLE scanning stopped")
    }

    /**
     * Check if currently scanning.
     */
    fun isScanning(): Boolean = isScanning

    /**
     * Connect to a BLE device.
     * @param address MAC address of the target BLE device
     * @param autoConnect Whether to auto-connect when device becomes available
     */
    fun connect(address: String, autoConnect: Boolean = false): Boolean {
        val device = bluetoothAdapter?.getRemoteDevice(address) ?: return false
        bluetoothGatt = device.connectGatt(this, autoConnect, gattCallback)
        return bluetoothGatt != null
    }

    /**
     * Disconnect from the current BLE device.
     */
    fun disconnect() {
        bluetoothGatt?.disconnect()
        bluetoothGatt?.close()
        bluetoothGatt = null
    }

    /**
     * Get list of connected BLE devices.
     */
    fun getConnectedDevices(): List<BluetoothDevice> = connectedDevices.toList()

    /**
     * Get discovered BLE devices from last scan.
     */
    fun getDiscoveredDevices(): Set<String> = discoveredDevices.toSet()

    /**
     * Process a scan result and broadcast it.
     */
    private fun processScanResult(result: ScanResult) {
        val device = result.device
        if (device.address == null) return

        // Avoid duplicate broadcasts within the same scan
        if (discoveredDevices.contains(device.address)) return
        discoveredDevices.add(device.address)

        val intent = Intent(ACTION_BLE_DEVICE_FOUND).apply {
            putExtra(EXTRA_DEVICE_ADDRESS, device.address)
            putExtra(EXTRA_DEVICE_NAME, device.name ?: "Unknown Device")
            putExtra(EXTRA_DEVICE_RSSI, result.rssi)
        }
        sendBroadcast(intent)
    }

    /**
     * Broadcast a BLE connection state update.
     */
    private fun broadcastUpdate(action: String, deviceAddress: String = "") {
        val intent = Intent(action).apply {
            if (deviceAddress.isNotEmpty()) {
                putExtra(EXTRA_DEVICE_ADDRESS, deviceAddress)
            }
        }
        sendBroadcast(intent)
    }

    /**
     * Broadcast BLE data received.
     */
    private fun broadcastUpdate(action: String, data: ByteArray) {
        val intent = Intent(action).apply {
            putExtra(EXTRA_DATA, data)
        }
        sendBroadcast(intent)
    }

    override fun onDestroy() {
        super.onDestroy()
        stopScanning()
        disconnect()
        handler.removeCallbacksAndMessages(null)
    }
}