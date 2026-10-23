package org.familyscreentime

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Foreground service that keeps the monitor alive. It runs the rule engine
 * in a Flutter engine without interface (Dart entry point `monitorMain`),
 * feeds it the foreground app and screen state, and carries out what it
 * decides: countdown notification, warnings and block screen.
 */
class MonitorService : Service(), MethodChannel.MethodCallHandler {

    private var engine: FlutterEngine? = null
    private lateinit var overlay: CountdownOverlay
    private lateinit var banner: WarningBanner
    private lateinit var blockNotice: BlockOverlay
    private lateinit var deviceLock: DeviceLockOverlay
    lateinit var volume: VolumeGuard
        private set

    /** No screen time left and the parent chose to lock the whole device. */
    private var deviceLocked = false
    private var lockTexts = DeviceLockOverlay.Texts("", "", "")

    /** Apps that stay open on a locked device. */
    private var lockExempt: List<String> = emptyList()
    private var settingsTitle = ""
    private var settingsMessage = ""
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())
    private var lastForeground: String? = null
    private var screenOn = true

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_OFF -> setScreen(false)
                // The lock screen is not screen time: count from unlocking.
                Intent.ACTION_SCREEN_ON -> if (!keyguardLocked()) setScreen(true)
                Intent.ACTION_USER_PRESENT -> setScreen(true)
            }
            updateDeviceLock()
        }
    }

    /** Polls usage statistics when the accessibility service is off. */
    private val poller = object : Runnable {
        override fun run() {
            if (screenOn && ForegroundAccessibilityService.instance == null) {
                foregroundFromUsageStats()?.let { onForegroundApp(it) }
            }
            main.postDelayed(this, POLL_MS)
        }
    }

    /**
     * While uninstall protection is on, watches for Android's safety center,
     * which hides from accessibility services since Android 14.
     */
    private val safetyWatcher = object : Runnable {
        override fun run() {
            val accessibility = ForegroundAccessibilityService.instance
            if (screenOn && accessibility != null && ProtectionGuard.safetyCenterInFront(this@MonitorService)) {
                accessibility.closeProtected()
            }
            main.postDelayed(this, SAFETY_POLL_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        overlay = CountdownOverlay(this)
        banner = WarningBanner(this)
        blockNotice = BlockOverlay(this)
        deviceLock = DeviceLockOverlay(this)
        volume = VolumeGuard(this)
        createChannels()
        val notification = buildNotification(getString(R.string.monitor_starting), null, null)
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(MONITOR_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(MONITOR_ID, notification)
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(screenReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(screenReceiver, filter)
        }
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        screenOn = pm.isInteractive && !keyguardLocked()
        startEngine()
        main.postDelayed(poller, POLL_MS)
        main.postDelayed(safetyWatcher, SAFETY_POLL_MS)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        instance = null
        overlay.hide()
        banner.hide()
        blockNotice.hide()
        deviceLock.hide()
        volume.stop()
        main.removeCallbacks(poller)
        main.removeCallbacks(safetyWatcher)
        unregisterReceiver(screenReceiver)
        engine?.destroy()
        engine = null
        super.onDestroy()
    }

    private fun startEngine() {
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)
        val flutter = FlutterEngine(applicationContext)
        val messenger = flutter.dartExecutor.binaryMessenger
        channel = MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(this) }
        PlatformBridge(applicationContext).attach(messenger)
        flutter.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "monitorMain"),
        )
        engine = flutter
    }

    /** Called by the accessibility service or the poller. */
    fun onForegroundApp(pkg: String) {
        main.post {
            // A volume raised in parent mode comes back under the cap.
            volume.enforce()
            if (pkg == lastForeground) return@post
            lastForeground = pkg
            updateDeviceLock()
            channel?.invokeMethod("foreground", mapOf("package" to pkg))
        }
    }

    /**
     * The app in front according to the usage statistics, when a window
     * change did not name an activity.
     */
    fun confirmForeground() {
        if (!screenOn) return
        foregroundFromUsageStats()?.let { onForegroundApp(it) }
    }

    /** Asks the monitor to reload the rules after a change. */
    fun reload() {
        main.post { channel?.invokeMethod("reload", null) }
    }

    private fun keyguardLocked(): Boolean =
        (getSystemService(Context.KEYGUARD_SERVICE) as android.app.KeyguardManager)
            .isKeyguardLocked

    private fun setScreen(on: Boolean) {
        if (on == screenOn) return
        screenOn = on
        if (!on) lastForeground = null
        channel?.invokeMethod("screen", mapOf("on" to on))
        // Unlocking straight into an app sends no window change: look up
        // the last app that came to the foreground instead.
        if (on) foregroundFromUsageStats(SINCE_UNLOCK_MS)?.let { onForegroundApp(it) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "state" -> result.success(
                mapOf("foreground" to lastForeground, "screenOn" to screenOn),
            )
            "countdown" -> {
                val n = buildNotification(
                    call.argument<String>("title") ?: "",
                    call.argument<String>("text"),
                    call.argument<Number>("endsAt")?.toLong(),
                )
                notificationManager().notify(MONITOR_ID, n)
                result.success(null)
            }
            "warn" -> {
                warn(call.argument<String>("title") ?: "", call.argument<String>("text") ?: "")
                result.success(null)
            }
            "block" -> {
                block(
                    call.argument<String>("title") ?: "",
                    call.argument<String>("message") ?: "",
                    call.argument<String>("package"),
                    call.argument<String>("closed"),
                    call.argument<String>("ok") ?: "OK",
                    call.argument<String>("home") ?: "OK",
                    call.argument<String>("open") ?: "Family Screen Time",
                )
                result.success(null)
            }
            "overlay" -> {
                overlay.show(
                    call.argument<Number>("endsAt")?.toLong() ?: 0L,
                    call.argument<String>("style") ?: "digits",
                )
                result.success(null)
            }
            "lockState" -> {
                ProtectionGuard.settingsLocked = call.argument<Boolean>("settingsLocked") ?: false
                deviceLocked = call.argument<Boolean>("deviceLocked") ?: false
                lockTexts = DeviceLockOverlay.Texts(
                    call.argument<String>("title") ?: "",
                    call.argument<String>("message") ?: "",
                    call.argument<String>("open") ?: "",
                )
                lockExempt = call.argument<List<String>>("exempt") ?: emptyList()
                settingsTitle = call.argument<String>("settingsTitle") ?: ""
                settingsMessage = call.argument<String>("settingsMessage") ?: ""
                updateDeviceLock()
                // Settings already open when they close: leave them.
                val accessibility = ForegroundAccessibilityService.instance
                if (ProtectionGuard.settingsLocked && !ProtectionGuard.allowed() &&
                    lastForeground in ProtectionGuard.settingsPackages
                ) {
                    accessibility?.closeSettings()
                }
                result.success(null)
            }
            "overlayHide" -> {
                overlay.hide()
                result.success(null)
            }
            "volumeCap" -> {
                volume.set(
                    call.argument<Int>("headphones"),
                    call.argument<Int>("speaker"),
                    call.argument<String>("message") ?: "",
                )
                result.success(null)
            }
            "familyChanged" -> {
                // Settings changed on another device: the interface reloads.
                PlatformBridge.uiChannel?.invokeMethod("familyChanged", null)
                result.success(null)
            }
            "unblock" -> {
                BlockActivity.dismiss()
                blockNotice.hide()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * The accessibility service started or stopped: floating windows move
     * to the layer now available (its own, above full-screen games).
     */
    fun overlayHostChanged() {
        overlay.rehost()
        banner.hide()
    }

    /**
     * Sends the child home and says why. With the accessibility service, the
     * notice is drawn over the home screen; otherwise a full-screen activity
     * covers the blocked app.
     */
    private fun block(
        title: String,
        message: String,
        pkg: String?,
        closed: String?,
        ok: String,
        home: String,
        open: String,
    ) {
        // Parent mode: nothing closes, whatever the time (system screens
        // such as device administration may belong to apps with no time
        // left). The monitor checks again when parent mode ends.
        if (ProtectionGuard.allowed()) return
        banner.hide()
        val app = pkg ?: lastForeground
        val text = if (closed != null && app != null) {
            "$message\n${closed.replace("{app}", appLabel(app))}"
        } else {
            message
        }
        val accessibility = ForegroundAccessibilityService.instance
        if (accessibility != null) {
            accessibility.goHome()
            // The device lock says it all.
            if (deviceLocked) {
                updateDeviceLock()
                if (deviceLock.isShown) return
            }
            if (blockNotice.show(title, text, ok, open)) return
        }
        // Activities may be started from an accessibility service, or from a
        // service whose app may draw over other apps.
        val starter: Context = accessibility ?: this
        try {
            BlockActivity.show(starter, title, text, home, open)
        } catch (e: Exception) {
            warn(title, text)
        }
    }

    /** Settings closed while there is no time left: says why. */
    fun showSettingsNotice() {
        if (deviceLocked) return
        val shown = blockNotice.show(
            settingsTitle,
            settingsMessage,
            getString(android.R.string.ok),
            getString(R.string.protected_open),
        )
        if (!shown) warn(settingsTitle, settingsMessage)
    }

    /**
     * Shows or hides the device lock: shown while the device is locked,
     * unlocked by the child (not on the lock screen), and neither an app
     * kept available, this app nor parent mode is in front.
     */
    fun updateDeviceLock() {
        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
        val fg = lastForeground
        val exempt = fg != null && (
            fg == packageName || fg in lockExempt || fg in callScreens
            )
        val show = deviceLocked && screenOn && !keyguard.isKeyguardLocked &&
            !exempt && !ProtectionGuard.allowed()
        if (show) {
            banner.hide()
            blockNotice.hide()
            deviceLock.show(lockTexts, lockExempt)
        } else {
            deviceLock.hide()
        }
    }

    /** A protected settings page was just closed: says why. */
    fun showProtectedNotice() {
        val shown = blockNotice.show(
            getString(R.string.protected_title),
            getString(R.string.protected_message),
            getString(android.R.string.ok),
            getString(R.string.protected_open),
        )
        if (!shown) warn(getString(R.string.protected_title), getString(R.string.protected_message))
    }

    private fun appLabel(pkg: String): String = try {
        val info = packageManager.getApplicationInfo(pkg, 0)
        packageManager.getApplicationLabel(info).toString()
    } catch (e: Exception) {
        pkg
    }

    private fun foregroundFromUsageStats(windowMs: Long = 15_000): String? {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager ?: return null
        val now = System.currentTimeMillis()
        val events = usm.queryEvents(now - windowMs, now) ?: return null
        val e = UsageEvents.Event()
        var latest: String? = null
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            @Suppress("DEPRECATION")
            if (e.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) latest = e.packageName
        }
        return latest
    }

    private fun notificationManager() =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = notificationManager()
        nm.createNotificationChannel(
            NotificationChannel(
                MONITOR_CHANNEL,
                getString(R.string.monitor_channel),
                NotificationManager.IMPORTANCE_LOW,
            ).apply { setShowBadge(false) },
        )
        nm.createNotificationChannel(
            NotificationChannel(
                WARNING_CHANNEL,
                getString(R.string.warning_channel),
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )
        nm.createNotificationChannel(
            NotificationChannel(
                SHOWN_WARNING_CHANNEL,
                getString(R.string.shown_warning_channel),
                NotificationManager.IMPORTANCE_LOW,
            ).apply { setShowBadge(false) },
        )
    }

    private fun builder(channelId: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

    private fun openAppIntent(): PendingIntent = PendingIntent.getActivity(
        this,
        0,
        Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    /** Ongoing notification; with [endsAt], Android shows a live countdown. */
    private fun buildNotification(title: String, text: String?, endsAt: Long?): Notification {
        val b = builder(MONITOR_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentIntent(openAppIntent())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
        if (text != null) b.setContentText(text)
        if (endsAt != null) {
            b.setWhen(endsAt).setShowWhen(true).setUsesChronometer(true)
            if (Build.VERSION.SDK_INT >= 24) b.setChronometerCountDown(true)
        } else {
            b.setShowWhen(false)
        }
        return b.build()
    }

    /**
     * Shows the warning on screen, over full-screen apps too; it is also
     * kept, quietly, in the notifications. Without any overlay layer, the
     * notification pops up instead.
     */
    private fun warn(title: String, text: String) {
        val shown = banner.show(title, text)
        val n = builder(if (shown) SHOWN_WARNING_CHANNEL else WARNING_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(openAppIntent())
            .setAutoCancel(true)
            .build()
        notificationManager().notify(WARNING_ID, n)
    }

    companion object {
        const val CHANNEL = "org.familyscreentime/monitor"
        private const val MONITOR_CHANNEL = "monitor"
        private const val WARNING_CHANNEL = "warnings"
        private const val SHOWN_WARNING_CHANNEL = "warnings_shown"
        private const val MONITOR_ID = 1
        private const val WARNING_ID = 2
        private const val POLL_MS = 3_000L
        private const val SAFETY_POLL_MS = 1_000L

        /** In-call screens, which must never be covered. */
        private val callScreens = setOf(
            "com.android.incallui",
            "com.android.server.telecom",
            "com.android.phone",
            "com.android.emergency",
            "com.google.android.dialer",
        )
        private const val SINCE_UNLOCK_MS = 6 * 60 * 60 * 1000L

        @Volatile
        var instance: MonitorService? = null

        /**
         * Starts the monitor. Android may refuse to start a foreground
         * service from the background; the next app launch, boot or
         * accessibility connection tries again.
         */
        fun start(context: Context) {
            val intent = Intent(context, MonitorService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= 26) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: IllegalStateException) {
                android.util.Log.w("FamilyScreenTime", "Monitor not started", e)
            }
        }
    }
}
