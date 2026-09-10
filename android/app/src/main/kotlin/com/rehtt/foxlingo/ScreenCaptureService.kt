package com.rehtt.foxlingo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.util.DisplayMetrics
import androidx.annotation.RequiresApi
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean

/** Owns the MediaProjection token and all resources derived from it. */
class ScreenCaptureService : Service(), ImageReader.OnImageAvailableListener {
    companion object {
        private const val CHANNEL_ID = "screen_capture"
        private const val NOTIFICATION_ID = 7391
        private const val ACTION_STOP = "com.rehtt.foxlingo.action.STOP_SCREEN_TRANSLATION"
        private const val EXTRA_PROJECTION_DATA = "com.rehtt.foxlingo.extra.PROJECTION_DATA"
        private const val CAPTURE_TIMEOUT_MS = 5000L

        @Volatile
        private var instance: ScreenCaptureService? = null

        @Volatile
        private var lastFailureSnapshot: Pair<String, String>? = null

        fun isReady(): Boolean = instance?.ready == true

        fun requestCapture(result: io.flutter.plugin.common.MethodChannel.Result): ScreenCaptureChannel.CaptureRequestStatus {
            val service = instance ?: return ScreenCaptureChannel.CaptureRequestStatus.NOT_READY
            return service.enqueueCapture(result)
        }

        fun cancelCapture() {
            instance?.let { service ->
                service.captureHandler.post { service.cancelPendingCapture() }
            }
        }

        fun stopFromClient(onComplete: (() -> Unit)? = null) {
            val service = instance
            if (service == null) {
                onComplete?.invoke()
            } else {
                service.requestStop("client", onComplete)
            }
        }

        fun clearLastError() {
            lastFailureSnapshot = null
            instance?.lastFailure = null
        }

        fun lastError(): Pair<String, String>? = instance?.lastFailure ?: lastFailureSnapshot

        fun currentState(): Map<String, Any?> = instance?.stateMap() ?: lastFailureSnapshot?.let {
            mapOf(
                "state" to "error",
                "width" to 0,
                "height" to 0,
                "geometryVersion" to 0,
                "errorCode" to it.first,
                "message" to it.second,
            )
        } ?: stoppedState()

        fun currentEvent(): Map<String, Any?> = instance?.stateMap() ?: stoppedState()

        private fun stoppedState(): Map<String, Any?> = mapOf(
            "state" to "stopped",
            "width" to 0,
            "height" to 0,
            "geometryVersion" to 0,
        )
    }

    private data class PendingCapture(
        val result: io.flutter.plugin.common.MethodChannel.Result,
        var timeout: Runnable? = null,
    )

    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var captureThread: HandlerThread
    private lateinit var captureHandler: Handler
    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var pendingCapture: PendingCapture? = null
    private val captureBusy = AtomicBoolean(false)
    private var released = false
    private var stopRequested = false
    private val stopCallbacks = mutableListOf<() -> Unit>()
    private var lastStartId = 0

    @Volatile
    private var ready = false

    @Volatile
    private var lastFailure: Pair<String, String>? = null

