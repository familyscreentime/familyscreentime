package org.familyscreentime

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView

/**
 * A warning drawn by the app itself at the top of the screen for a few
 * seconds. Unlike a notification's pop-up, it shows over full-screen games
 * whatever the notification settings, Do Not Disturb or game modes. A touch
 * dismisses it.
 */
class WarningBanner(private val context: Context) {

    private val handler = Handler(Looper.getMainLooper())
    private val hideLater = Runnable { hide() }
    private var view: View? = null
    private var target: OverlayHost.Target? = null

    /** False when no overlay layer is available: notify instead. */
    fun show(title: String, text: String): Boolean {
        hide()
        val host = OverlayHost.current(context) ?: return false
        val wm = host.windowManager
        val density = context.resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        val box = LinearLayout(host.context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(12), dp(18), dp(14))
            background = GradientDrawable().apply {
                cornerRadius = 18f * density
                setColor(Color.argb(240, 28, 28, 30))
            }
            elevation = 8f * density
            addView(
                TextView(host.context).apply {
                    this.text = title
                    setTextColor(Color.WHITE)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
                    typeface = Typeface.DEFAULT_BOLD
                },
            )
            if (text.isNotEmpty()) {
                addView(
                    TextView(host.context).apply {
                        this.text = text
                        setTextColor(Color.argb(220, 255, 255, 255))
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                    },
                )
            }
            setOnClickListener { hide() }
        }
        val (w, _) = OverlayHost.screenSize(wm)
        val p = WindowManager.LayoutParams(
            minOf(w - dp(32), dp(460)),
            WindowManager.LayoutParams.WRAP_CONTENT,
            host.type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = dp(20)
            windowAnimations = android.R.style.Animation_Toast
        }
        OverlayHost.fullScreen(p)
        return try {
            wm.addView(box, p)
            view = box
            target = host
            handler.postDelayed(hideLater, SHOWN_MS)
            true
        } catch (e: Exception) {
            false
        }
    }

    fun hide() {
        handler.removeCallbacks(hideLater)
        val v = view ?: return
        try {
            target?.windowManager?.removeView(v)
        } catch (e: Exception) {
            // Already gone, with the service that showed it.
        }
        view = null
        target = null
    }

    private companion object {
        const val SHOWN_MS = 7_000L
    }
}
