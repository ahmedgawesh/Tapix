package com.tapix.pos

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Owns the app's Flutter engine at process scope.
 *
 * The independent-branch HTTPS listener runs in the main Dart isolate. Keeping
 * that isolate owned by an Activity made the listener disappear when Android
 * removed the UI task even though the foreground service was still alive.
 * A process-scoped engine lets the UI detach while branch/cashier devices keep
 * using the same database writer and the same TLS server.
 */
class TapixApplication : Application() {
    lateinit var flutterEngine: FlutterEngine
        private set

    lateinit var masterKeepAliveChannel: MasterKeepAliveChannel
        private set

    override fun onCreate() {
        super.onCreate()

        flutterEngine = FlutterEngine(this)
        masterKeepAliveChannel = MasterKeepAliveChannel(this).also { channel ->
            channel.registerWith(flutterEngine)
        }
        flutterEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault(),
        )
    }
}
