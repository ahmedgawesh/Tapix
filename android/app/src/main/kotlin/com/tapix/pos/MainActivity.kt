package com.tapix.pos

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
    private companion object {
        const val BLUETOOTH_CHANNEL = "com.tapix.pos/bluetooth_label_printer"
        const val MASTER_KEEP_ALIVE_CHANNEL = "com.tapix.pos/master_keep_alive"
        const val BLUETOOTH_PERMISSION_REQUEST = 7012
        const val NOTIFICATION_PERMISSION_REQUEST = 7013
        val SERIAL_PORT_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }

    private val bluetoothExecutor = Executors.newSingleThreadExecutor()
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingPermissionAction: (() -> Unit)? = null
    private var pendingMasterResult: MethodChannel.Result? = null
    private var pendingMasterPort: Int? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BLUETOOTH_CHANNEL,
        ).setMethodCallHandler(::handleBluetoothCall)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MASTER_KEEP_ALIVE_CHANNEL,
        ).setMethodCallHandler(::handleMasterKeepAliveCall)
    }

    private fun handleMasterKeepAliveCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val port = call.argument<Int>("port")
                if (port == null || port !in 1..65535) {
                    result.error("invalid_port", "A valid master port is required", null)
                    return
                }
                if (
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                    checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                        PackageManager.PERMISSION_GRANTED
                ) {
                    if (pendingMasterResult != null) {
                        result.error(
                            "permission_request_busy",
                            "A notification permission request is already active",
                            null,
                        )
                        return
                    }
                    pendingMasterResult = result
                    pendingMasterPort = port
                    requestPermissions(
                        arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                        NOTIFICATION_PERMISSION_REQUEST,
                    )
                } else {
                    startMasterKeepAlive(port, result, notificationPermissionGranted = true)
                }
            }
            "stop" -> {
                MasterKeepAliveService.stop(this)
                result.success(null)
            }
            "isRunning" -> result.success(MasterKeepAliveService.isRunning)
            else -> result.notImplemented()
        }
    }

    private fun startMasterKeepAlive(
        port: Int,
        result: MethodChannel.Result,
        notificationPermissionGranted: Boolean,
    ) {
        try {
            MasterKeepAliveService.start(this, port)
            result.success(
                mapOf("notificationPermissionGranted" to notificationPermissionGranted),
            )
        } catch (error: Exception) {
            result.error(
                "master_keep_alive_failed",
                error.message ?: "Could not keep the master service active",
                error.javaClass.simpleName,
            )
        }
    }

    private fun handleBluetoothCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getBondedDevices" -> withBluetoothConnectPermission(result) {
                listBondedDevices(result)
            }
            "printRaw" -> withBluetoothConnectPermission(result) {
                val address = call.argument<String>("address")
                val data = call.argument<ByteArray>("data")
                if (address.isNullOrBlank() || data == null || data.isEmpty()) {
                    result.error("invalid_arguments", "Printer address or print data is missing", null)
                } else {
                    printRaw(address, data, result)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun withBluetoothConnectPermission(
        result: MethodChannel.Result,
        action: () -> Unit,
    ) {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingPermissionResult != null) {
                result.error("permission_request_busy", "A Bluetooth permission request is already active", null)
                return
            }
            pendingPermissionResult = result
            pendingPermissionAction = action
            requestPermissions(
                arrayOf(Manifest.permission.BLUETOOTH_CONNECT),
                BLUETOOTH_PERMISSION_REQUEST,
            )
            return
        }
        action()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST) {
            val result = pendingMasterResult
            val port = pendingMasterPort
            pendingMasterResult = null
            pendingMasterPort = null
            if (result != null && port != null) {
                val granted =
                    grantResults.isNotEmpty() &&
                        grantResults[0] == PackageManager.PERMISSION_GRANTED
                startMasterKeepAlive(port, result, notificationPermissionGranted = granted)
            }
            return
        }
        if (requestCode != BLUETOOTH_PERMISSION_REQUEST) return

        val result = pendingPermissionResult
        val action = pendingPermissionAction
        pendingPermissionResult = null
        pendingPermissionAction = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            action?.invoke()
        } else {
            result?.error("bluetooth_permission_denied", "Nearby devices permission was denied", null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun listBondedDevices(result: MethodChannel.Result) {
        val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
        if (adapter == null) {
            result.error("bluetooth_unavailable", "Bluetooth is not supported on this device", null)
            return
        }
        if (!adapter.isEnabled) {
            result.error("bluetooth_disabled", "Bluetooth is turned off", null)
            return
        }
        val devices = adapter.bondedDevices
            .map { device ->
                mapOf(
                    "name" to (device.name ?: "Bluetooth printer"),
                    "address" to device.address,
                )
            }
            .sortedBy { it["name"]?.lowercase() }
        result.success(devices)
    }

    @SuppressLint("MissingPermission")
    private fun printRaw(address: String, data: ByteArray, result: MethodChannel.Result) {
        val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
        if (adapter == null || !adapter.isEnabled) {
            result.error("bluetooth_disabled", "Bluetooth is unavailable or turned off", null)
            return
        }

        bluetoothExecutor.execute {
            try {
                val device = adapter.getRemoteDevice(address)
                device.createInsecureRfcommSocketToServiceRecord(SERIAL_PORT_UUID).use { socket ->
                    socket.connect()
                    socket.outputStream.use { output ->
                        output.write(data)
                        output.flush()
                    }
                }
                runOnUiThread { result.success(null) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "bluetooth_print_failed",
                        error.message ?: "Could not connect to the Bluetooth printer",
                        error.javaClass.simpleName,
                    )
                }
            }
        }
    }

    override fun onDestroy() {
        bluetoothExecutor.shutdownNow()
        super.onDestroy()
    }
}
