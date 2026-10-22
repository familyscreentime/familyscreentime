package org.familyscreentime

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

/**
 * Device administrator with no policies. Its effect is that the app cannot
 * be uninstalled while it is on; [ProtectionGuard] keeps the child from
 * turning it off in the settings, and parent mode turns it off directly.
 */
class AdminReceiver : DeviceAdminReceiver() {

    /** Shown by Android if the settings are reached anyway. */
    override fun onDisableRequested(context: Context, intent: Intent): CharSequence =
        context.getString(R.string.admin_disable_warning)
}
