package com.rehtt.foxlingo

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache

/** Keeps the primary Flutter engine alive while MainActivity is recreated. */
class FoxLingoApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val cache = FlutterEngineCache.getInstance()
        if (cache.get(MAIN_ENGINE_ID) == null) {
            cache.put(MAIN_ENGINE_ID, FlutterEngine(this))
        }
    }

    companion object {
        const val MAIN_ENGINE_ID = "foxlingo_main_engine"
    }
}
