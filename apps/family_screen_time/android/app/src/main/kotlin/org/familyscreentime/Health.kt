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
    private const val WANTED = "wanted"

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
    fun monitorWanted(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(WANTED, true)

    fun setMonitorWanted(context: Context, wanted: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(WANTED, wanted).apply()
        if (wanted) Watchdog.schedule(context) else Watchdog.cancel(context)
    }

    private const val XIAOMI_AUTOSTART_OP = 10008
}

/**
 * Wakes up every quarter of an hour, and after a reboot, to start the
 * monitor again if Android stopped it.
 */
class Watchdog : JobService() {
    override fun onStartJob(params: JobParameters?): Boolean {
        if (Health.monitorWanted(this) && MonitorService.instance == null) {
            Log.i("FamilyScreenTime", "Watchdog: starting the monitor again")
            MonitorService.start(this)
        }
        return false
    }

    override fun onStopJob(params: JobParameters?): Boolean = false

    companion object {
        private const val JOB_ID = 7301
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

        fun cancel(context: Context) {
            val jobs = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
            jobs.cancel(JOB_ID)
        }
    }
}
