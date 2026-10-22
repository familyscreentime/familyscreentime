package org.familyscreentime

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Says why an app was just closed ("Time is up…"), over the home screen the
 * child was sent to, so the closing is not taken for a crash. Drawn in the
 * accessibility service's layer: unlike an activity, nothing can come in
 * front of it before it is read. Stays until dismissed.
 */
class BlockOverlay(private val context: Context) {

    private var view: View? = null
    private var target: OverlayHost.Target? = null
    private var title: TextView? = null
    private var message: TextView? = null

    /** False when no overlay layer is available. */
    fun show(title: String, message: String, ok: String, open: String): Boolean {
        if (view != null && OverlayHost.current(context)?.context === target?.context) {
            this.title?.text = title
            this.message?.text = message
            return true
        }
        hide()
        val host = OverlayHost.current(context) ?: return false
        val c = host.context
        val density = context.resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        val titleView = TextView(c).apply {
            text = title
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }
        val messageView = TextView(c).apply {
            text = message
            setTextColor(Color.argb(225, 255, 255, 255))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            gravity = Gravity.CENTER
            setPadding(0, dp(10), 0, dp(18))
        }
        val okButton = Button(c).apply {
            text = ok
            setOnClickListener { hide() }
        }
        val openButton = Button(c).apply {
            text = open
            setOnClickListener {
                hide()
                openApp(c)
            }
        }
        val card = LinearLayout(c).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(24), dp(24), dp(16))
            background = GradientDrawable().apply {
                cornerRadius = 24f * density
                setColor(Color.rgb(31, 42, 68))
            }
            val match = ViewGroup.LayoutParams.MATCH_PARENT
            val wrap = ViewGroup.LayoutParams.WRAP_CONTENT
            addView(titleView, LinearLayout.LayoutParams(match, wrap))
            addView(messageView, LinearLayout.LayoutParams(match, wrap))
            addView(okButton, LinearLayout.LayoutParams(match, wrap))
            addView(openButton, LinearLayout.LayoutParams(match, wrap))
        }
        val root = FrameLayout(c).apply {
            setBackgroundColor(Color.argb(170, 0, 0, 0))
            // Touches around the card are swallowed, not passed below.
            isClickable = true
            addView(
                card,
                FrameLayout.LayoutParams(dp(340), ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER),
            )
        }
        val p = android.view.WindowManager.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
            host.type,
            android.view.WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        )
        OverlayHost.fullScreen(p)
        return try {
            host.windowManager.addView(root, p)
            view = root
            target = host
            this.title = titleView
            this.message = messageView
            true
        } catch (e: Exception) {
            false
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

    companion object {
        fun openApp(context: Context) {
            try {
                context.startActivity(
                    Intent(context, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
                )
            } catch (e: Exception) {
                android.util.Log.w("FamilyScreenTime", "App not opened", e)
            }
        }
    }
}
