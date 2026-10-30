package org.familyscreentime

import android.Manifest
import android.app.Activity
import android.app.AppOpsManager
import android.app.NotificationManager
import android.app.admin.DevicePolicyManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import android.provider.Telephony
import android.telecom.TelecomManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * Platform services shared by the interface and the monitor: permission
 * checks, settings screens, installed apps, and control of the monitor.
 *
 * [activity] is set when the bridge serves the interface: some settings
 * screens refuse to open in a new task.
 */
class PlatformBridge(
    private val context: Context,
    private val activity: Activity? = null,
) : MethodChannel.MethodCallHandler {

    fun attach(messenger: BinaryMessenger) {
        val channel = MethodChannel(messenger, CHANNEL)
        channel.setMethodCallHandler(this)
        // The interface's channel, for calls from Android to it.
        if (activity != null) uiChannel = channel
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "permissionStatus" -> result.success(permissionStatus())
            "openPermissionSettings" -> {
                // Opened by the parent: the guarded pages may open for a while.
                ProtectionGuard.allowFor(SETTINGS_ALLOWANCE_MS)
                result.success(openPermissionSettings(call.argument<String>("kind") ?: ""))
            }
            "launcherApps" -> {
                // Reading every app's name takes a while: off the main thread.
                worker.execute {
                    val apps = launcherApps()
                    main.post { result.success(apps) }
                }
            }
            "appInfo" -> {
                val packages = call.argument<List<String>>("packages") ?: emptyList()
                val size = call.argument<Int>("size")
                // Drawing icons takes a moment: off the main thread.
                worker.execute {
                    val info = appInfo(packages, size)
                    main.post { result.success(info) }
                }
            }
            "systemPackages" -> result.success(systemPackages())
            "appVersion" -> result.success(appVersion())
            "usageHistory" -> {
                val from = call.argument<Number>("from")?.toLong() ?: 0L
                val to = call.argument<Number>("to")?.toLong() ?: System.currentTimeMillis()
                worker.execute {
                    val segments = try {
                        usageHistory(from, to, call.argument<Boolean>("closeOpen") ?: false)
                    } catch (e: SecurityException) {
                        null
                    }
                    main.post { result.success(segments) }
                }
            }
            "startMonitor" -> {
                Health.setMonitorWanted(context, true)
                MonitorService.start(context)
                result.success(null)
            }
            "reloadMonitor" -> {
                Enforcer.get(context).reloadMonitor()
                result.success(null)
            }
            "deviceName" -> result.success("${Build.MANUFACTURER} ${Build.MODEL}")
            "parentMode" -> {
                val on = call.argument<Boolean>("on") ?: false
                val ms = call.argument<Number>("forMs")?.toLong() ?: 0L
                ProtectionGuard.allowFor(if (on) ms else 0L)
                if (on) {
                    ParentModeNotice.show(
                        context,
                        call.argument<String>("title") ?: "",
                        call.argument<String>("text") ?: "",
                        call.argument<String>("leave") ?: "",
                    )
                } else {
                    ParentModeNotice.hide(context)
                }
                val enforcer = Enforcer.get(context)
                enforcer.updateDeviceLock()
                if (!on) {
                    // Leaving parent mode: the volume comes back under the
                    // cap, and the app in front is checked again.
                    enforcer.volume.enforce()
                    enforcer.reloadMonitor()
                }
                result.success(null)
            }
            "shareFile" -> result.success(
                shareFile(
                    call.argument<String>("path") ?: "",
                    call.argument<String>("mime") ?: "application/octet-stream",
                    call.argument<String>("subject") ?: "",
                ),
            )
            "disableDeviceAdmin" -> {
                val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                dpm.removeActiveAdmin(ComponentName(context, AdminReceiver::class.java))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Offers a file of the app's cache (an export) to the apps that take
     * one, through the app's FileProvider.
     */
    private fun shareFile(path: String, mime: String, subject: String): Boolean {
        return try {
            val file = java.io.File(path)
            val uri = androidx.core.content.FileProvider.getUriForFile(
                context,
                "${context.packageName}.files",
                file,
            )
            val send = Intent(Intent.ACTION_SEND)
                .setType(mime)
                .putExtra(Intent.EXTRA_STREAM, uri)
                .putExtra(Intent.EXTRA_SUBJECT, subject)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            val chooser = Intent.createChooser(send, subject)
            if (activity != null) {
                activity.startActivity(chooser)
            } else {
                context.startActivity(chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            true
        } catch (e: Exception) {
            android.util.Log.w("FamilyScreenTime", "File not shared", e)
            false
        }
    }

    /**
     * The accessibility service counts only while it runs: ticked but
     * stopped by the system, it is reported as `accessibilityStopped`. On
     * Xiaomi devices, `autostart` is their own switch (or
     * `autostartUnknown` when it cannot be read).
     */
    private fun permissionStatus(): Map<String, Boolean> {
        val enabled = Health.accessibilityEnabled(context)
        val running = ForegroundAccessibilityService.instance != null
        val status = mutableMapOf(
            "accessibility" to (enabled && running),
            "usageAccess" to hasUsageAccess(),
            "overlay" to (Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(context)),
            "notifications" to notificationsAllowed(),
            "battery" to isIgnoringBatteryOptimizations(),
            "deviceAdmin" to isDeviceAdmin(),
        )
        if (enabled && !running) status["accessibilityStopped"] = true
        if (Health.isXiaomi) {
            val autostart = Health.xiaomiAutostart(context)
            if (autostart == null) {
                status["autostartUnknown"] = true
            } else {
                status["autostart"] = autostart
            }
        }
        return status
    }

    private fun hasUsageAccess(): Boolean {
        val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        @Suppress("DEPRECATION")
        val mode = if (Build.VERSION.SDK_INT >= 29) {
            ops.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        } else {
            ops.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun notificationsAllowed(): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return nm.areNotificationsEnabled()
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < 23) return true
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun isDeviceAdmin(): Boolean {
        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        return dpm.isAdminActive(ComponentName(context, AdminReceiver::class.java))
    }

    /** Opens the settings screen for a permission. Returns false if unknown. */
    private fun openPermissionSettings(kind: String): Boolean {
        val pkg = Uri.parse("package:${context.packageName}")
        val intent = when (kind) {
            "accessibility" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            "usageAccess" -> Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            "overlay" -> Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, pkg)
            "notifications" -> if (Build.VERSION.SDK_INT >= 26) {
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg)
            }
            "battery" -> Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, pkg)
            "deviceAdmin" -> Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                .putExtra(
                    DevicePolicyManager.EXTRA_DEVICE_ADMIN,
                    ComponentName(context, AdminReceiver::class.java),
                )
                .putExtra(
                    DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                    context.getString(R.string.admin_description),
                )
            "appDetails" -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg)
            "autostart" -> Health.xiaomiAutostartIntent()
            else -> return false
        }
        // The device-admin screen closes at once when opened as a new task,
        // so it is started from the activity.
        val starter: Context = activity ?: context
        if (activity == null) {
            if (kind == "deviceAdmin") return false
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            starter.startActivity(intent)
            true
        } catch (e: Exception) {
            // Some manufacturers remove screens; fall back to the app's page.
            context.startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            false
        }
    }

    /** Apps with a launcher icon, which the parent can put in groups. */
    private fun launcherApps(): List<Map<String, String>> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        @Suppress("DEPRECATION")
        val activities = pm.queryIntentActivities(intent, 0)
        return activities
            .map { it.activityInfo.packageName to it.loadLabel(pm).toString() }
            .filter { it.first != context.packageName }
            .distinctBy { it.first }
            .sortedBy { it.second.lowercase() }
            .map { mapOf("package" to it.first, "label" to it.second) }
    }

    /**
     * Names and icons (PNG) of the given packages. Packages that are not
     * installed, or not visible to this app, are left out.
     */
    private fun appInfo(packages: List<String>, iconSize: Int? = null): Map<String, Map<String, Any>> {
        val pm = context.packageManager
        // A given size in pixels (icons shared with the family's devices
        // are kept small), or 48 dp.
        val size = iconSize
            ?: (48 * context.resources.displayMetrics.density).toInt().coerceIn(48, 144)
        val out = HashMap<String, Map<String, Any>>()
        for (pkg in packages) {
            try {
                @Suppress("DEPRECATION")
                val info = pm.getApplicationInfo(pkg, 0)
                val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
                val drawable = pm.getApplicationIcon(info)
                drawable.setBounds(0, 0, size, size)
                drawable.draw(Canvas(bitmap))
                val png = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, png)
                out[pkg] = mapOf(
                    "label" to pm.getApplicationLabel(info).toString(),
                    "icon" to png.toByteArray(),
                )
            } catch (e: PackageManager.NameNotFoundException) {
                // Uninstalled since, or hidden by package visibility.
            }
        }
        return out
    }

    /**
     * Rebuilds foreground sessions from Android's usage events between
     * [from] and [to] (milliseconds). Android keeps these events about ten
     * days. Returns `null` without usage access.
     */
    /** [closeOpen]: the use still going on counts up to [to]. */
    private fun usageHistory(from: Long, to: Long, closeOpen: Boolean = false): List<Map<String, Any>>? {
        val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = usm.queryEvents(from, to) ?: return null
        val out = ArrayList<Map<String, Any>>()
        var current: String? = null
        var start = 0L
        var pausedAt: Long? = null

        fun close(end: Long) {
            val pkg = current ?: return
            if (end > start) out.add(mapOf("package" to pkg, "start" to start, "end" to end))
            current = null
            pausedAt = null
        }

        val e = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            val t = e.timeStamp
            @Suppress("DEPRECATION")
            when (e.eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                    if (e.packageName != current) {
                        close(t)
                        current = e.packageName
                        start = t
                    }
                    pausedAt = null
                }
                UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                    if (e.packageName == current) pausedAt = t
                }
                SCREEN_NON_INTERACTIVE, KEYGUARD_SHOWN, DEVICE_SHUTDOWN -> {
                    close(pausedAt ?: t)
                }
            }
        }
        // Use still going on: up to the last pause, or not at all.
        pausedAt?.let { close(it) }
        if (closeOpen) close(to)
        return out
    }

    /** This app's version: its name (0.28.1) and its number (55). */
    private fun appVersion(): Map<String, Any?> {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        val build = if (Build.VERSION.SDK_INT >= 28) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return mapOf("version" to info.versionName, "build" to build)
    }

    /** Packages with a special role: dialer, SMS, home screens, this app. */
    private fun systemPackages(): Map<String, Any?> {
        val pm = context.packageManager
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        @Suppress("DEPRECATION")
        val launchers = pm.queryIntentActivities(home, 0)
            .map { it.activityInfo.packageName }
            .distinct()
        val dialer = if (Build.VERSION.SDK_INT >= 23) {
            (context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager)
                ?.defaultDialerPackage
        } else {
            null
        }
        return mapOf(
            "self" to context.packageName,
            "dialer" to dialer,
            "sms" to Telephony.Sms.getDefaultSmsPackage(context),
            "launchers" to launchers,
            "callScreens" to Calls.screens(context).toList(),
        )
    }

    private val main = Handler(Looper.getMainLooper())

    companion object {
        const val CHANNEL = "org.familyscreentime/platform"

        /** Channel of the interface, while it runs. */
        @Volatile
        var uiChannel: MethodChannel? = null

        /** Time to change a setting after the app opened its page. */
        private const val SETTINGS_ALLOWANCE_MS = 3 * 60 * 1000L
        private val worker = Executors.newSingleThreadExecutor()

        // UsageEvents.Event constants added in API 28 and 29.
        private const val SCREEN_NON_INTERACTIVE = 16
        private const val KEYGUARD_SHOWN = 17
        private const val DEVICE_SHUTDOWN = 26
    }
}
