package org.familyscreentime

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper

/**
 * Notification shown while parent mode is on, with a button to leave it at
 * once, from anywhere.
 */
object ParentModeNotice {
    private const val CHANNEL_ID = "parent_mode"
    private const val ID = 3
    const val ACTION_LEAVE = "org.familyscreentime.LEAVE_PARENT_MODE"

    fun show(context: Context, title: String, text: String, leave: String) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    context.getString(R.string.parent_mode_channel),
                    NotificationManager.IMPORTANCE_LOW,
                ).apply { setShowBadge(false) },
            )
        }
        val leaveIntent = PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, LeaveParentModeReceiver::class.java).setAction(ACTION_LEAVE),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val open = PendingIntent.getActivity(
            context,
            1,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val n = builder
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(
                Notification.Action.Builder(null, leave, leaveIntent).build(),
            )
            .build()
        nm.notify(ID, n)
    }

    fun hide(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(ID)
    }
}

/** "Leave parent mode" from the notification. */
class LeaveParentModeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ParentModeNotice.ACTION_LEAVE) return
        ProtectionGuard.allowFor(0)
        ParentModeNotice.hide(context)
        MonitorService.instance?.updateDeviceLock()
        // The interface closes its parent screens, if it runs.
        Handler(Looper.getMainLooper()).post {
            PlatformBridge.uiChannel?.invokeMethod("leaveParentMode", null)
        }
    }
}
