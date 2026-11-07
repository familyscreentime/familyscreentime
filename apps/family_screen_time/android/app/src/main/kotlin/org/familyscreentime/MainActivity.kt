package org.familyscreentime

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Hosts the Flutter interface (child and parent screens). A fragment
 * activity, for the biometric prompt.
 */
class MainActivity : FlutterFragmentActivity() {
    override fun onResume() {
        super.onResume()
        visible = true
    }

    override fun onPause() {
        visible = false
        super.onPause()
    }

    companion object {
        /** The interface is on screen: the process must not restart then. */
        @Volatile
        var visible = false
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PlatformBridge(applicationContext, this)
            .attach(flutterEngine.dartExecutor.binaryMessenger)
    }
}
