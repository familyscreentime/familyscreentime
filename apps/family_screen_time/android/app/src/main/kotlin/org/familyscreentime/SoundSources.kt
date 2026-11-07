package org.familyscreentime

import android.content.Context
import android.content.pm.ApplicationInfo
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.AudioPlaybackConfiguration
import android.os.Build
import android.os.Handler
import android.os.Looper

/**
 * Where the sound playing now comes from, as far as can be told without
 * any permission: Android hides which app plays, and whether there is a
 * picture, but says when each player starts. A player that starts while an
 * app is in front is taken as that app's: a video plays in the app being
 * watched, while music in the background was started elsewhere (and goes
 * on when another app comes in front).
 *
 * Android 8 and later; before, nothing is known ([fromFront] says `null`).
 */
internal class SoundSources(
    context: Context,
    /** The app in front now. */
    private val front: () -> String?,
) {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val packages = context.packageManager

    /**
     * The media players playing, with the app in front when each started
     * ([UNKNOWN]: already playing when this began watching, after a
     * restart of the process, say).
     */
    private val started = HashMap<Any, String?>()

    init {
        if (Build.VERSION.SDK_INT >= 26) {
            try {
                // Already playing: by which app, no one knows.
                for (c in audio.activePlaybackConfigurations) {
                    if (media(c)) started[c] = UNKNOWN
                }
                audio.registerAudioPlaybackCallback(
                    object : AudioManager.AudioPlaybackCallback() {
                        override fun onPlaybackConfigChanged(
                            configs: MutableList<AudioPlaybackConfiguration>,
                        ) = changed(configs)
                    },
                    Handler(Looper.getMainLooper()),
                )
            } catch (e: Exception) {
                started.clear()
            }
        }
    }

    private fun changed(configs: List<AudioPlaybackConfiguration>) {
        if (Build.VERSION.SDK_INT < 26) return
        val now = configs.filter { media(it) }.toSet()
        started.keys.retainAll(now)
        val pkg = front()
        for (c in now) if (c !in started) started[c] = pkg
    }

    /**
     * Whether media sound plays from [pkg], the app in front: `true` when a
     * player started while it was in front (and it is no music app),
     * `false` when what plays started elsewhere (music in the background)
     * or nothing plays, `null` when Android cannot tell (before Android 8,
     * or a player already playing when this began watching).
     */
    fun fromFront(pkg: String?): Boolean? {
        if (Build.VERSION.SDK_INT < 26) return null
        if (pkg == null || started.isEmpty()) return false
        // A music app in front (it says so itself): music, not a video.
        if (pkg in started.values) return !musicApp(pkg)
        return if (UNKNOWN in started.values) null else false
    }

    private fun musicApp(pkg: String): Boolean = Build.VERSION.SDK_INT >= 26 && try {
        packages.getApplicationInfo(pkg, 0).category == ApplicationInfo.CATEGORY_AUDIO
    } catch (e: Exception) {
        false
    }

    /**
     * Media sound (videos, music, podcasts): not a game's sounds, a call,
     * an alarm or a notification.
     */
    private fun media(c: AudioPlaybackConfiguration): Boolean =
        Build.VERSION.SDK_INT >= 26 &&
            c.audioAttributes.usage == AudioAttributes.USAGE_MEDIA

    private companion object {
        /** A player whose start was not seen. */
        const val UNKNOWN = "?"
    }
}
