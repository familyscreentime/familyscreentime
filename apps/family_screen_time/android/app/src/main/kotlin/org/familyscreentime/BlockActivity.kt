package org.familyscreentime

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.window.OnBackInvokedDispatcher
import java.lang.ref.WeakReference

/**
 * Full-screen notice shown over a blocked app. It is native rather than
 * Flutter so it appears instantly. Its texts come from the monitor, already
 * translated.
 */
class BlockActivity : Activity() {

    private lateinit var title: TextView
    private lateinit var message: TextView
    private lateinit var homeButton: Button
    private lateinit var openButton: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        current = WeakReference(this)
        setContentView(buildLayout())
        bind(intent)
        if (Build.VERSION.SDK_INT >= 33) {
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                OnBackInvokedDispatcher.PRIORITY_DEFAULT,
            ) { goHome() }
        }
    }

    /**
     * Shown again (the screen unlocked, say) once the app may open again:
     * it goes, rather than say "it's over" (the monitor also takes it away
     * then, when it knows).
     */
    override fun onResume() {
        super.onResume()
        val until = intent.getLongExtra(EXTRA_UNTIL, 0L)
        if (until > 0L && System.currentTimeMillis() >= until) finish()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        bind(intent)
    }

    @Deprecated("Kept for Android 12 and older.")
    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        // Going back would show the blocked app again.
        goHome()
    }

    override fun onDestroy() {
        if (current?.get() === this) current = null
        super.onDestroy()
    }

    private fun bind(intent: Intent) {
        title.text = intent.getStringExtra(EXTRA_TITLE) ?: ""
        message.text = intent.getStringExtra(EXTRA_MESSAGE) ?: ""
        homeButton.text = intent.getStringExtra(EXTRA_HOME) ?: "OK"
        openButton.text = intent.getStringExtra(EXTRA_OPEN) ?: "Family Screen Time"
    }

    private fun goHome() {
        startActivity(
            Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_HOME)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION),
        )
        finish()
    }

    private fun buildLayout(): LinearLayout {
        val pad = (24 * resources.displayMetrics.density).toInt()
        title = TextView(this).apply {
            textSize = 26f
            setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
        }
        message = TextView(this).apply {
            textSize = 18f
            gravity = Gravity.CENTER
            setTextColor(Color.parseColor("#E0E0E0"))
            setPadding(0, pad / 2, 0, pad)
        }
        homeButton = Button(this).apply { setOnClickListener { goHome() } }
        openButton = Button(this).apply {
            setOnClickListener {
                startActivity(
                    Intent(this@BlockActivity, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                finish()
            }
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(pad, pad, pad, pad)
            setBackgroundColor(Color.parseColor("#1F2A44"))
            val wrap = ViewGroup.LayoutParams.WRAP_CONTENT
            val match = ViewGroup.LayoutParams.MATCH_PARENT
            addView(title, LinearLayout.LayoutParams(match, wrap))
            addView(message, LinearLayout.LayoutParams(match, wrap))
            addView(homeButton, LinearLayout.LayoutParams(match, wrap))
            addView(openButton, LinearLayout.LayoutParams(match, wrap))
            // Drawn edge to edge (Android 15 and later): the texts and
            // buttons stay clear of the status and navigation bars and of
            // the camera cutout; the background fills the screen.
            androidx.core.view.ViewCompat.setOnApplyWindowInsetsListener(this) { v, insets ->
                val bars = insets.getInsets(
                    androidx.core.view.WindowInsetsCompat.Type.systemBars() or
                        androidx.core.view.WindowInsetsCompat.Type.displayCutout(),
                )
                v.setPadding(pad + bars.left, pad + bars.top, pad + bars.right, pad + bars.bottom)
                insets
            }
        }
    }

    companion object {
        const val EXTRA_TITLE = "title"
        const val EXTRA_MESSAGE = "message"
        const val EXTRA_HOME = "home"
        const val EXTRA_OPEN = "open"
        const val EXTRA_UNTIL = "until"

        private var current: WeakReference<BlockActivity>? = null

        /**
         * Shown over the blocked app. Not as the child's own move
         * (FLAG_ACTIVITY_NO_USER_ACTION): a video app would take it as
         * leaving, and go on in a floating window (picture in picture),
         * which only the accessibility service can close.
         */
        fun show(
            context: Context,
            title: String,
            message: String,
            home: String,
            open: String,
            until: Long = 0L,
        ) {
            context.startActivity(
                Intent(context, BlockActivity::class.java)
                    .addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
                            Intent.FLAG_ACTIVITY_NO_USER_ACTION,
                    )
                    .putExtra(EXTRA_TITLE, title)
                    .putExtra(EXTRA_MESSAGE, message)
                    .putExtra(EXTRA_HOME, home)
                    .putExtra(EXTRA_OPEN, open)
                    .putExtra(EXTRA_UNTIL, until),
            )
        }

        fun dismiss() {
            current?.get()?.finish()
        }
    }
}
