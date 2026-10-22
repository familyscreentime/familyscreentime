package org.familyscreentime

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log
import android.view.accessibility.AccessibilityEvent

/**
 * Reports which app comes to the foreground, as soon as it does, from the
 * package and activity names of window changes. Screen content is never
 * read, except on Android's security and permission pages while uninstall
 * protection is on (see [ProtectionGuard]).
 */
class ForegroundAccessibilityService : AccessibilityService() {

    override fun onServiceConnected() {
        instance = this
        MonitorService.start(this)
        MonitorService.instance?.overlayHostChanged()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        if (ProtectionGuard.mustClose(this, event)) {
            closeProtected()
            return
        }
        if (ProtectionGuard.settingsMustClose(event)) {
            closeSettings()
            return
        }
        if (ProtectionGuard.isSecurityPage(this, event)) scanSoon(event.packageName.toString())
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        val cls = event.className?.toString() ?: return
        // Keyboards, toasts and dialogs also change windows; only activities
        // mean that another app is in front.
        val activity = isActivity(pkg, cls)
        Log.d(TAG, "window $pkg/$cls activity=$activity")
        if (activity) {
            MonitorService.instance?.onForegroundApp(pkg)
        } else {
            // Some apps (YouTube, Play Store…) open with windows whose class
            // is not an activity, or that Android cannot resolve: Android's
            // usage statistics then say which app is in front.
            confirmSoon()
        }
    }

    private var confirmPending = false

    /** Asks the usage statistics for the app in front, once they are written. */
    private fun confirmSoon() {
        if (confirmPending) return
        confirmPending = true
        main.postDelayed({
            MonitorService.instance?.confirmForeground()
        }, 400)
        main.postDelayed({
            confirmPending = false
            MonitorService.instance?.confirmForeground()
        }, 1_500)
    }

    override fun onInterrupt() {}

    override fun onUnbind(intent: Intent?): Boolean {
        stopped()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        stopped()
        super.onDestroy()
    }

    /** Its overlay layer goes with it: floating windows move elsewhere. */
    private fun stopped() {
        if (instance !== this) return
        instance = null
        MonitorService.instance?.overlayHostChanged()
    }

    private var closedAt = 0L
    private val main = android.os.Handler(android.os.Looper.getMainLooper())
    private var scanPending = false

    /**
     * Looks at the security page shortly, once its content has settled;
     * changes meanwhile are covered by the same look.
     */
    private fun scanSoon(pkg: String) {
        if (scanPending) return
        scanPending = true
        main.postDelayed({
            scanPending = false
            if (ProtectionGuard.securityPageShowsApp(this, pkg)) closeProtected()
        }, 250)
        // Cards that load late: one more look.
        main.postDelayed({
            if (ProtectionGuard.securityPageShowsApp(this, pkg)) closeProtected()
        }, 1_200)
    }

    /** Leaves a protected settings page, saying why (once per second). */
    fun closeProtected() {
        val now = android.os.SystemClock.elapsedRealtime()
        if (now - closedAt < 1_000) return
        closedAt = now
        goHome()
        MonitorService.instance?.showProtectedNotice()
    }

    /** Leaves the settings while they are closed, saying why. */
    fun closeSettings() {
        val now = android.os.SystemClock.elapsedRealtime()
        if (now - closedAt < 1_000) return
        closedAt = now
        goHome()
        MonitorService.instance?.showSettingsNotice()
    }

    /** Sends the user to the home screen, away from a blocked app. */
    fun goHome() {
        performGlobalAction(GLOBAL_ACTION_HOME)
    }

    private fun isActivity(pkg: String, cls: String): Boolean = try {
        @Suppress("DEPRECATION")
        packageManager.getActivityInfo(ComponentName(pkg, cls), 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    companion object {
        private const val TAG = "FamilyScreenTime"

        @Volatile
        var instance: ForegroundAccessibilityService? = null
    }
}
