package com.rehtt.foxlingo

import android.content.Context
import android.graphics.Point
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec

/** Routes typed messages between the main and cached overlay Flutter engines. */
object ScreenTranslationBridge {
    private const val MESSAGE_CHANNEL = "com.rehtt.foxlingo/translation_bridge"
    private const val CONTROL_CHANNEL = "com.rehtt.foxlingo/translation_bridge_control"
    private const val OVERLAY_ENGINE_ID = "myCachedEngine"

    private var mainChannel: BasicMessageChannel<Any?>? = null
    private var overlayChannel: BasicMessageChannel<Any?>? = null
    private var applicationContext: Context? = null

    fun registerMain(context: Context, engine: FlutterEngine) {
        applicationContext = context.applicationContext
        val channel = BasicMessageChannel<Any?>(
            engine.dartExecutor.binaryMessenger,
            MESSAGE_CHANNEL,
            StandardMessageCodec.INSTANCE,
        )
        mainChannel = channel
        channel.setMessageHandler { message, reply ->
            overlayChannel?.send(message)
            reply.reply(null)
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, CONTROL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bindOverlay" -> result.success(bindOverlay())
                    else -> result.notImplemented()
                }
            }
    }

    private fun bindOverlay(): Boolean {
        val overlayEngine = FlutterEngineCache.getInstance().get(OVERLAY_ENGINE_ID)
            ?: return false
        val channel = BasicMessageChannel<Any?>(
            overlayEngine.dartExecutor.binaryMessenger,
            MESSAGE_CHANNEL,
            StandardMessageCodec.INSTANCE,
        )
        overlayChannel = channel
        channel.setMessageHandler { message, reply ->
            mainChannel?.send(message)
            reply.reply(null)
        }
        MethodChannel(overlayEngine.dartExecutor.binaryMessenger, CONTROL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "displaySize" -> result.success(displaySize())
                    else -> result.notImplemented()
                }
            }
        return true
    }

    private fun displaySize(): Map<String, Double> {
        val context = applicationContext ?: return mapOf("width" to 0.0, "height" to 0.0)
        val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val point = Point()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.currentWindowMetrics.bounds
            point.set(bounds.width(), bounds.height())
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.getRealSize(point)
        }
        val density = context.resources.displayMetrics.density
        return mapOf(
            "width" to (point.x / density).toDouble(),
            "height" to (point.y / density).toDouble(),
        )
    }
}
