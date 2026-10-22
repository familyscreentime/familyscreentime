package org.familyscreentime

import android.annotation.SuppressLint
import android.content.Context
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.min

/**
 * Small floating countdown shown over limited apps, when the child asks for
 * it: either digits, or a disc in the style of a Time Timer (the red sector
 * is the time left, on a 60-minute dial). It counts down by itself from
 * the end time given by the monitor, and can be dragged; a tap opens the
 * app.
 *
 * Shown in the accessibility service's overlay layer when it runs, so it
 * stays visible over full-screen games. Its position is remembered as a
 * fraction of the screen, so it stays on screen in both orientations.
 */
class CountdownOverlay(private val context: Context) {

    private val prefs = context.getSharedPreferences("overlay", Context.MODE_PRIVATE)
    private var view: CountdownView? = null
    private var target: OverlayHost.Target? = null
    private var params: WindowManager.LayoutParams? = null
    private var lastEndsAt = 0L
    private var lastStyle = "digits"

    fun show(endsAt: Long, style: String) {
        lastEndsAt = endsAt
        lastStyle = style
        val host = OverlayHost.current(context) ?: run {
            hide()
            return
        }
        // The accessibility service started or stopped: move to its layer.
        if (view != null && target?.context !== host.context) hide()
        val v = view ?: create(host) ?: return
        v.endsAt = endsAt
        v.style = style
        v.invalidate()
    }

    fun hide() {
        val v = view ?: return
        v.removeCallbacks(v.ticker)
        try {
            target?.windowManager?.removeView(v)
        } catch (e: Exception) {
            // Already gone, with the service that showed it.
        }
        view = null
        target = null
        params = null
    }

    /** Shows the countdown again in the layer that is now available. */
    fun rehost() {
        if (view == null) return
        hide()
        show(lastEndsAt, lastStyle)
    }

    private val size: Int
        get() = (64 * context.resources.displayMetrics.density).toInt()

    /** Puts the countdown at its remembered place on the current screen. */
    private fun place(host: OverlayHost.Target, p: WindowManager.LayoutParams) {
        val (w, h) = OverlayHost.screenSize(host.windowManager)
        p.x = (prefs.getFloat("fx", 0.04f) * (w - size)).toInt().coerceIn(0, maxOf(0, w - size))
        p.y = (prefs.getFloat("fy", 0.12f) * (h - size)).toInt().coerceIn(0, maxOf(0, h - size))
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun create(host: OverlayHost.Target): CountdownView? {
        val wm = host.windowManager
        val p = WindowManager.LayoutParams(
            size,
            size,
            host.type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply { gravity = Gravity.TOP or Gravity.START }
        OverlayHost.fullScreen(p)
        place(host, p)
        val v = CountdownView(host.context)
        v.onRotated = {
            if (view === v) {
                place(host, p)
                try {
                    wm.updateViewLayout(v, p)
                } catch (e: Exception) {
                    // Removed meanwhile.
                }
            }
        }
        val slop = ViewConfiguration.get(host.context).scaledTouchSlop
        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var dragging = false
        v.setOnTouchListener { _, e ->
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX
                    downY = e.rawY
                    startX = p.x
                    startY = p.y
                    dragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    if (!dragging && abs(e.rawX - downX) <= slop && abs(e.rawY - downY) <= slop) {
                        return@setOnTouchListener true
                    }
                    dragging = true
                    val (w, h) = OverlayHost.screenSize(wm)
                    p.x = (startX + (e.rawX - downX).toInt()).coerceIn(0, maxOf(0, w - size))
                    p.y = (startY + (e.rawY - downY).toInt()).coerceIn(0, maxOf(0, h - size))
                    wm.updateViewLayout(v, p)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    // A tap, not a drag: open the app (time left, rules).
                    if (!dragging) {
                        BlockOverlay.openApp(host.context)
                    } else {
                        val (w, h) = OverlayHost.screenSize(wm)
                        prefs.edit()
                            .putFloat("fx", p.x.toFloat() / maxOf(1, w - size))
                            .putFloat("fy", p.y.toFloat() / maxOf(1, h - size))
                            .apply()
                    }
                    true
                }
                else -> false
            }
        }
        return try {
            wm.addView(v, p)
            view = v
            target = host
            params = p
            v.post(v.ticker)
            v
        } catch (e: Exception) {
            null
        }
    }
}

private class CountdownView(context: Context) : View(context) {
    var endsAt = 0L
    var style = "digits"
    var onRotated: (() -> Unit)? = null

    override fun onConfigurationChanged(newConfig: Configuration?) {
        super.onConfigurationChanged(newConfig)
        // The new screen size is known once the change is laid out.
        post { onRotated?.invoke() }
    }

    private val density = resources.displayMetrics.density
    private val face = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(235, 255, 255, 255) }
    private val rim = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1.5f * density
        color = Color.argb(160, 0, 0, 0)
    }
    private val red = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(220, 40, 40) }
    private val ink = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(30, 30, 30)
        textAlign = Paint.Align.CENTER
        isFakeBoldText = true
    }
    private val oval = RectF()

    val ticker: Runnable = object : Runnable {
        override fun run() {
            invalidate()
            postDelayed(this, 1000)
        }
    }

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        val r = min(w, h) / 2f - rim.strokeWidth
        val cx = w / 2f
        val cy = h / 2f
        val left = ((endsAt - System.currentTimeMillis()) / 1000L).coerceAtLeast(0L)
        canvas.drawCircle(cx, cy, r, face)
        canvas.drawCircle(cx, cy, r, rim)
        if (style == "disc") {
            // 60-minute dial; the red sector shrinks towards 12 o'clock.
            val fraction = min(left, 3600L) / 3600f
            val inset = r * 0.12f
            oval.set(cx - r + inset, cy - r + inset, cx + r - inset, cy + r - inset)
            canvas.drawArc(oval, -90f, -360f * fraction, true, red)
            if (left > 3600L) {
                ink.textSize = 11f * density
                canvas.drawText(label(left), cx, cy + ink.textSize / 3f, ink)
            }
        } else {
            ink.textSize = (if (left >= 3600L) 13f else 15f) * density
            canvas.drawText(label(left), cx, cy + ink.textSize / 3f, ink)
        }
    }

    /** "12:05" under an hour, "1 h 25" above. */
    private fun label(seconds: Long): String {
        if (seconds >= 3600L) {
            val minutes = ceil(seconds / 60.0).toLong()
            return "${minutes / 60} h ${(minutes % 60).toString().padStart(2, '0')}"
        }
        return "${seconds / 60}:${(seconds % 60).toString().padStart(2, '0')}"
    }
}
