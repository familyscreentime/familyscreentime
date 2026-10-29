package org.familyscreentime

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent

/**
 * Measures what is done in a browser without reading the pages: while a
 * browser is in front, how much it scrolls (the scroll events browsers
 * send to accessibility services: count, gestures and distance) and
 * whether something plays. Every [SAMPLE_MS], and when the browser is left,
 * a sample goes to the monitor, which classes it (video, quick scrolling,
 * other).
 *
 * Any app that opens every web link is a browser: Chrome and the browsers
 * built on it (Edge, Samsung Internet, Brave, Opera…), Firefox, and the
 * others. Sound cannot be tied to an app (Android hides which app plays):
 * what starts while the browser is in front is taken as the browser's;
 * what was already playing (music from another app) is counted apart.
 */
internal class BrowserWatch(
    private val context: Context,
    /** Sends a sample to the monitor. */
    private val send: (Bundle) -> Unit,
) {
    private val main = Handler(Looper.getMainLooper())
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private var browsers: Set<String> = emptySet()
    private var browsersAt = 0L

    /** The browser in front, while one is. */
    private var current: String? = null

    private var sampleStart = 0L
    private var scrolls = 0
    private var bursts = 0
    private var distance = 0L
    private var mediaMs = 0L
    private var otherMediaMs = 0L

    private var lastScrollAt = 0L
    private var lastScrollY = -1

    /** Sound playing at the last check, and whether it began in the browser. */
    private var playing = false
    private var playingHere = false
    private var lastCheck = 0L

    private val tick = object : Runnable {
        override fun run() {
            checkMedia()
            if (SystemClock.elapsedRealtime() - sampleStart >= SAMPLE_MS) flush()
            if (current != null) main.postDelayed(this, TICK_MS)
        }
    }

    /** The apps that open any web link, looked up again now and then. */
    fun browsers(): Set<String> {
        val now = SystemClock.elapsedRealtime()
        if (browsersAt != 0L && now - browsersAt < BROWSERS_TTL_MS) return browsers
        browsersAt = now
        browsers = try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(PROBE_URL))
                .addCategory(Intent.CATEGORY_BROWSABLE)
            context.packageManager
                .queryIntentActivities(intent, PackageManager.MATCH_ALL)
                .map { it.activityInfo.packageName }
                .filter { it != context.packageName }
                .toSet()
        } catch (e: Exception) {
            emptySet()
        }
        return browsers
    }

    /** The app in front changed ([pkg] `null`: none, screen off). */
    fun foreground(pkg: String?) {
        val browser = pkg?.takeIf { it in browsers() }
        if (browser == current) return
        if (current != null) flush()
        main.removeCallbacks(tick)
        current = browser
        if (browser == null) return
        reset()
        lastScrollY = -1
        // Sound already playing belongs to some other app.
        playing = audio.isMusicActive
        playingHere = false
        lastCheck = SystemClock.elapsedRealtime()
        main.postDelayed(tick, TICK_MS)
    }

    /** A scroll event from any app: counted if it is the browser in front. */
    fun onScroll(event: AccessibilityEvent) {
        val pkg = event.packageName?.toString() ?: return
        if (pkg != current) return
        val now = SystemClock.elapsedRealtime()
        scrolls++
        if (now - lastScrollAt > BURST_GAP_MS) bursts++
        lastScrollAt = now
        val y = event.scrollY
        if (y >= 0) {
            if (lastScrollY >= 0) {
                val dy = kotlin.math.abs(y - lastScrollY)
                // A jump of more than the whole page: another page.
                if (event.maxScrollY <= 0 || dy <= event.maxScrollY) distance += dy
            }
            lastScrollY = y
        }
    }

    private fun checkMedia() {
        val now = SystemClock.elapsedRealtime()
        val elapsed = now - lastCheck
        lastCheck = now
        if (playing) {
            if (playingHere) mediaMs += elapsed else otherMediaMs += elapsed
        }
        val active = audio.isMusicActive
        if (active && !playing) playingHere = true
        if (!active) playingHere = false
        playing = active
    }

    private fun flush() {
        val pkg = current ?: return
        checkMedia()
        val endMs = System.currentTimeMillis()
        val length = SystemClock.elapsedRealtime() - sampleStart
        if (length >= MIN_SAMPLE_MS) {
            send(
                Bundle().apply {
                    putString("package", pkg)
                    putLong("start", endMs - length)
                    putLong("end", endMs)
                    putInt("scrolls", scrolls)
                    putInt("bursts", bursts)
                    putLong("scrollDistance", distance)
                    putLong("mediaMs", mediaMs.coerceAtMost(length))
                    putLong("otherMediaMs", otherMediaMs.coerceAtMost(length))
                },
            )
        }
        reset()
    }

    private fun reset() {
        sampleStart = SystemClock.elapsedRealtime()
        scrolls = 0
        bursts = 0
        distance = 0
        mediaMs = 0
        otherMediaMs = 0
    }

    companion object {
        /** A sample every 15 seconds. */
        const val SAMPLE_MS = 15_000L
        private const val MIN_SAMPLE_MS = 1_000L
        private const val TICK_MS = 1_000L

        /** Scrolls further apart than this are separate gestures. */
        private const val BURST_GAP_MS = 1_000L
        private const val BROWSERS_TTL_MS = 10 * 60 * 1000L

        /** A web address no app claims for itself: only browsers open it. */
        private const val PROBE_URL = "https://www.example.com/"
    }
}
