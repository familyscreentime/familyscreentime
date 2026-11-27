package org.familyscreentime

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Starts the monitor after a reboot or an app update. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Diag.init(context)
        Diag.i("Started by ${intent.action}")
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED ->
                if (Health.monitorWanted(context)) MonitorService.start(context)
        }
    }
}
