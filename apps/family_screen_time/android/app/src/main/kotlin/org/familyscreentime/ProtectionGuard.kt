package org.familyscreentime

import android.accessibilityservice.AccessibilityService
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.util.Log
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent

/**
 * Keeps the child out of the Android settings that would switch the app
 * off, while uninstall protection is on: turning off the protection
 * (device administrator), any settings page about this app — its app info
 * (force stop, uninstall), its accessibility service, its permissions —
 * and the security pages that offer to remove its access (Android's safety
 * center: "Review this app with full access to the device").
 *
 * Pages about the app are recognised by their title, the app's name. The
 * security pages are recognised by the app's name in their content: the
 * screen content is read there, and only there (security and permission
 * pages of the settings).
 *
 * Since Android 14, the safety center hides itself from accessibility
 * services that are not assistive tools: no event arrives from it. It is
 * then recognised from the usage statistics (the activity on screen) and
 * closed whatever it shows.
 *
 * Android has no way to ask for a code there, so those pages are closed at
 * once with a notice; they open normally while parent mode is on in the
 * app, and for a short while after the app itself opened a settings page.
 * The protection is turned off from parent mode, without going through the
 * settings.
 */
object ProtectionGuard {

    /** Settings and installer apps whose pages can switch the app off. */
    private val guardedPackages = setOf(
        "com.android.settings",
        "com.google.android.packageinstaller",
        "com.android.packageinstaller",
        "com.google.android.permissioncontroller",
        "com.android.permissioncontroller",
    )

    private const val TAG = "FamilyScreenTime"

    private val installerPackages = setOf(
        "com.google.android.packageinstaller",
        "com.android.packageinstaller",
    )

    /** Pages that may show a "remove access" card for the app. */
    private val securityPackages = setOf(
        "com.google.android.permissioncontroller",
        "com.android.permissioncontroller",
        "com.google.android.apps.safetycenter",
    )
    private val securityClassHints = listOf("Safety", "Security", "Privacy")

    /** Class of the last window shown by the settings, to know its page. */
    @Volatile
    private var settingsClass = ""

    @Volatile
    private var activeCache = false

    @Volatile
    private var activeCheckedAt = 0L

    /** Parent mode on, or a settings page opened by the app: until then. */
    @Volatile
    private var allowedUntil = 0L

    /** Allows the guarded pages for [ms] (0: no longer). */
    fun allowFor(ms: Long) {
        allowedUntil = if (ms <= 0) 0L else SystemClock.elapsedRealtime() + ms
    }

    /** Parent mode is on, or the app just opened a settings page. */
    fun allowed() = SystemClock.elapsedRealtime() < allowedUntil

    /** Settings and wallpaper apps, closed when the parent chose so. */
    val settingsPackages = setOf(
        "com.android.settings",
        "com.google.android.apps.wallpaper",
        "com.android.wallpaper",
        "com.android.wallpaperpicker",
        "com.android.wallpaper.livepicker",
        "com.android.customization",
        "com.android.themepicker",
    )

    /** The settings are closed: no time left, or for the parent only. */
    @Volatile
    var settingsLocked = false

    /** True when [event] opens a settings page that is closed right now. */
    fun settingsMustClose(event: AccessibilityEvent): Boolean {
        if (!settingsLocked || allowed()) return false
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return false
        return event.packageName?.toString() in settingsPackages
    }

    /** Whether the protection is on; checked at most every few seconds. */
    private fun activeCached(context: Context): Boolean {
        val now = SystemClock.elapsedRealtime()
        if (now - activeCheckedAt > 3_000) {
            activeCache = isActive(context)
            activeCheckedAt = now
        }
        return activeCache
    }

    fun isActive(context: Context): Boolean {
        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        return dpm.isAdminActive(ComponentName(context, AdminReceiver::class.java))
    }

    /** True when [event] shows a guarded page that must be closed. */
    fun mustClose(context: Context, event: AccessibilityEvent): Boolean {
        val pkg = event.packageName?.toString() ?: return false
        if (pkg !in guardedPackages && pkg !in securityPackages) return false
        val cls = event.className?.toString() ?: ""
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            pkg == "com.android.settings"
        ) {
            settingsClass = cls
        }
        if (allowed() || !activeCached(context)) return false
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return false
        Log.d(TAG, "settings window $pkg/$cls: ${event.text}")
        // Turning off device administrators (ours or, while protected, any).
        if (cls.contains("DeviceAdminAdd")) return true
        // The installer is needed to update the app; uninstalling is refused
        // anyway while the app is a device administrator.
        if (pkg in installerPackages) return cls.contains("Uninstall")
        // A page about this app: its title is the app's name.
        val name = appName(context)
        val texts = event.text.joinToString(" ") + " " + (event.contentDescription ?: "")
        return texts.contains(name, ignoreCase = true)
    }

    /** Whether [event] comes from a security page worth looking at. */
    fun isSecurityPage(context: Context, event: AccessibilityEvent): Boolean {
        val pkg = event.packageName?.toString() ?: return false
        val security = pkg in securityPackages ||
            (pkg == "com.android.settings" && securityClassHints.any { settingsClass.contains(it) })
        return security && !allowed() && activeCached(context)
    }

    /**
     * True when the security page of [pkg] now on screen names the app, e.g.
     * Android's offer to remove its accessibility access.
     */
    fun securityPageShowsApp(service: AccessibilityService, pkg: String): Boolean {
        if (allowed()) return false
        val root = service.rootInActiveWindow
        if (root == null) {
            Log.i(TAG, "security page $pkg: no window content")
            return false
        }
        return try {
            val found = root.packageName?.toString() == pkg &&
                root.findAccessibilityNodeInfosByText(appName(service)).isNotEmpty()
            Log.i(TAG, "security page $pkg (window ${root.packageName}): app named = $found")
            found
        } catch (e: Exception) {
            Log.w(TAG, "security page $pkg: not readable", e)
            false
        }
    }

    /** Time of the last screen change already handled, to act once. */
    @Volatile
    private var lastResumedAt = 0L

    /**
     * True when Android's safety center has just come to the front, as the
     * usage statistics tell (it sends no accessibility events). Needs usage
     * access.
     */
    fun safetyCenterInFront(context: Context): Boolean {
        if (allowed() || !activeCached(context)) return false
        val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
            ?: return false
        val now = System.currentTimeMillis()
        val events = try {
            usm.queryEvents(now - 10_000, now) ?: return false
        } catch (e: Exception) {
            return false
        }
        val e = UsageEvents.Event()
        var pkg: String? = null
        var cls: String? = null
        var at = 0L
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            @Suppress("DEPRECATION")
            if (e.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                pkg = e.packageName
                cls = e.className
                at = e.timeStamp
            }
        }
        if (pkg == null || at <= lastResumedAt) return false
        lastResumedAt = at
        if (pkg !in securityPackages) return false
        Log.i(TAG, "in front (usage statistics): $pkg/$cls")
        return cls?.contains("SafetyCenter", ignoreCase = true) == true
    }

    private fun appName(context: Context): String =
        context.applicationInfo.loadLabel(context.packageManager).toString()
}
