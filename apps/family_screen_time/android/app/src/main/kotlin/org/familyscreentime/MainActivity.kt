package org.familyscreentime

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/** Hosts the Flutter interface (child and parent screens). */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PlatformBridge(applicationContext, this)
            .attach(flutterEngine.dartExecutor.binaryMessenger)
    }
}
