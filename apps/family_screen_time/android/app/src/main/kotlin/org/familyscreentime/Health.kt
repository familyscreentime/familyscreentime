package org.familyscreentime

import android.app.AppOpsManager
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.util.Log

/**
 * Whether the monitor can still see and block apps. Some manufacturers
 * (Xiaomi above all) stop an app's services without telling it: the
 * accessibility service then stays ticked in Android's settings but is no
 * longer running, and nothing is detected any more.
 */
object Health {
    private const val PREFS = "monitor"

    /** Ticked in Android's accessibility settings. */
    fun accessibilityEnabled(context: Context): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val me = ComponentName(context, ForegroundAccessibilityService::class.java)
        return enabled.split(':').any {
            ComponentName.unflattenFromString(it) == me
        }
    }

    /** Ticked, but Android stopped it and did not start it again. */
    fun accessibilityStopped(context: Context): Boolean =
        ForegroundAccessibilityService.instance == null && accessibilityEnabled(context)

    /** Xiaomi, Redmi and POCO devices (MIUI, HyperOS). */
    val isXiaomi: Boolean
        get() = listOf("xiaomi", "redmi", "poco").any {
            Build.MANUFACTURER.equals(it, ignoreCase = true) ||
                Build.BRAND.equals(it, ignoreCase = true)
        }

    /**
     * Xiaomi's "Autostart" switch for this app, read from its own app-op
     * (10008); `null` when it cannot be read.
     */
    fun xiaomiAutostart(context: Context): Boolean? {
        if (!isXiaomi) return null
        return try {
            val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val check = AppOpsManager::class.java.getMethod(
                "checkOpNoThrow",
                Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType,
                String::class.java,
            )
            val mode = check.invoke(ops, XIAOMI_AUTOSTART_OP, Process.myUid(), context.packageName) as Int
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            null
        }
    }

    /** Xiaomi's autostart list, where this app can be switched on. */
    fun xiaomiAutostartIntent(): Intent = Intent().setComponent(
        ComponentName(
            "com.miui.securitycenter",
            "com.miui.permcenter.autostart.AutoStartManagementActivity",
        ),
    )

    /**
     * Whether the monitor should run on this device: not on a parent's
     * device. Devices set up before this was recorded run it.
     */
    fun monitorWanted(context: Context): Boolean = !unwantedFile(context).exists()

    /** A file rather than preferences: both processes read it. */
    private fun unwantedFile(context: Context) = java.io.File(context.filesDir, "monitor-unwanted")

    fun setMonitorWanted(context: Context, wanted: Boolean) {
        val file = unwantedFile(context)
        if (wanted) file.delete() else file.createNewFile()
        if (wanted) Watchdog.schedule(context) else Watchdog.cancel(context)
    }

    private const val XIAOMI_AUTOSTART_OP = 10008

    private const val LAST_RESTART = "lastRestart"

    /**
     * Whether this app may restart its own process now to get the
     * accessibility service back (Android binds it again when the process
     * starts): at most once every half hour, so a device where it does not
     * help is not restarted over and over.
     */
    fun mayRestartFor(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        if (now - prefs.getLong(LAST_RESTART, 0L) < 30 * 60 * 1000L) return false
        prefs.edit().putLong(LAST_RESTART, now).commit()
        return true
    }

    /** Why the app's last processes ended, for the logs (Android 11+). */
    fun logExitReasons(context: Context) {
        if (Build.VERSION.SDK_INT < 30) return
        try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            for (info in am.getHistoricalProcessExitReasons(context.packageName, 0, 5)) {
                Log.i(
                    "FamilyScreenTime",
                    "Process ended ${java.text.SimpleDateFormat("MM-dd HH:mm:ss", java.util.Locale.ROOT).format(java.util.Date(info.timestamp))}: " +
                        "reason ${info.reason}, importance ${info.importance}, ${info.description ?: ""}",
                )
            }
        } catch (e: Exception) {
            Log.w("FamilyScreenTime", "Exit reasons not read", e)
        }
    }
}

/**
 * Wakes up every quarter of an hour, and after a reboot, to start the
 * monitor again if Android stopped it.
 */
class Watchdog : JobService() {
    override fun onStartJob(params: JobParameters?): Boolean {
        // Started, or kept: a running monitor only shows its notification again.
        if (Health.monitorWanted(this)) MonitorService.start(this)
        return false
    }

    override fun onStopJob(params: JobParameters?): Boolean = false

    companion object {
        private const val JOB_ID = 7301
        private const val SOON_ID = 7302
        private const val PERIOD_MS = 15 * 60 * 1000L

        fun schedule(context: Context) {
            val jobs = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
            if (jobs.getPendingJob(JOB_ID) != null) return
            val job = JobInfo.Builder(JOB_ID, ComponentName(context, Watchdog::class.java))
                .setPeriodic(PERIOD_MS)
                .setPersisted(true)
                .build()
            try {
                jobs.schedule(job)
            } catch (e: Exception) {
                Log.w("FamilyScreenTime", "Watchdog not scheduled", e)
            }
        }

        /** Starts the monitor again in a few seconds, once. */
        fun soon(context: Context) {
            val jobs = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
            val job = JobInfo.Builder(SOON_ID, ComponentName(context, Watchdog::class.java))
                .setMinimumLatency(3_000)
                .setOverrideDeadline(15_000)
                .build()
            try {
                jobs.schedule(job)
            } catch (e: Exception) {
                Log.w("FamilyScreenTime", "Restart not scheduled", e)
            }
        }

        fun cancel(context: Context) {
            val jobs = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
            jobs.cancel(JOB_ID)
        }
    }
}
