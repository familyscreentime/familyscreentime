package org.familyscreentime

import android.app.Notification
import android.app.Service
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.ServiceConnection
import android.content.pm.ServiceInfo
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
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Foreground service that keeps the monitor alive, in its own process
 * (`:monitor`). It runs the rule engine in a Flutter engine without
 * interface (Dart entry point `monitorMain`), feeds it the app in front and
 * the screen's state, and passes what it decides to the main process's
 * [Enforcer], which shows it. Android may stop this process when memory
 * runs short: the main one keeps detecting and blocking meanwhile, and the
 * monitor, started again, takes up where it was.
 */
class MonitorService : Service(), MethodChannel.MethodCallHandler {

    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())
    private var lastForeground: String? = null
    private var screenOn = true
    private var notification: Notification? = null

    // --- The link with the main process ---------------------------------------

    private var enforcer: Messenger? = null

    /** Whether the accessibility service runs, as the main process said. */
    private var accessibilityRuns = false
    private var bound = false

    /** The last state sent to the main process, sent again when it connects. */
    private val lastState = LinkedHashMap<String, Bundle>()

    private val incoming = Messenger(
        Handler(Looper.getMainLooper()) { msg ->
            msg.data?.let { fromEnforcer(it) }
            true
        },
    )

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            val m = Messenger(binder)
            enforcer = m
            try {
                m.send(Message.obtain(null, Enforcer.MSG).apply {
                    data = Bundle().apply { putString("cmd", "hello") }
                    replyTo = incoming
                })
            } catch (e: RemoteException) {
                enforcer = null
                return
            }
            for (state in lastState.values) toEnforcer(Bundle(state))
            Log.i(TAG, "Connected to the main process")
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            // The main process stopped: Android starts it again (the
            // binding asks for it), and it connects back.
            enforcer = null
            accessibilityRuns = false
            Log.w(TAG, "Main process gone")
        }

        override fun onBindingDied(name: ComponentName?) {
            enforcer = null
            accessibilityRuns = false
            unbind()
            main.postDelayed({ bind() }, 1_000)
        }
    }

    private fun bind() {
        if (bound) return
        bound = bindService(
            Intent(this, EnforcerService::class.java),
            connection,
            Context.BIND_AUTO_CREATE or Context.BIND_IMPORTANT,
        )
    }

    private fun unbind() {
        if (!bound) return
        bound = false
        try {
            unbindService(connection)
        } catch (e: IllegalArgumentException) {
            // Not bound any more.
        }
    }

    private fun toEnforcer(data: Bundle): Boolean {
        val m = enforcer ?: return false
        return try {
            m.send(Message.obtain(null, Enforcer.MSG).apply { this.data = data })
            true
        } catch (e: RemoteException) {
            enforcer = null
            false
        }
    }

    /** Sends a call from the rule engine; state calls are kept for later. */
    private fun forward(cmd: String, args: Map<*, *>?) {
        val data = Shared.toBundle(args).apply { putString("cmd", cmd) }
        when (cmd) {
            "lockState", "volumeCap" -> lastState[cmd] = data
            "overlay", "overlayHide" -> lastState["overlay"] = data
        }
        toEnforcer(data)
    }

    private fun fromEnforcer(data: Bundle) {
        when (data.getString("cmd")) {
            "foreground" -> data.getString("package")?.let { onForegroundApp(it, fromEnforcer = true) }
            "status" -> {
                accessibilityRuns = data.getBoolean("accessibility", false)
                data.getString("foreground")?.let { if (screenOn) onForegroundApp(it, fromEnforcer = true) }
                data.getStringArrayList("visible")?.let { visible(it) }
                checkAccessibility()
            }
            "visible" -> visible(data.getStringArrayList("packages") ?: arrayListOf())
            "reload" -> reload()
        }
    }

    // --- Android's events -------------------------------------------------------

    /**
     * An app installed, updated or removed: the monitor shares the list of
     * apps with the family's devices at once (a few seconds later, so an
     * update's removal and addition count as one).
     */
    private val packageReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.data?.schemeSpecificPart == packageName) return
            // An update removes then adds the same app: nothing new.
            if (intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)) return
            main.removeCallbacks(appsChanged)
            main.postDelayed(appsChanged, 10_000)
        }
    }

    private val appsChanged = Runnable { channel?.invokeMethod("appsChanged", null) }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_OFF -> setScreen(false)
                // The lock screen is not screen time: count from unlocking.
                Intent.ACTION_SCREEN_ON -> if (!keyguardLocked()) setScreen(true)
                Intent.ACTION_USER_PRESENT -> setScreen(true)
            }
        }
    }

    /** Polls usage statistics when the accessibility service is not running. */
    private val poller = object : Runnable {
        override fun run() {
            if (screenOn && !accessibilityRuns) {
                // Not known yet (the process just started, say): the app in
                // front may have come there long ago.
                val window = if (lastForeground == null) Shared.SINCE_UNLOCK_MS else 15_000L
                Shared.foregroundFromUsageStats(this@MonitorService, window)?.let { onForegroundApp(it) }
            }
            if (!bound) bind()
            checkAccessibility()
            main.postDelayed(this, POLL_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /** Since when the accessibility service is ticked but stopped (0: it runs). */
    private var stoppedSince = 0L
    private var stoppedShown = false

    /**
     * Tells, in a notification, when Android stopped the accessibility
     * service without unticking it (apps are then only seen from the usage
     * statistics, when allowed), and asks the main process to restart,
     * which brings the service back.
     */
    private fun checkAccessibility() {
        if (accessibilityRuns || !Health.accessibilityEnabled(this)) {
            stoppedSince = 0L
            if (stoppedShown) {
                Shared.notificationManager(this).cancel(Shared.STOPPED_ID)
                stoppedShown = false
            }
            return
        }
        val now = SystemClock.elapsedRealtime()
        if (stoppedSince == 0L) stoppedSince = now
        if (stoppedShown || now - stoppedSince < STOPPED_GRACE_MS) return
        Log.w(TAG, "Accessibility service ticked but stopped")
        val message = getString(R.string.stopped_message)
        val n = Shared.builder(this, Shared.WARNING_CHANNEL)
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setContentTitle(getString(R.string.stopped_title))
            .setContentText(message)
            .setStyle(Notification.BigTextStyle().bigText(message))
            .setContentIntent(Shared.openAppIntent(this))
            .setOngoing(true)
            .build()
        Shared.notificationManager(this).notify(Shared.STOPPED_ID, n)
        stoppedShown = true
        if (!toEnforcer(Bundle().apply { putString("cmd", "restart") })) {
            // No main process to restart: binding starts it.
            unbind()
            bind()
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "Monitor started")
        Health.logExitReasons(this)
        instance = this
        Shared.createChannels(this)
        goForeground(buildNotification(getString(R.string.monitor_starting), null, null))
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
        val packages = IntentFilter().apply {
            // Not ACTION_PACKAGE_CHANGED: some apps (Google Play services)
            // send it all the time.
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REMOVED)
            addDataScheme("package")
        }
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(packageReceiver, packages, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(packageReceiver, packages)
        }
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        screenOn = pm.isInteractive && !keyguardLocked()
        // Started again by Android (after it ran short of memory, say): the
        // app in front is the one the usage statistics last saw come there,
        // until the main process says.
        if (screenOn) {
            Shared.foregroundFromUsageStats(this, Shared.SINCE_UNLOCK_MS)?.let { lastForeground = it }
        }
        bind()
        startEngine()
        main.postDelayed(poller, POLL_MS)
        if (Health.monitorWanted(this)) Watchdog.schedule(this)
    }

    private fun goForeground(n: Notification) {
        notification = n
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(Shared.MONITOR_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(Shared.MONITOR_ID, n)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Started again while running (the watchdog, say): Android wants the
        // notification again.
        notification?.let { goForeground(it) }
        return START_STICKY
    }

    override fun onDestroy() {
        Log.w(TAG, "Monitor stopped")
        instance = null
        main.removeCallbacks(poller)
        main.removeCallbacks(appsChanged)
        unregisterReceiver(screenReceiver)
        unregisterReceiver(packageReceiver)
        unbind()
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

    /** From the main process, or this process's poller ([fromEnforcer] false). */
    private fun onForegroundApp(pkg: String, fromEnforcer: Boolean = false) {
        main.post {
            if (pkg == lastForeground) return@post
            lastForeground = pkg
            if (!fromEnforcer) toEnforcer(Bundle().apply {
                putString("cmd", "foreground")
                putString("package", pkg)
            })
            channel?.invokeMethod("foreground", mapOf("package" to pkg))
        }
    }

    /** The apps on screen, from the main process. */
    private fun visible(packages: List<String>) {
        main.post { channel?.invokeMethod("visible", mapOf("packages" to packages)) }
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
        if (on) {
            Shared.foregroundFromUsageStats(this, Shared.SINCE_UNLOCK_MS)?.let { onForegroundApp(it) }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Not on this device (a parent's): no monitor, no watchdog.
            "unwanted" -> {
                Health.setMonitorWanted(this, false)
                result.success(null)
                main.post { stopSelf() }
            }
            "state" -> result.success(
                mapOf("foreground" to lastForeground, "screenOn" to screenOn),
            )
            "countdown" -> {
                val n = buildNotification(
                    call.argument<String>("title") ?: "",
                    call.argument<String>("text"),
                    call.argument<Number>("endsAt")?.toLong(),
                )
                notification = n
                Shared.notificationManager(this).notify(Shared.MONITOR_ID, n)
                result.success(null)
            }
            "block", "unblock", "warn", "overlay", "overlayHide", "lockState",
            "volumeCap", "familyChanged" -> {
                forward(call.method, call.arguments as? Map<*, *>)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Ongoing notification; with [endsAt], Android shows a live countdown. */
    private fun buildNotification(title: String, text: String?, endsAt: Long?): Notification {
        val b = Shared.builder(this, Shared.MONITOR_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentIntent(Shared.openAppIntent(this))
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

    companion object {
        const val CHANNEL = "org.familyscreentime/monitor"
        private const val TAG = "FamilyScreenTime"
        private const val STOPPED_GRACE_MS = 60_000L
        private const val POLL_MS = 3_000L

        /** The monitor, in its own process only. */
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
                Log.w(TAG, "Monitor not started", e)
            }
        }
    }
}
