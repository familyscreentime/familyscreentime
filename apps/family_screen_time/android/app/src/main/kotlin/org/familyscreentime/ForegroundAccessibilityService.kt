package org.familyscreentime

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log
import android.os.Build
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.inputmethod.InputMethodManager

/**
 * Reports which app comes to the foreground, as soon as it does, from the
 * package and activity names of window changes. Screen content is never
 * read, except on Android's security and permission pages while uninstall
 * protection is on (see [ProtectionGuard]). In browsers, scroll events are
 * counted (see [BrowserWatch]), their content left aside.
 */
class ForegroundAccessibilityService : AccessibilityService() {

    override fun onServiceConnected() {
        Log.i(TAG, "Accessibility service connected")
        instance = this
        Enforcer.get(this).accessibilityChanged()
        if (Health.monitorWanted(this)) MonitorService.start(this)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        // Only counted, for the browsers (see BrowserWatch).
        if (event.eventType == AccessibilityEvent.TYPE_VIEW_SCROLLED) {
            Enforcer.get(this).onScroll(event)
            return
        }
        if (ProtectionGuard.mustClose(this, event)) {
            closeProtected()
            return
        }
        if (ProtectionGuard.settingsMustClose(event)) {
            closeSettings()
            return
        }
        if (ProtectionGuard.isSecurityPage(this, event)) scanSoon(event.packageName.toString())
        // A floating video window (picture in picture) of an app blocked
        // a moment ago: closed.
        if (event.eventType == AccessibilityEvent.TYPE_WINDOWS_CHANGED) {
            Enforcer.get(this).checkPictureInPicture()
            visibleSoon()
            return
        }
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        val cls = event.className?.toString() ?: return
        // Keyboards, toasts and dialogs also change windows; only activities
        // mean that another app is in front.
        val activity = isActivity(pkg, cls)
        Log.d(TAG, "window $pkg/$cls activity=$activity")
        visibleSoon()
        if (activity) {
            Enforcer.get(this).onForegroundApp(pkg)
        } else {
            // Some apps (YouTube, Play Store…) open with windows whose class
            // is not an activity, or that Android cannot resolve. A full
            // screen window of an app with an icon is taken at once (a
            // blocked app then closes without waiting); Android's usage
            // statistics then confirm which app is in front.
            if (event.isFullScreen && likelyApp(pkg, cls)) {
                Enforcer.get(this).onForegroundApp(pkg)
            }
            confirmSoon()
        }
    }

    private var visiblePending = false

    /** Says which apps are on screen, once the windows have settled. */
    fun visibleSoon() {
        if (visiblePending) return
        visiblePending = true
        main.postDelayed({
            visiblePending = false
            Enforcer.get(this).visibleApps(visibleApps())
        }, 300)
    }

    /**
     * The apps with a window on screen: the one in front, and those beside
     * it (split screen), in a floating video window (picture in picture) or
     * in free windows. Only their package names are read.
     */
    fun visibleApps(): List<String> {
        val list = try {
            windows
        } catch (e: Exception) {
            return emptyList()
        }
        val apps = LinkedHashSet<String>()
        for (w in list) {
            if (w.type != android.view.accessibility.AccessibilityWindowInfo.TYPE_APPLICATION) continue
            val pkg = w.root?.packageName?.toString() ?: continue
            if (pkg == packageName || pkg == "com.android.systemui") continue
            apps.add(pkg)
        }
        return apps.toList()
    }

    /** Whether [pkg]'s window [cls] is an app's screen, not a keyboard, a toast… */
    private fun likelyApp(pkg: String, cls: String): Boolean {
        if (pkg == packageName || pkg == "com.android.systemui") return false
        if (cls.contains("Toast") || cls.contains("Dialog")) return false
        val keyboards = (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager)
            .enabledInputMethodList.map { it.packageName }
        if (pkg in keyboards) return false
        return packageManager.getLaunchIntentForPackage(pkg) != null
    }

    /**
     * Closes the floating video windows (picture in picture) of the apps
     * [blocked] says; when one cannot be closed, its video is paused.
     * Whether any was found.
     */
    fun closePictureInPicture(blocked: (String) -> Boolean): Boolean {
        if (Build.VERSION.SDK_INT < 26) return false
        var found = false
        val list = try {
            windows
        } catch (e: Exception) {
            return false
        }
        for (w in list) {
            if (!w.isInPictureInPictureMode) continue
            val root = w.root ?: continue
            val pkg = root.packageName?.toString() ?: continue
            if (!blocked(pkg)) continue
            found = true
            Log.i(TAG, "Closing the floating window of $pkg")
            if (!root.performAction(AccessibilityNodeInfo.ACTION_DISMISS)) {
                Enforcer.get(this).pauseMedia()
            }
        }
        return found
    }

    private var confirmPending = false

    /** Asks the usage statistics for the app in front, once they are written. */
    private fun confirmSoon() {
        if (confirmPending) return
        confirmPending = true
        main.postDelayed({
            Enforcer.get(this).confirmForeground()
        }, 400)
        main.postDelayed({
            confirmPending = false
            Enforcer.get(this).confirmForeground()
        }, 1_500)
    }

    override fun onInterrupt() {}

    override fun onUnbind(intent: Intent?): Boolean {
        Log.w(TAG, "Accessibility service unbound by the system")
        stopped()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        Log.w(TAG, "Accessibility service destroyed")
        stopped()
        super.onDestroy()
    }

    /** Its overlay layer goes with it: floating windows move elsewhere. */
    private fun stopped() {
        if (instance !== this) return
        instance = null
        Enforcer.get(this).accessibilityChanged()
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
        Enforcer.get(this).showProtectedNotice()
    }

    /** Leaves the settings while they are closed, saying why. */
    fun closeSettings() {
        val now = android.os.SystemClock.elapsedRealtime()
        if (now - closedAt < 1_000) return
        closedAt = now
        goHome()
        Enforcer.get(this).showSettingsNotice()
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
