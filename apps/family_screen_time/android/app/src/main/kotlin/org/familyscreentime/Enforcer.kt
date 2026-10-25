package org.familyscreentime

import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.PowerManager
import android.os.RemoteException
import android.os.SystemClock
import android.util.Log

/**
 * The main process's side of the monitor: it knows the app in front (from
 * the accessibility service), and carries out what the rule engine decides
 * in the `:monitor` process: block screens, warnings, the floating
 * countdown, the device lock and the volume cap.
 *
 * It keeps what it was told while the monitor is away (stopped by Android
 * for memory, say): the device stays locked, and an app blocked in the last
 * hours is blocked again, until the monitor is back and decides again.
 */
@Suppress("StaticFieldLeak") // The application context only.
internal object Enforcer {
    private lateinit var app: Context
    private val main = Handler(Looper.getMainLooper())

    private lateinit var overlay: CountdownOverlay
    private lateinit var banner: WarningBanner
    private lateinit var blockNotice: BlockOverlay
    private lateinit var deviceLock: DeviceLockOverlay
    lateinit var volume: VolumeGuard
        private set

    /** The monitor's messenger, while it is connected. */
    private var monitor: Messenger? = null
    private var lastForeground: String? = null
    private var screenOn = true

    private var deviceLocked = false
    private var lockTexts = DeviceLockOverlay.Texts("", "", "")
    private var lockExempt: List<String> = emptyList()
    private var settingsTitle = ""
    private var settingsMessage = ""

    /** Apps blocked lately, with the notice shown, for while the monitor is away. */
    private val recentBlocks = HashMap<String, Pair<Long, Bundle>>()
    private const val RECENT_BLOCK_MS = 3 * 60 * 60 * 1000L

    private var started = false
    private var lastMonitorStart = 0L

