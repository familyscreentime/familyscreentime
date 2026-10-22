package org.familyscreentime

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Covers the whole device when there is no screen time left and the parent
 * chose to lock it, like Family Link: the home screen, the settings and
 * every app stay behind it. The apps the parent keeps available (the phone,
 * say) and this app open from its buttons, and it steps aside while one of
 * them is in front.
 */
class DeviceLockOverlay(private val context: Context) {

    private var view: View? = null
    private var target: OverlayHost.Target? = null
    private var title: TextView? = null
    private var message: TextView? = null

    val isShown: Boolean get() = view != null

    data class Texts(val title: String, val message: String, val open: String)

    /** Apps shown as buttons, to rebuild the screen when they change. */
    private var shownApps: List<String> = emptyList()

    fun show(texts: Texts, apps: List<String>) {
        val host = OverlayHost.current(context) ?: return
        if (view != null && target?.context === host.context && apps == shownApps) {
            title?.text = texts.title
            message?.text = texts.message
            return
        }
        hide()
        val c = host.context
        val density = context.resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        val titleView = TextView(c).apply {
            text = texts.title
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 28f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }
        val messageView = TextView(c).apply {
            text = texts.message
            setTextColor(Color.argb(225, 255, 255, 255))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            gravity = Gravity.CENTER
            setPadding(0, dp(16), 0, dp(32))
        }
        fun button(label: String, launch: () -> Unit) = Button(c).apply {
            text = label
            setOnClickListener { launch() }
        }
        val column = LinearLayout(c).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(32), dp(32), dp(32), dp(32))
            val match = ViewGroup.LayoutParams.MATCH_PARENT
            val wrap = ViewGroup.LayoutParams.WRAP_CONTENT
            addView(titleView, LinearLayout.LayoutParams(match, wrap))
            addView(messageView, LinearLayout.LayoutParams(match, wrap))
            for (app in apps.take(MAX_APPS)) {
                val label = try {
                    c.packageManager.getApplicationLabel(
                        c.packageManager.getApplicationInfo(app, 0),
                    ).toString()
                } catch (e: Exception) {
                    continue
                }
                if (c.packageManager.getLaunchIntentForPackage(app) == null) continue
                addView(button(label) { launch(c, app) }, LinearLayout.LayoutParams(match, wrap))
            }
            addView(
                button(texts.open) { BlockOverlay.openApp(c) },
                LinearLayout.LayoutParams(match, wrap),
            )
        }
        val root = FrameLayout(c).apply {
            setBackgroundColor(Color.rgb(20, 28, 48))
            // Nothing below can be touched.
            isClickable = true
            addView(
                column,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    Gravity.CENTER,
                ),
            )
        }
        val p = WindowManager.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
            host.type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.OPAQUE,
        )
        OverlayHost.fullScreen(p)
        try {
            host.windowManager.addView(root, p)
            view = root
            target = host
            title = titleView
            message = messageView
            shownApps = apps
        } catch (e: Exception) {
            android.util.Log.w("FamilyScreenTime", "Device lock not shown", e)
        }
    }

    fun hide() {
        val v = view ?: return
        try {
            target?.windowManager?.removeView(v)
        } catch (e: Exception) {
            // Already gone, with the service that showed it.
        }
        view = null
        target = null
        title = null
        message = null
    }

    private companion object {
        const val MAX_APPS = 4
    }

    private fun launch(c: Context, pkg: String) {
        val intent = c.packageManager.getLaunchIntentForPackage(pkg) ?: return
        try {
            c.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: Exception) {
            android.util.Log.w("FamilyScreenTime", "Not opened: $pkg", e)
        }
    }
}
