package org.familyscreentime

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle

/**
 * What both processes use: the notification channels, and the app in front
 * according to Android's usage statistics.
 *
 * The app runs in two processes. The main one holds the accessibility
 * service, the floating windows and the blocking ([Enforcer]); it is small,
 * so Android rarely stops it. `:monitor` holds the rule engine in a Flutter
 * engine ([MonitorService]); it is bigger, and Android may stop it when
 * memory runs short, while the main one keeps detecting and blocking.
 */
internal object Shared {
    const val MONITOR_CHANNEL = "monitor"
    const val WARNING_CHANNEL = "warnings"
    const val SHOWN_WARNING_CHANNEL = "warnings_shown"
    const val MONITOR_ID = 1
    const val WARNING_ID = 2
    const val STOPPED_ID = 3

    /** How far back to look for the app in front when it is not known. */
    const val SINCE_UNLOCK_MS = 6 * 60 * 60 * 1000L

    fun notificationManager(context: Context) =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    fun createChannels(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = notificationManager(context)
        nm.createNotificationChannel(
            NotificationChannel(
                MONITOR_CHANNEL,
                context.getString(R.string.monitor_channel),
                NotificationManager.IMPORTANCE_LOW,
            ).apply { setShowBadge(false) },
        )
        nm.createNotificationChannel(
            NotificationChannel(
                WARNING_CHANNEL,
                context.getString(R.string.warning_channel),
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )
        nm.createNotificationChannel(
            NotificationChannel(
                SHOWN_WARNING_CHANNEL,
                context.getString(R.string.shown_warning_channel),
                NotificationManager.IMPORTANCE_LOW,
            ).apply { setShowBadge(false) },
        )
    }

    fun builder(context: Context, channelId: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

    fun openAppIntent(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        0,
        Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    /** The last app that came to the foreground in the last [windowMs]. */
    fun foregroundFromUsageStats(context: Context, windowMs: Long = 15_000): String? {
        val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager ?: return null
        val now = System.currentTimeMillis()
        val events = try {
            usm.queryEvents(now - windowMs, now)
        } catch (e: Exception) {
            null
        } ?: return null
        val e = UsageEvents.Event()
        var latest: String? = null
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            @Suppress("DEPRECATION")
            if (e.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) latest = e.packageName
        }
        return latest
    }

    /** A method call's arguments as a message's data (strings, numbers, flags, lists of strings). */
    fun toBundle(args: Map<*, *>?): Bundle {
        val b = Bundle()
        args?.forEach { (k, v) ->
            val key = k as? String ?: return@forEach
            when (v) {
                null -> {}
                is String -> b.putString(key, v)
                is Boolean -> b.putBoolean(key, v)
                is Int -> b.putInt(key, v)
                is Long -> b.putLong(key, v)
                is Double -> b.putDouble(key, v)
                is List<*> -> b.putStringArrayList(key, ArrayList(v.map { it.toString() }))
                else -> b.putString(key, v.toString())
            }
        }
        return b
    }

    fun long(b: Bundle, key: String): Long? = when (val v = b.get(key)) {
        is Number -> v.toLong()
        else -> null
    }

    fun int(b: Bundle, key: String): Int? = when (val v = b.get(key)) {
        is Number -> v.toInt()
        else -> null
    }
}
