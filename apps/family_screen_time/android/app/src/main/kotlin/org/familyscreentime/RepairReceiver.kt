package org.familyscreentime

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Switches the accessibility service's component off and on, as the app
 * does by itself when Android left the service stopped (see
 * [Enforcer.repairAccessibility]). For tests from a computer only: the
 * DUMP permission is the shell's, no app may send it.
 *
 *     adb shell am broadcast -a org.familyscreentime.REPAIR_ACCESSIBILITY -p <package>
 */
class RepairReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        Enforcer.get(context).repairAccessibility { pending.finish() }
    }
}