    private var captureWidth = 0
    private var captureHeight = 0
    private var densityDpi = 0
    private var geometryVersion = 0
    private var frameId = 0L

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            requestStop("system")
        }

        @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
        override fun onCapturedContentResize(width: Int, height: Int) {
            resizeCapture(width, height)
        }
    }

    override fun onCreate() {
        super.onCreate()
        captureThread = HandlerThread("screen-capture").also { it.start() }
        captureHandler = Handler(captureThread.looper)
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        lastStartId = startId
        if (intent?.action == ACTION_STOP) {
            requestStop("notification")
            return START_NOT_STICKY
        }

        // A service restarted with an empty Intent must never try to reuse a
        // consent token or recreate a projection session.
        val projectionIntent = readProjectionIntent(intent)
        if (projectionIntent == null) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        if (ready) {
            return START_NOT_STICKY
        }

        if (released) {
            released = false
            stopRequested = false
            lastFailure = null
        }

        try {
            startForegroundWithNotification()
            initializeProjection(projectionIntent)
        } catch (error: SecurityException) {
            failSession("projection_denied", error.message ?: "Screen capture permission was denied.")
        } catch (error: Exception) {
            failSession("projection_failed", error.message ?: "Unable to start screen capture.")
        }
        return START_NOT_STICKY
    }

    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        val metrics = resources.displayMetrics
        resizeCapture(metrics.widthPixels, metrics.heightPixels)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onImageAvailable(reader: ImageReader) {
        val pending = pendingCapture ?: run {
            closeLatestImage(reader)
            return
        }
        val image = try {
            reader.acquireLatestImage()
        } catch (error: Exception) {
            completeCaptureError(pending, "capture_failed", error.message ?: "Unable to read the screen.")
            return
        } ?: return

        try {
            val bytes = encodePng(image)
            completeCaptureSuccess(
                pending,
                mapOf(
                    "bytes" to bytes,
                    "width" to image.width,
                    "height" to image.height,
                    "frameId" to ++frameId,
                    "geometryVersion" to geometryVersion,
                ),
            )
        } catch (error: Exception) {
            completeCaptureError(pending, "capture_failed", error.message ?: "Unable to encode the screen.")
        } finally {
            image.close()
        }
    }

    override fun onDestroy() {
        releaseResources("destroy", notifyStopped = false)
        if (instance === this) {
            instance = null
        }
        captureThread.quitSafely()
        super.onDestroy()
    }

    private fun initializeProjection(projectionIntent: Intent) {
        val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val resultCode = ActivityResultCodes.RESULT_OK
        val mediaProjection = manager.getMediaProjection(resultCode, projectionIntent)
            ?: throw IllegalStateException("MediaProjection could not be created.")

        projection = mediaProjection
        mediaProjection.registerCallback(projectionCallback, mainHandler)
        val metrics = resources.displayMetrics
        captureWidth = metrics.widthPixels
        captureHeight = metrics.heightPixels
        densityDpi = metrics.densityDpi
        geometryVersion = 1
        createDisplayResources(captureWidth, captureHeight)
        ready = true
        lastFailure = null
        ScreenCaptureChannel.emitEvent(stateMap())
    }

    private fun createDisplayResources(width: Int, height: Int) {
        if (width <= 0 || height <= 0) {
            throw IllegalArgumentException("Display dimensions are invalid.")
        }
        val previousReader = imageReader
        val reader = ImageReader.newInstance(width, height, android.graphics.PixelFormat.RGBA_8888, 2)
        reader.setOnImageAvailableListener(this, captureHandler)
        try {
            val display = virtualDisplay
            if (display == null) {
                virtualDisplay = projection?.createVirtualDisplay(
                    "tr-app-screen-capture",
                    width,
                    height,
                    densityDpi,
                    DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                    reader.surface,
                    null,
                    captureHandler,
                ) ?: throw IllegalStateException("VirtualDisplay could not be created.")
            } else {
                display.resize(width, height, densityDpi)
                display.setSurface(reader.surface)
            }
            imageReader = reader
            previousReader?.setOnImageAvailableListener(null, null)
            previousReader?.close()
        } catch (error: Exception) {
            reader.close()
            throw error
        }
    }

    private fun resizeCapture(width: Int, height: Int) {
        if (!ready || width <= 0 || height <= 0) {
            return
        }
        if (width == captureWidth && height == captureHeight) {
            return
        }
        captureHandler.post {
            if (!ready || released) {
                return@post
            }
            captureWidth = width
            captureHeight = height
            geometryVersion++
            try {
                createDisplayResources(width, height)
                ScreenCaptureChannel.emitEvent(stateMap())
            } catch (error: Exception) {
                mainHandler.post {
                    failSession("resize_failed", error.message ?: "Unable to resize screen capture.")
                }
            }
        }
    }

    private fun enqueueCapture(result: io.flutter.plugin.common.MethodChannel.Result): ScreenCaptureChannel.CaptureRequestStatus {
        if (!ready || released || imageReader == null) {
            return ScreenCaptureChannel.CaptureRequestStatus.NOT_READY
        }
        if (!captureBusy.compareAndSet(false, true)) {
            return ScreenCaptureChannel.CaptureRequestStatus.BUSY
        }
        val pending = PendingCapture(result)
        captureHandler.post {
            if (!ready || released || imageReader == null) {
                captureBusy.set(false)
                postError(pending.result, "session_invalid", "Screen capture session is no longer ready.")
                return@post
            }
            // Arm the request only after old buffers have been discarded on
            // the same thread that delivers image callbacks.
            drainImages()
            pendingCapture = pending
            val timeout = Runnable {
                if (pendingCapture === pending) {
                    pendingCapture = null
                    captureBusy.set(false)
                    postError(pending.result, "capture_timeout", "No fresh screen frame arrived within five seconds.")
                }
            }
            pending.timeout = timeout
            captureHandler.postDelayed(timeout, CAPTURE_TIMEOUT_MS)
        }
        return ScreenCaptureChannel.CaptureRequestStatus.ACCEPTED
    }

    private fun cancelPendingCapture() {
        val pending = pendingCapture ?: return
        completeCaptureError(pending, "capture_cancelled", "Screen capture was cancelled.")
    }

    private fun drainImages() {
        val reader = imageReader ?: return
        while (true) {
            val image = try {
                reader.acquireLatestImage()
            } catch (_: Exception) {
                null
            } ?: break
            image.close()
        }
    }

    private fun closeLatestImage(reader: ImageReader) {
        try {
            reader.acquireLatestImage()?.close()
        } catch (_: Exception) {
            // The reader may be closing during stop; there is nothing to do.
        }
    }

    private fun completeCaptureSuccess(pending: PendingCapture, payload: Map<String, Any?>) {
        if (pendingCapture !== pending) {
            return
        }
        pendingCapture = null
        captureBusy.set(false)
        pending.timeout?.let { captureHandler.removeCallbacks(it) }
        mainHandler.post { pending.result.success(payload) }
    }

    private fun completeCaptureError(pending: PendingCapture, code: String, message: String) {
        if (pendingCapture !== pending) {
            return
        }
        pendingCapture = null
        captureBusy.set(false)
        pending.timeout?.let { captureHandler.removeCallbacks(it) }
        postError(pending.result, code, message)
    }

    private fun postError(result: io.flutter.plugin.common.MethodChannel.Result, code: String, message: String) {
        mainHandler.post { result.error(code, message, null) }
    }

    private fun requestStop(reason: String, onComplete: (() -> Unit)? = null) {
        if (released) {
            if (onComplete != null) {
                mainHandler.post(onComplete)
            }
            return
        }
        if (onComplete != null) {
            stopCallbacks += onComplete
        }
        if (stopRequested) {
            return
        }
        stopRequested = true
        val stopStartId = lastStartId
        captureHandler.post {
            releaseResources(reason, notifyStopped = true)
            mainHandler.post {
                stopSelf(stopStartId)
                val callbacks = stopCallbacks.toList()
                stopCallbacks.clear()
                callbacks.forEach { it.invoke() }
            }
        }
    }

    private fun failSession(code: String, message: String) {
        lastFailure = code to message
        lastFailureSnapshot = lastFailure
        ScreenCaptureChannel.emitEvent(
            mapOf(
                "state" to "error",
                "width" to captureWidth,
                "height" to captureHeight,
                "geometryVersion" to geometryVersion,
                "errorCode" to code,
                "message" to message,
            ),
        )
        releaseResources("error", notifyStopped = false)
        mainHandler.post { stopSelf() }
    }

    private fun releaseResources(reason: String, notifyStopped: Boolean) {
        if (released) {
            return
        }
        released = true
        ready = false
        captureBusy.set(false)
        pendingCapture?.let {
            pendingCapture = null
            it.timeout?.let { timeout -> captureHandler.removeCallbacks(timeout) }
            postError(it.result, "session_stopped", "Screen capture session stopped.")
        }
        try {
            imageReader?.setOnImageAvailableListener(null, null)
        } catch (_: Exception) {
        }
        imageReader?.close()
        imageReader = null
        virtualDisplay?.release()
        virtualDisplay = null
        projection?.unregisterCallback(projectionCallback)
        projection?.stop()
        projection = null
        if (notifyStopped) {
            ScreenCaptureChannel.emitEvent(
                mapOf(
                    "state" to "stopped",
                    "width" to 0,
                    "height" to 0,
                    "geometryVersion" to geometryVersion,
                    "reason" to reason,
                ),
            )
        }
    }

    private fun stateMap(): Map<String, Any?> = mapOf(
        "state" to when {
            ready -> "ready"
            lastFailure != null -> "error"
            !released -> "starting"
            else -> "stopped"
        },
        "width" to captureWidth,
        "height" to captureHeight,
        "geometryVersion" to geometryVersion,
        if (lastFailure != null) "errorCode" to lastFailure!!.first else "errorCode" to null,
        if (lastFailure != null) "message" to lastFailure!!.second else "message" to null,
    )

    private fun encodePng(image: Image): ByteArray {
        val plane = image.planes.firstOrNull()
            ?: throw IllegalStateException("Screen frame has no pixel plane.")
        val width = image.width
        val height = image.height
        val pixelStride = plane.pixelStride
        val rowStride = plane.rowStride
        if (width <= 0 || height <= 0 || pixelStride <= 0 || rowStride < width * pixelStride) {
            throw IllegalStateException("Screen frame has invalid row padding.")
        }
        val source = plane.buffer.duplicate().apply { position(0) }
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        try {
            if (pixelStride == 4) {
                val tight = ByteBuffer.allocate(width * height * 4)
                val row = ByteArray(width * 4)
                for (y in 0 until height) {
                    val offset = y * rowStride
                    if (offset + row.size > source.limit()) {
                        throw IllegalStateException("Screen frame buffer is truncated.")
                    }
                    source.position(offset)
                    source.get(row)
                    tight.put(row)
                }
                tight.flip()
                bitmap.copyPixelsFromBuffer(tight)
            } else {
                val pixels = IntArray(width * height)
                if (pixelStride < 3) {
                    throw IllegalStateException("Screen frame pixel stride is unsupported.")
                }
                for (y in 0 until height) {
                    for (x in 0 until width) {
                        val offset = y * rowStride + x * pixelStride
                        if (offset + 2 >= source.limit() ||
                            (pixelStride >= 4 && offset + 3 >= source.limit())
                        ) {
                            throw IllegalStateException("Screen frame buffer is truncated.")
                        }
                        val red = source.get(offset).toInt() and 0xff
                        val green = source.get(offset + 1).toInt() and 0xff
                        val blue = source.get(offset + 2).toInt() and 0xff
                        val alpha = if (pixelStride >= 4) {
                            source.get(offset + 3).toInt() and 0xff
                        } else {
                            0xff
                        }
                        pixels[y * width + x] = Color.argb(alpha, red, green, blue)
                    }
                }
                bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
            }
            val output = ByteArrayOutputStream()
            if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)) {
                throw IllegalStateException("PNG encoding failed.")
            }
            return output.toByteArray()
        } finally {
            bitmap.recycle()
        }
    }

    private fun readProjectionIntent(intent: Intent?): Intent? {
        if (intent == null) {
            return null
        }
        @Suppress("DEPRECATION")
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(EXTRA_PROJECTION_DATA, Intent::class.java)
        } else {
            intent.getParcelableExtra(EXTRA_PROJECTION_DATA)
        }
    }

    private fun startForegroundWithNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        val stopIntent = Intent(this, ScreenCaptureService::class.java).setAction(ACTION_STOP)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val stopPendingIntent = PendingIntent.getService(this, 7392, stopIntent, flags)
        val notificationBuilder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = notificationBuilder
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(getString(R.string.screen_translation_notification_title))
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .addAction(
                Notification.Action.Builder(
                    null,
                    getString(R.string.screen_translation_notification_stop),
                    stopPendingIntent,
                ).build(),
            )
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager?.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Screen translation",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private object ActivityResultCodes {
        const val RESULT_OK = -1
    }
}
