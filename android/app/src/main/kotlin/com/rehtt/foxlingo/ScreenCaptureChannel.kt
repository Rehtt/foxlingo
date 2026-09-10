package com.rehtt.foxlingo

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.media.projection.MediaProjectionConfig
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

object ScreenCaptureChannel {
    const val CHANNEL = "com.rehtt.foxlingo/screen_capture"
    private const val EVENTS_CHANNEL = "com.rehtt.foxlingo/screen_capture_events"
    private const val REQUEST_CODE = 4891
    private const val NOTIFICATION_REQUEST_CODE = 4892
    private const val START_TIMEOUT_MS = 5000L
    private const val EXTRA_PROJECTION_DATA = "com.rehtt.foxlingo.extra.PROJECTION_DATA"

    private val mainHandler = Handler(Looper.getMainLooper())
    private var activityReference: WeakReference<Activity>? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null
    private var projectionData: Intent? = null
    private var eventSink: EventChannel.EventSink? = null

    fun register(activity: Activity, flutterEngine: FlutterEngine) {
        activityReference = WeakReference(activity)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handle(call, result) }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    events?.success(ScreenCaptureService.currentEvent())
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) {
            return false
        }
        val result = pendingPermissionResult
        pendingPermissionResult = null
        if (resultCode == Activity.RESULT_OK && data != null) {
            projectionData = data
            result?.success(mapOf("granted" to true, "cancelled" to false))
        } else {
            projectionData = null
            result?.success(mapOf("granted" to false, "cancelled" to true))
        }
        return true
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != NOTIFICATION_REQUEST_CODE) {
            return false
        }
        val result = pendingNotificationPermissionResult
        pendingNotificationPermissionResult = null
        val granted = grantResults.firstOrNull() == android.content.pm.PackageManager.PERMISSION_GRANTED
        result?.success(granted)
        return true
    }

    fun onActivityDestroyed(activity: Activity) {
        if (activityReference?.get() === activity) {
            pendingPermissionResult?.success(mapOf("granted" to false, "cancelled" to true))
            pendingPermissionResult = null
            pendingNotificationPermissionResult?.success(false)
            pendingNotificationPermissionResult = null
            projectionData = null
            activityReference = null
        }
    }

    fun emitEvent(event: Map<String, Any?>) {
        mainHandler.post { eventSink?.success(event) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestPermission" -> requestPermission(result)
            "requestNotificationPermission" -> requestNotificationPermission(result)
            "startSession" -> startSession(result)
            "captureFrame" -> captureFrame(result)
            "cancelCapture" -> {
                ScreenCaptureService.cancelCapture()
                result.success(null)
            }
            "stopSession" -> {
                projectionData = null
                ScreenCaptureService.stopFromClient { result.success(null) }
            }
            "getSessionState" -> result.success(ScreenCaptureService.currentState())
            else -> result.notImplemented()
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        val activity = activityReference?.get()
        if (activity == null) {
            result.success(false)
            return
        }
        if (
            activity.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingNotificationPermissionResult != null) {
            result.error("notification_permission_busy", "A notification permission request is already active.", null)
            return
        }
        pendingNotificationPermissionResult = result
        activity.requestPermissions(
            arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_REQUEST_CODE,
        )
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (ScreenCaptureService.isReady()) {
            result.success(mapOf("granted" to true, "cancelled" to false))
            return
        }
        if (projectionData != null) {
            result.success(mapOf("granted" to true, "cancelled" to false))
            return
        }
        if (pendingPermissionResult != null) {
            result.error("permission_busy", "A screen capture permission request is already active.", null)
            return
        }
        val activity = activityReference?.get()
        if (activity == null) {
            result.error("activity_unavailable", "Screen capture permission needs a visible activity.", null)
            return
        }
        val manager = activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as? MediaProjectionManager
        if (manager == null) {
            result.error("unavailable", "MediaProjection is unavailable on this device.", null)
            return
        }
        pendingPermissionResult = result
        try {
            val captureIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                manager.createScreenCaptureIntent(MediaProjectionConfig.createConfigForDefaultDisplay())
            } else {
                manager.createScreenCaptureIntent()
            }
            activity.startActivityForResult(captureIntent, REQUEST_CODE)
        } catch (error: SecurityException) {
            pendingPermissionResult = null
            result.error("permission_failed", error.message, null)
        }
    }

    private fun startSession(result: MethodChannel.Result) {
        if (ScreenCaptureService.isReady()) {
            result.success(ScreenCaptureService.currentState())
            return
        }
        val data = projectionData
        if (data == null) {
            result.error("permission_required", "Screen capture permission is required first.", null)
            return
        }
        projectionData = null
        ScreenCaptureService.clearLastError()
        val context = activityReference?.get()?.applicationContext
            ?: return result.error("activity_unavailable", "The application is not ready.", null)
        val intent = Intent(context, ScreenCaptureService::class.java)
            .putExtra(EXTRA_PROJECTION_DATA, data)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        } catch (error: Exception) {
            result.error("service_start_failed", error.message, null)
            return
        }
        awaitReady(result, System.currentTimeMillis())
    }

    private fun awaitReady(result: MethodChannel.Result, startedAt: Long) {
        if (ScreenCaptureService.isReady()) {
            result.success(ScreenCaptureService.currentState())
            return
        }
        val lastError = ScreenCaptureService.lastError()
        if (lastError != null) {
            result.error(lastError.first, lastError.second, null)
            return
        }
        if (System.currentTimeMillis() - startedAt >= START_TIMEOUT_MS) {
            result.error("session_start_timeout", "Screen capture service did not become ready.", null)
            return
        }
        mainHandler.postDelayed({ awaitReady(result, startedAt) }, 50L)
    }

    private fun captureFrame(result: MethodChannel.Result) {
        when (ScreenCaptureService.requestCapture(result)) {
            CaptureRequestStatus.ACCEPTED -> Unit
            CaptureRequestStatus.NOT_READY -> result.error("session_not_ready", "Screen capture session is not ready.", null)
            CaptureRequestStatus.BUSY -> result.error("capture_busy", "A screen capture is already in progress.", null)
        }
    }

    enum class CaptureRequestStatus {
        ACCEPTED,
        NOT_READY,
        BUSY,
    }
}
