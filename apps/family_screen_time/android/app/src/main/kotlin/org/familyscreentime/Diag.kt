package org.familyscreentime

import android.app.Application
import android.content.Context
import android.os.Build
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The diagnostic log: what the app saw and did (screen on or off, the app
 * in front, the accessibility service, blocks, errors), kept on the device
 * in a file per process and shared only by the parent, from parent mode.
 * Also in Android's log, under the "FamilyScreenTime" tag.
 *
 * Each file is kept under [MAX_BYTES]: the older half goes to `.1`.
 */
object Diag {
    private const val TAG = "FamilyScreenTime"
    private const val MAX_BYTES = 512 * 1024L

    @Volatile
    private var dir: File? = null
    private var process = "main"
    private val time = SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.ROOT)

    /** Where the files go; called by each process's first component. */
    fun init(context: Context) {
        if (dir != null) return
        synchronized(this) {
            if (dir != null) return
            process = processSuffix(context)
            dir = File(context.filesDir, "diagnostics").apply { mkdirs() }
        }
    }

    fun i(message: String) {
        Diag.i(message)
        append("I", message)
    }

    fun w(message: String, e: Throwable? = null) {
        Diag.w(message, e)
        append("W", if (e == null) message else "$message: $e")
    }

    @Synchronized
    private fun append(level: String, message: String) {
        val d = dir ?: return
        try {
            val file = File(d, "$process.log")
            if (file.length() > MAX_BYTES) {
                val old = File(d, "$process.log.1")
                old.delete()
                file.renameTo(old)
            }
            file.appendText("${time.format(Date())} $level $message\n")
        } catch (e: Exception) {
            // Android's log still has it.
        }
    }

    /** The files of every process, oldest first. */
    fun files(context: Context): List<File> {
        val d = File(context.filesDir, "diagnostics")
        return listOf("main", "monitor").flatMap { p ->
            listOf(File(d, "$p.log.1"), File(d, "$p.log"))
        }.filter { it.exists() }
    }

    /** "main" or "monitor", from the process name ("…:monitor"). */
    private fun processSuffix(context: Context): String {
        val name = if (Build.VERSION.SDK_INT >= 28) {
            Application.getProcessName()
        } else {
            try {
                File("/proc/self/cmdline").readText().trim('\u0000', ' ')
            } catch (e: Exception) {
                context.packageName
            }
        }
        return if (name.endsWith(":monitor")) "monitor" else "main"
    }
}