    fun get(context: Context): Enforcer {
        if (started) return this
        started = true
        app = context.applicationContext
        overlay = CountdownOverlay(app)
        banner = WarningBanner(app)
        blockNotice = BlockOverlay(app)
        deviceLock = DeviceLockOverlay(app)
        volume = VolumeGuard(app)
        Shared.createChannels(app)
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            app.registerReceiver(screenReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            app.registerReceiver(screenReceiver, filter)
        }
        val pm = app.getSystemService(Context.POWER_SERVICE) as PowerManager
        screenOn = pm.isInteractive && !keyguardLocked()
        main.postDelayed(safetyWatcher, SAFETY_POLL_MS)
        Log.i(TAG, "Enforcer started")
        return this
    }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_OFF -> {
                    screenOn = false
                    lastForeground = null
                    lastVisible = emptyList()
                }
                Intent.ACTION_SCREEN_ON -> if (!keyguardLocked()) screenOn = true
                Intent.ACTION_USER_PRESENT -> screenOn = true
            }
            updateDeviceLock()
        }
    }

    /**
     * While uninstall protection is on, watches for Android's safety center,
     * which hides from accessibility services since Android 14.
     */
    private val safetyWatcher = object : Runnable {
        override fun run() {
            val accessibility = ForegroundAccessibilityService.instance
            if (screenOn && accessibility != null && ProtectionGuard.safetyCenterInFront(app)) {
                accessibility.closeProtected()
            }
            main.postDelayed(this, SAFETY_POLL_MS)
        }
    }

    private fun keyguardLocked(): Boolean =
        (app.getSystemService(Context.KEYGUARD_SERVICE) as android.app.KeyguardManager)
            .isKeyguardLocked

    // --- From the accessibility service ---------------------------------------

    /**
     * Another app came in front, seen by the accessibility service, or by
     * the monitor ([fromMonitor]) when that service is not running.
     */
    fun onForegroundApp(pkg: String, fromMonitor: Boolean = false) {
        main.post {
            // A volume raised in parent mode comes back under the cap.
            volume.enforce()
            if (pkg == lastForeground) return@post
            lastForeground = pkg
            updateDeviceLock()
            if (fromMonitor) return@post
            if (!send("foreground", Bundle().apply { putString("package", pkg) })) {
                // The monitor is away: an app blocked lately stays blocked.
                blockAgain(pkg)
                startMonitor()
            }
        }
    }

    /** Apps on screen, as last told to the monitor. */
    private var lastVisible: List<String> = emptyList()

    /**
     * The apps with a window on screen (split screen, floating windows…),
     * from the accessibility service: told to the monitor when they change.
     */
    fun visibleApps(apps: List<String>) {
        main.post {
            val sorted = apps.sorted()
            if (sorted == lastVisible) return@post
            lastVisible = sorted
            send("visible", Bundle().apply { putStringArrayList("packages", ArrayList(sorted)) })
        }
    }

    /** The app in front according to the usage statistics, after a window change that named none. */
    fun confirmForeground() {
        if (!screenOn) return
        Shared.foregroundFromUsageStats(app)?.let { onForegroundApp(it) }
    }

    /** The accessibility service started or stopped. */
    fun accessibilityChanged() {
        main.post {
            // Floating windows move to the layer now available.
            overlay.rehost()
            banner.hide()
            sendStatus()
        }
    }

    private fun sendStatus() {
        send(
            "status",
            Bundle().apply {
                putBoolean("accessibility", ForegroundAccessibilityService.instance != null)
                putString("foreground", lastForeground)
                putStringArrayList("visible", ArrayList(lastVisible))
            },
        )
    }

    // --- The monitor ----------------------------------------------------------

    /** The monitor connected, or connected again. */
    fun monitorConnected(messenger: Messenger) {
        monitor = messenger
        Log.i(TAG, "Monitor connected")
        sendStatus()
    }

    fun monitorGone() {
        monitor = null
        Log.w(TAG, "Monitor gone")
    }

    val monitorConnected: Boolean get() = monitor != null

    /** Sends [cmd] to the monitor; whether it is there. */
    fun send(cmd: String, data: Bundle = Bundle()): Boolean {
        val m = monitor ?: return false
        return try {
            m.send(Message.obtain(null, MSG).apply { this.data = data.apply { putString("cmd", cmd) } })
            true
        } catch (e: RemoteException) {
            monitor = null
            false
        }
    }

    /** The monitor reads the settings again; started if it is not running. */
    fun reloadMonitor() {
        if (!send("reload")) startMonitor()
    }

    private fun startMonitor() {
        val now = SystemClock.elapsedRealtime()
        if (now - lastMonitorStart < 10_000 || !Health.monitorWanted(app)) return
        lastMonitorStart = now
        MonitorService.start(app)
    }

    /** What the monitor asks. */
    fun handle(data: Bundle) {
        when (data.getString("cmd")) {
            "foreground" -> data.getString("package")?.let { onForegroundApp(it, fromMonitor = true) }
            "block" -> block(data)
            "unblock" -> {
                recentBlocks.clear()
                BlockActivity.dismiss()
                blockNotice.hide()
            }
            "warn" -> warn(data.getString("title") ?: "", data.getString("text") ?: "")
            "overlay" -> overlay.show(
                Shared.long(data, "endsAt") ?: 0L,
                data.getString("style") ?: "digits",
            )
            "overlayHide" -> overlay.hide()
            "lockState" -> lockState(data)
            "volumeCap" -> volume.set(
                Shared.int(data, "headphones"),
                Shared.int(data, "speaker"),
                data.getString("message") ?: "",
            )
            "familyChanged" -> PlatformBridge.uiChannel?.invokeMethod("familyChanged", null)
            "restart" -> restartForAccessibility()
        }
    }

    private fun lockState(data: Bundle) {
        ProtectionGuard.settingsLocked = data.getBoolean("settingsLocked", false)
        deviceLocked = data.getBoolean("deviceLocked", false)
        lockTexts = DeviceLockOverlay.Texts(
            data.getString("title") ?: "",
            data.getString("message") ?: "",
            data.getString("open") ?: "",
        )
        lockExempt = data.getStringArrayList("exempt") ?: emptyList()
        settingsTitle = data.getString("settingsTitle") ?: ""
        settingsMessage = data.getString("settingsMessage") ?: ""
        updateDeviceLock()
        // Settings already open when they close: leave them.
        if (ProtectionGuard.settingsLocked && !ProtectionGuard.allowed() &&
            lastForeground in ProtectionGuard.settingsPackages
        ) {
            ForegroundAccessibilityService.instance?.closeSettings()
        }
    }

    /**
     * Android binds the accessibility service again when this process
     * starts: it restarts (the monitor's link starts it again at once),
     * unless the child is using the app's own screens.
     */
    private fun restartForAccessibility() {
        if (ForegroundAccessibilityService.instance != null) return
        if (MainActivity.visible || !Health.mayRestartFor(app)) return
        Log.w(TAG, "Restarting the main process to get the accessibility service back")
        Watchdog.soon(app)
        main.postDelayed({ android.os.Process.killProcess(android.os.Process.myPid()) }, 500)
    }

    // --- What it shows --------------------------------------------------------

    /**
     * Sends the child home and says why. With the accessibility service, the
     * notice is drawn over the home screen; otherwise a full-screen activity
     * covers the blocked app.
     */
    private fun block(data: Bundle) {
        // Parent mode: nothing closes, whatever the time (system screens
        // such as device administration may belong to apps with no time
        // left). The monitor checks again when parent mode ends.
        if (ProtectionGuard.allowed()) return
        banner.hide()
        val app = data.getString("package") ?: lastForeground
        if (app != null) recentBlocks[app] = SystemClock.elapsedRealtime() to Bundle(data)
        val title = data.getString("title") ?: ""
        val message = data.getString("message") ?: ""
        val closed = data.getString("closed")
        val text = if (closed != null && app != null) {
            "$message\n${closed.replace("{app}", appLabel(app))}"
        } else {
            message
        }
        val ok = data.getString("ok") ?: "OK"
        val home = data.getString("home") ?: "OK"
        val open = data.getString("open") ?: "Family Screen Time"
        val accessibility = ForegroundAccessibilityService.instance
        // Only in a floating video window, beside the app in front: that
        // window closes, the app in front stays.
        if (accessibility != null && app != null && app != lastForeground &&
            accessibility.closePictureInPicture { it == app }
        ) {
            if (!blockNotice.show(title, text, ok, open)) warn(title, text)
            return
        }
        accessibility?.goHome()
        // Leaving a video for the home screen may float it in a small
        // window (picture in picture): closed as it appears.
        if (app != null) {
            for (delay in PIP_CHECKS_MS) {
                main.postDelayed({ closePictureInPicture(app) }, delay)
            }
        }
        // The device lock says it all: shown now, or as soon as the child
        // unlocks the screen. The block notice before it would show two
        // screens one after the other.
        if (deviceLocked) {
            updateDeviceLock()
            if (deviceLock.isShown || keyguardLocked() || !screenOn) return
        }
        if (accessibility != null && blockNotice.show(title, text, ok, open)) return
        // Activities may be started from an accessibility service, or from
        // an app that may draw over other apps.
        val starter: Context = accessibility ?: this.app
        try {
            BlockActivity.show(starter, title, text, home, open)
        } catch (e: Exception) {
            warn(title, text)
        }
    }

    /** Closes [pkg]'s floating video window, if it has one. */
    private fun closePictureInPicture(pkg: String) {
        ForegroundAccessibilityService.instance?.closePictureInPicture { it == pkg }
    }

    /**
     * A window appeared or went: a floating video window of an app blocked
     * in the last minutes is closed (started again from the notification,
     * say).
     */
    fun checkPictureInPicture() {
        if (ProtectionGuard.allowed() || recentBlocks.isEmpty()) return
        val now = SystemClock.elapsedRealtime()
        ForegroundAccessibilityService.instance?.closePictureInPicture { pkg ->
            val at = recentBlocks[pkg]?.first
            at != null && now - at < PIP_WATCH_MS
        }
    }

    /**
     * Pauses what is playing (a floating video that would not close): the
     * media session in use gets the pause key.
     */
    fun pauseMedia() {
        val audio = app.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
        for (action in listOf(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.ACTION_UP)) {
            audio.dispatchMediaKeyEvent(
                android.view.KeyEvent(action, android.view.KeyEvent.KEYCODE_MEDIA_PAUSE),
            )
        }
    }

    /** An app blocked lately, opened while the monitor is away. */
    private fun blockAgain(pkg: String) {
        val (at, data) = recentBlocks[pkg] ?: return
        if (SystemClock.elapsedRealtime() - at > RECENT_BLOCK_MS) {
            recentBlocks.remove(pkg)
            return
        }
        Log.i(TAG, "Blocked again while the monitor is away: $pkg")
        block(Bundle(data).apply { putString("package", pkg) })
    }

    /** Settings closed while there is no time left: says why. */
    fun showSettingsNotice() {
        if (deviceLocked) return
        val shown = blockNotice.show(
            settingsTitle,
            settingsMessage,
            app.getString(android.R.string.ok),
            app.getString(R.string.protected_open),
        )
        if (!shown) warn(settingsTitle, settingsMessage)
    }

    /** A protected settings page was just closed: says why. */
    fun showProtectedNotice() {
        val shown = blockNotice.show(
            app.getString(R.string.protected_title),
            app.getString(R.string.protected_message),
            app.getString(android.R.string.ok),
            app.getString(R.string.protected_open),
        )
        if (!shown) warn(app.getString(R.string.protected_title), app.getString(R.string.protected_message))
    }

    /**
     * Shows or hides the device lock: shown while the device is locked,
     * unlocked by the child (not on the lock screen), and neither an app
     * kept available, this app nor parent mode is in front.
     */
    fun updateDeviceLock() {
        if (!started) return
        val fg = lastForeground
        val exempt = fg != null && (
            fg == app.packageName || fg in lockExempt || fg in callScreens
            )
        val show = deviceLocked && screenOn && !keyguardLocked() &&
            !exempt && !ProtectionGuard.allowed()
        if (show) {
            banner.hide()
            blockNotice.hide()
            deviceLock.show(lockTexts, lockExempt)
        } else {
            deviceLock.hide()
        }
    }

    /**
     * Shows the warning on screen, over full-screen apps too; it is also
     * kept, quietly, in the notifications. Without any overlay layer, the
     * notification pops up instead.
     */
    private fun warn(title: String, text: String) {
        val shown = banner.show(title, text)
        val n = Shared.builder(app, if (shown) Shared.SHOWN_WARNING_CHANNEL else Shared.WARNING_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(Shared.openAppIntent(app))
            .setAutoCancel(true)
            .build()
        Shared.notificationManager(app).notify(Shared.WARNING_ID, n)
    }

    private fun appLabel(pkg: String): String = try {
        val pm = app.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (e: Exception) {
        pkg
    }

    const val MSG = 1

    /** When to look for a floating video window after a block. */
    private val PIP_CHECKS_MS = listOf(600L, 1_500L, 3_000L)

    /** How long after a block a floating video window of the app is closed. */
    private const val PIP_WATCH_MS = 10 * 60 * 1000L
    private const val TAG = "FamilyScreenTime"
    private const val SAFETY_POLL_MS = 1_000L

    /** In-call screens, which must never be covered. */
    private val callScreens = setOf(
        "com.android.incallui",
        "com.android.server.telecom",
        "com.android.phone",
        "com.android.emergency",
        "com.google.android.dialer",
    )
}

/**
 * The [Enforcer]'s door for the monitor, which binds to it from its own
 * process: messages both ways, each a `cmd` and its data.
 */
class EnforcerService : Service() {
    private val incoming = Messenger(
        Handler(Looper.getMainLooper()) { msg ->
            val data = msg.data ?: return@Handler true
            if (data.getString("cmd") == "hello") {
                msg.replyTo?.let { Enforcer.monitorConnected(it) }
            } else {
                Enforcer.handle(data)
            }
            true
        },
    )

    override fun onCreate() {
        super.onCreate()
        Enforcer.get(this)
    }

    override fun onBind(intent: Intent?): IBinder = incoming.binder

    override fun onUnbind(intent: Intent?): Boolean {
        Enforcer.monitorGone()
        return false
    }
}
