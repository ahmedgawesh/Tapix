package com.tapix.pos

import android.Manifest
import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Bridges the process-owned Flutter engine to the Android foreground service. */
class MasterKeepAliveChannel(private val application: Application) {
    private var activity: Activity? = null
    private var deferredPermissionPrompt = false
    private var permissionPromptRequested = false
    private var pendingPort: Int? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingStartRetry = Runnable { retryPendingStart() }

    fun registerWith(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler(::handleCall)
    }

    fun attachActivity(activity: Activity) {
        this.activity = activity
        if (
            deferredPermissionPrompt &&
            !permissionPromptRequested &&
            needsNotificationPermission(activity)
        ) {
            deferredPermissionPrompt = false
            permissionPromptRequested = true
            activity.requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST,
            )
        }
    }

    fun detachActivity(activity: Activity) {
        if (this.activity === activity) {
            this.activity = null
            mainHandler.removeCallbacks(pendingStartRetry)
        }
    }

    /** Retries an Android 12+ foreground-service start once the UI is visible. */
    fun retryPendingStart() {
        val port = pendingPort ?: return
        val currentActivity = activity ?: return
        val powerManager = application.getSystemService(PowerManager::class.java)
        if (!powerManager.isInteractive || !currentActivity.hasWindowFocus()) return
        if (MasterKeepAliveService.isRunning) {
            pendingPort = null
            mainHandler.removeCallbacks(pendingStartRetry)
            return
        }
        try {
            MasterKeepAliveService.start(currentActivity, port)
            pendingPort = null
            mainHandler.removeCallbacks(pendingStartRetry)
        } catch (error: Exception) {
            // Android can keep the UID in a transitional background state for
            // a short moment after onResume/window focus. Retry only while the
            // visible Activity can legitimately start a foreground service.
            Log.e(TAG, "Unable to start deferred LAN foreground service", error)
            if (isForegroundServiceStartDenied(error)) schedulePendingStartRetry()
        }
    }

    private fun schedulePendingStartRetry() {
        if (pendingPort == null || activity == null) return
        mainHandler.removeCallbacks(pendingStartRetry)
        mainHandler.postDelayed(pendingStartRetry, PENDING_RETRY_DELAY_MS)
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return false

        return true
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> handleStart(call, result)
            "stop" -> {
                pendingPort = null
                mainHandler.removeCallbacks(pendingStartRetry)
                MasterKeepAliveService.stop(application)
                result.success(null)
            }
            "isRunning" -> result.success(MasterKeepAliveService.isRunning)
            else -> result.notImplemented()
        }
    }

    private fun handleStart(call: MethodCall, result: MethodChannel.Result) {
        val port = call.argument<Int>("port")
        if (port == null || port !in 1..65535) {
            result.error("invalid_port", "A valid master port is required", null)
            return
        }

        val currentActivity = activity
        val permissionGranted = !needsNotificationPermission(application)
        if (
            !permissionGranted &&
            currentActivity != null &&
            !permissionPromptRequested
        ) {
            permissionPromptRequested = true
            currentActivity.requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST,
            )
        } else if (!permissionGranted && currentActivity == null) {
            // Ask when a UI becomes available, but never hold the branch server
            // startup behind an Activity or a permission dialog.
            deferredPermissionPrompt = true
        }

        // Android permits a foreground service while notification posting is
        // denied. Starting immediately is essential during a sticky, headless
        // process restart; the system still exposes the service in task manager.
        startService(port, result, permissionGranted)
    }

    private fun startService(
        port: Int,
        result: MethodChannel.Result,
        notificationPermissionGranted: Boolean,
    ) {
        if (MasterKeepAliveService.isRunning) {
            pendingPort = null
            result.success(
                mapOf("notificationPermissionGranted" to notificationPermissionGranted),
            )
            return
        }
        try {
            MasterKeepAliveService.start(application, port)
            pendingPort = null
            result.success(
                mapOf("notificationPermissionGranted" to notificationPermissionGranted),
            )
        } catch (error: Exception) {
            if (isForegroundServiceStartDenied(error)) {
                // The process-scoped Flutter engine can initialize before its
                // Activity reaches RESUMED. Preserve the already-bound Dart
                // HTTPS listener, then start the native foreground service from
                // MainActivity.onResume where Android permits the transition.
                pendingPort = port
                schedulePendingStartRetry()
                result.success(
                    mapOf(
                        "notificationPermissionGranted" to
                            notificationPermissionGranted,
                        "serviceStartDeferred" to true,
                    ),
                )
                return
            }
            result.error(
                "master_keep_alive_failed",
                error.message ?: "Could not keep the master service active",
                error.javaClass.simpleName,
            )
        }
    }

    private fun isForegroundServiceStartDenied(error: Exception): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            error.javaClass.name ==
                "android.app.ForegroundServiceStartNotAllowedException"

    private fun needsNotificationPermission(context: Context): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED

    companion object {
        private const val TAG = "TapixLanKeepAlive"
        private const val PENDING_RETRY_DELAY_MS = 750L
        const val CHANNEL_NAME = "com.tapix.pos/master_keep_alive"
        const val NOTIFICATION_PERMISSION_REQUEST = 7013
    }
}
