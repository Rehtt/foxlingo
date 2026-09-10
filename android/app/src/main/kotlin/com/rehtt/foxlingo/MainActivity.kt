package com.rehtt.foxlingo

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

class MainActivity : FlutterActivity() {
    override fun getCachedEngineId(): String = FoxLingoApplication.MAIN_ENGINE_ID

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ScreenCaptureChannel.register(this, flutterEngine)
        ScreenTranslationBridge.registerMain(this, flutterEngine)
        if (!flutterEngine.dartExecutor.isExecutingDart) {
            flutterEngine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault(),
            )
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        if (!ScreenCaptureChannel.onActivityResult(requestCode, resultCode, data)) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (!ScreenCaptureChannel.onRequestPermissionsResult(requestCode, permissions, grantResults)) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }

    override fun onDestroy() {
        ScreenCaptureChannel.onActivityDestroyed(this)
        super.onDestroy()
    }

    /** Keep the primary engine alive while the UI Activity is recreated. */
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }
}
