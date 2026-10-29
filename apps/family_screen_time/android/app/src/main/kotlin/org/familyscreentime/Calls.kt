package org.familyscreentime

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.os.SystemClock
import android.telecom.TelecomManager

/**
 * Phone calls, which nothing must ever cover or close: a child can always
 * call and be called, whatever the time left.
 *
 * The screens of a call differ from maker to maker (Samsung's is
 * `com.samsung.android.incallui`, for one), so they are not listed by
 * name only: every app that provides Android's in-call screen
 * (`InCallService`) counts, with the default phone app. And while a phone
 * call rings or goes on, the device lock steps aside whatever is in front.
 */
internal object Calls {

    /** Call screens known by name, found even before Android is asked. */
    private val known = setOf(
        "com.android.incallui",
        "com.android.server.telecom",
        "com.android.phone",
        "com.android.emergency",
        "com.android.dialer",
        "com.google.android.dialer",
        "com.samsung.android.incallui",
        "com.samsung.android.dialer",
    )

    private var screens: Set<String> = known
    private var screensAt = 0L

    /** The apps that show a call: in-call screens and the phone app. */
    fun screens(context: Context): Set<String> {
        val now = SystemClock.elapsedRealtime()
        if (screensAt != 0L && now - screensAt < TTL_MS) return screens
        screensAt = now
        val found = HashSet(known)
        try {
            @Suppress("DEPRECATION")
            context.packageManager
                .queryIntentServices(Intent(IN_CALL_SERVICE), PackageManager.GET_META_DATA)
                .forEach { found.add(it.serviceInfo.packageName) }
        } catch (e: Exception) {
            // The names known are kept.
        }
        if (Build.VERSION.SDK_INT >= 23) {
            try {
                (context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager)
                    ?.defaultDialerPackage
                    ?.let { found.add(it) }
            } catch (e: Exception) {
                // Without it, the in-call screens still count.
            }
        }
        found.remove(context.packageName)
        screens = found
        return screens
    }

    fun isScreen(context: Context, pkg: String?): Boolean =
        pkg != null && pkg in screens(context)

    /**
     * Whether a phone call rings or goes on, from the sound's mode, which
     * needs no permission. Calls in other apps (video calls) are not
     * counted: those apps follow the parent's rules.
     */
    fun phoneCall(context: Context): Boolean {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return when (audio.mode) {
            AudioManager.MODE_RINGTONE, AudioManager.MODE_IN_CALL -> true
            // Screening and redirection of a phone call (Android 11, 13).
            MODE_CALL_SCREENING, MODE_CALL_REDIRECT -> true
            else -> false
        }
    }

    /** Any call, a video call in another app included. */
    fun anyCall(context: Context): Boolean {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return phoneCall(context) || audio.mode == AudioManager.MODE_IN_COMMUNICATION
    }

    private const val IN_CALL_SERVICE = "android.telecom.InCallService"
    private const val TTL_MS = 10 * 60 * 1000L
    private const val MODE_CALL_SCREENING = 4
    private const val MODE_CALL_REDIRECT = 5
}
