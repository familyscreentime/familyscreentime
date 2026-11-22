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

    /**
     * On a child's device, once app detection is set up, the app leaves
     * no card in the recent apps: swiping it away, or "clear all", makes
     * some makers (Xiaomi's "SwipeUpClean") stop its processes in a way
     * after which Android does not start app detection again. The child
     * still opens it from the home screen.
     */
    override fun onStop() {
        super.onStop()
        val hide = Health.monitorWanted(this) && Health.accessibilityEnabled(this)
        try {
            val am = getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
            for (task in am.appTasks) task.setExcludeFromRecents(hide)
        } catch (e: Exception) {
            // The card stays: nothing else changes.
        }
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
