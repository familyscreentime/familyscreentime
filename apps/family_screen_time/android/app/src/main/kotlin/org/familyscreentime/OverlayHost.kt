package org.familyscreentime

import android.content.Context
import android.os.Build
import android.provider.Settings
import android.util.DisplayMetrics
import android.view.WindowManager

/**
 * Where floating windows go.
 *
 * While the accessibility service runs, its own overlay layer: it sits above
 * every app, full-screen games included, and needs no other permission.
 * Otherwise the ordinary "display over other apps" layer, when allowed.
 */
internal object OverlayHost {

    class Target(val context: Context, val type: Int) {
        val windowManager: WindowManager
            get() = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    }

    fun current(fallback: Context): Target? {
        val accessibility = ForegroundAccessibilityService.instance
        if (accessibility != null && Build.VERSION.SDK_INT >= 22) {
            return Target(accessibility, WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
        }
        if (Build.VERSION.SDK_INT >= 23 && !Settings.canDrawOverlays(fallback)) return null
        val type = if (Build.VERSION.SDK_INT >= 26) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        return Target(fallback.applicationContext, type)
    }

    /** Whole screen, system bars included, in the current orientation. */
    fun screenSize(wm: WindowManager): Pair<Int, Int> =
        if (Build.VERSION.SDK_INT >= 30) {
            val b = wm.currentWindowMetrics.bounds
            b.width() to b.height()
        } else {
            val m = DisplayMetrics()
            @Suppress("DEPRECATION")
            wm.defaultDisplay.getRealMetrics(m)
            m.widthPixels to m.heightPixels
        }

    /** Laid out against the whole screen, cutouts and hidden bars included. */
    fun fullScreen(params: WindowManager.LayoutParams) {
        params.flags = params.flags or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
        if (Build.VERSION.SDK_INT >= 30) {
            params.fitInsetsTypes = 0
            params.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
        } else if (Build.VERSION.SDK_INT >= 28) {
            params.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }
}
