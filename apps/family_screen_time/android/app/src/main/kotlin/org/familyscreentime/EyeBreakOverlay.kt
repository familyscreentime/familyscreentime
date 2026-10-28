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
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/**
 * The eye break, drawn by the app itself over every app: first a notice at
 * the top of the screen, with "now" and, while the child may still put it
 * off, "in 1 min"; then a veil over the whole screen, with a countdown and
 * an invitation to look into the distance. The veil takes the touches but
 * not the sound, and goes by itself at the end of the countdown. The
 * monitor decides when each comes; [onAnswer] tells it what the child
 * chose ("now", "later").
 */
class EyeBreakOverlay(
    private val context: Context,
    private val onAnswer: (String) -> Unit,
) {

    private val handler = Handler(Looper.getMainLooper())
    private var notice: View? = null
    private var noticeHost: OverlayHost.Target? = null
    private var veil: View? = null
    private var veilHost: OverlayHost.Target? = null
    private var countdown: TextView? = null
    private var veilEndsAt = 0L

    private val hideNoticeLater = Runnable { hideNotice() }

    private val tick = object : Runnable {
        override fun run() {
            val left = veilEndsAt - System.currentTimeMillis()
            if (left <= 0) {
                hideVeil()
                return
            }
            countdown?.text = ((left + 999) / 1000).toString()
            handler.postDelayed(this, TICK_MS)
        }
    }

    private fun dp(v: Int) = (v * context.resources.displayMetrics.density).toInt()

    /** False when no overlay layer is available. */
    fun showNotice(title: String, text: String, now: String, later: String?, endsAt: Long): Boolean {
        hideNotice()
        val host = OverlayHost.current(context) ?: return false
        val c = host.context
        val density = context.resources.displayMetrics.density
        val wrap = ViewGroup.LayoutParams.WRAP_CONTENT

        val buttons = LinearLayout(c).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
            setPadding(0, dp(8), 0, 0)
            if (later != null) {
                addView(
                    Button(c).apply {
                        this.text = later
                        setOnClickListener { answer("later") }
                    },
                    LinearLayout.LayoutParams(wrap, wrap).apply { marginEnd = dp(8) },
                )
            }
            addView(
                Button(c).apply {
                    this.text = now
                    setOnClickListener { answer("now") }
                },
                LinearLayout.LayoutParams(wrap, wrap),
            )
        }
        val box = LinearLayout(c).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(12), dp(18), dp(12))
            background = GradientDrawable().apply {
                cornerRadius = 18f * density
                setColor(Color.argb(240, 28, 28, 30))
            }
            elevation = 8f * density
            addView(
                TextView(c).apply {
                    this.text = title
                    setTextColor(Color.WHITE)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
                    typeface = Typeface.DEFAULT_BOLD
                },
            )
            addView(
                TextView(c).apply {
                    this.text = text
                    setTextColor(Color.argb(220, 255, 255, 255))
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                },
            )
            addView(buttons)
        }
        val (w, _) = OverlayHost.screenSize(host.windowManager)
        val p = WindowManager.LayoutParams(
            minOf(w - dp(32), dp(460)),
            WindowManager.LayoutParams.WRAP_CONTENT,
            host.type,
            // Touches beside it go to the app below.
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
            host.windowManager.addView(box, p)
            notice = box
            noticeHost = host
            handler.postDelayed(hideNoticeLater, maxOf(0L, endsAt - System.currentTimeMillis()))
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun answer(choice: String) {
        hideNotice()
        onAnswer(choice)
    }

    /** False when no overlay layer is available. */
    fun showVeil(title: String, text: String, endsAt: Long): Boolean {
        hideNotice()
        hideVeil()
        if (endsAt <= System.currentTimeMillis()) return true
        val host = OverlayHost.current(context) ?: return false
        val c = host.context
        val match = ViewGroup.LayoutParams.MATCH_PARENT
        val wrap = ViewGroup.LayoutParams.WRAP_CONTENT

        val count = TextView(c).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 72f)
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            gravity = Gravity.CENTER
        }
        val column = LinearLayout(c).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(32), 0, dp(32), 0)
            addView(count, LinearLayout.LayoutParams(match, wrap))
            addView(
                TextView(c).apply {
                    this.text = title
                    setTextColor(Color.WHITE)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 26f)
                    typeface = Typeface.DEFAULT_BOLD
                    gravity = Gravity.CENTER
                    setPadding(0, dp(12), 0, dp(8))
                },
                LinearLayout.LayoutParams(match, wrap),
            )
            addView(
                TextView(c).apply {
                    this.text = text
                    setTextColor(Color.argb(220, 255, 255, 255))
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
                    gravity = Gravity.CENTER
                },
                LinearLayout.LayoutParams(match, wrap),
            )
        }
        val root = FrameLayout(c).apply {
            setBackgroundColor(Color.argb(235, 12, 20, 32))
            // The touches stay on the veil.
            isClickable = true
            addView(column, FrameLayout.LayoutParams(match, wrap, Gravity.CENTER))
        }
        val p = WindowManager.LayoutParams(
            match,
            match,
            host.type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply { windowAnimations = android.R.style.Animation_Dialog }
        OverlayHost.fullScreen(p)
        return try {
            host.windowManager.addView(root, p)
            veil = root
            veilHost = host
            countdown = count
            veilEndsAt = endsAt
            tick.run()
            true
        } catch (e: Exception) {
            false
        }
    }

    fun hide() {
        hideNotice()
        hideVeil()
    }

    private fun hideNotice() {
        handler.removeCallbacks(hideNoticeLater)
        val v = notice ?: return
        try {
            noticeHost?.windowManager?.removeView(v)
        } catch (e: Exception) {
            // Already gone, with the service that showed it.
        }
        notice = null
        noticeHost = null
    }

    private fun hideVeil() {
        handler.removeCallbacks(tick)
        val v = veil ?: return
        try {
            veilHost?.windowManager?.removeView(v)
        } catch (e: Exception) {
            // Already gone, with the service that showed it.
        }
        veil = null
        veilHost = null
        countdown = null
    }

    private companion object {
        const val TICK_MS = 250L
    }
}
