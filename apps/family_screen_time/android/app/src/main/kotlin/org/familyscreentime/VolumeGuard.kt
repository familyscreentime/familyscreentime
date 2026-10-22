package org.familyscreentime

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.ContentObserver
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.widget.Toast

/**
 * Keeps the media volume (music, videos, games) under the caps the parent
 * set, one for headphones and one for the speaker, in percent of the
 * maximum. Calls, ringtone and alarms are left alone. Not applied in
 * parent mode.
 */
class VolumeGuard(private val context: Context) {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val main = Handler(Looper.getMainLooper())

    private var headphones: Int? = null
    private var speaker: Int? = null
    private var message = ""
    private var started = false
    private var toldAt = 0L

    private val observer = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean) = enforce()
    }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, intent: Intent?) = enforce()
    }

    private val devices = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>?) = enforce()
        override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>?) = enforce()
    }

    /** New caps, in percent; `null`: no cap. [message] has "{percent}". */
    fun set(headphones: Int?, speaker: Int?, message: String) {
        this.headphones = headphones?.takeIf { it < 100 }
        this.speaker = speaker?.takeIf { it < 100 }
        this.message = message
        if (this.headphones == null && this.speaker == null) {
            stop()
        } else {
            start()
            enforce()
        }
    }

    private fun start() {
        if (started) return
        started = true
        // Volume changes are saved in the system settings; the broadcast
        // and the audio devices cover the rest (headphones plugged in).
        context.contentResolver.registerContentObserver(
            Settings.System.CONTENT_URI, true, observer,
        )
        val filter = IntentFilter(VOLUME_CHANGED)
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
        audio.registerAudioDeviceCallback(devices, main)
    }

    fun stop() {
        if (!started) return
        started = false
        context.contentResolver.unregisterContentObserver(observer)
        try {
            context.unregisterReceiver(receiver)
        } catch (e: IllegalArgumentException) {
            // Not registered.
        }
        audio.unregisterAudioDeviceCallback(devices)
    }

    /** Brings the media volume back under the cap for the current output. */
    fun enforce() {
        if (!started || ProtectionGuard.allowed()) return
        val cap = (if (headphonesOn()) headphones else speaker) ?: return
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val allowed = maxOf(1, max * cap / 100)
        val current = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
        if (current <= allowed) return
        try {
            audio.setStreamVolume(AudioManager.STREAM_MUSIC, allowed, AudioManager.FLAG_SHOW_UI)
        } catch (e: SecurityException) {
            return
        }
        // Said once in a while, not at every press of the button.
        val now = SystemClock.elapsedRealtime()
        if (now - toldAt > 4_000 && message.isNotEmpty()) {
            toldAt = now
            Toast.makeText(context, message.replace("{percent}", "$cap"), Toast.LENGTH_SHORT).show()
        }
    }

    private fun headphonesOn(): Boolean =
        audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { it.type in HEADPHONES }

    companion object {
        private const val VOLUME_CHANGED = "android.media.VOLUME_CHANGED_ACTION"

        private val HEADPHONES = buildSet {
            add(AudioDeviceInfo.TYPE_WIRED_HEADSET)
            add(AudioDeviceInfo.TYPE_WIRED_HEADPHONES)
            add(AudioDeviceInfo.TYPE_BLUETOOTH_A2DP)
            add(AudioDeviceInfo.TYPE_USB_HEADSET)
            if (Build.VERSION.SDK_INT >= 31) {
                add(AudioDeviceInfo.TYPE_BLE_HEADSET)
            }
        }
    }
}
