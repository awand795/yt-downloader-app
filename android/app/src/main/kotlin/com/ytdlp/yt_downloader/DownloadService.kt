package com.ytdlp.yt_downloader

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import java.io.File
import java.util.Locale
import java.util.concurrent.Executors
import kotlin.math.pow

/**
 * Runs a single yt-dlp download in the foreground so Android does not kill the
 * process when the app is backgrounded or the screen turns off.
 */
class DownloadService : Service() {

    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        const val ACTION_START = "com.ytdlp.yt_downloader.DOWNLOAD_START"
        const val ACTION_CANCEL = "com.ytdlp.yt_downloader.DOWNLOAD_CANCEL"

        const val EXTRA_URL = "url"
        const val EXTRA_ARGS = "args"
        const val EXTRA_TASK_ID = "taskId"
        const val EXTRA_TEMPLATE = "template"

        const val NOTIF_ID = 4242
        const val CHANNEL_ID = "tubegrab_download"

        private val PROGRESS_LINE = Regex(
            """\[download\]\s+([\d.]+)%\s+of\s+~?\s*([\d.]+)\s*([KMGT]?i?B)(?:\s+at\s+([\d.]+)\s*([KMGT]?i?B)/s)?"""
        )

        // Callbacks into MainActivity (same process) for progress/result.
        @Volatile var onProgress: ((taskId: String, progress: Float, eta: Int, line: String) -> Unit)? = null
        @Volatile var onComplete: ((taskId: String, path: String) -> Unit)? = null
        @Volatile var onError: ((taskId: String, error: Throwable) -> Unit)? = null
        @Volatile var currentTaskId: String? = null
    }

    private var currentTaskIdLocal: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CANCEL -> {
                val id = intent.getStringExtra(EXTRA_TASK_ID) ?: currentTaskIdLocal
                if (id != null) {
                    try { YoutubeDL.getInstance().destroyProcessById(id) } catch (_: Throwable) {}
                }
                stopForegroundCompat()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                val url = intent.getStringExtra(EXTRA_URL) ?: return START_NOT_STICKY
                val args = intent.getStringArrayListExtra(EXTRA_ARGS) ?: arrayListOf()
                val taskId = intent.getStringExtra(EXTRA_TASK_ID) ?: return START_NOT_STICKY
                val template = intent.getStringExtra(EXTRA_TEMPLATE)
                    ?: "%(title).100B [%(id)s].%(ext)s"

                currentTaskIdLocal = taskId
                currentTaskId = taskId

                val notification = buildNotification(taskId, 0, "Menyiapkan…")
                startForeground(NOTIF_ID, notification)

                worker.execute {
                    try {
                        ensureInitialized()
                        val path = runDownload(url, args, taskId, template) { progress, eta, line ->
                            mainHandler.post {
                                updateNotification(taskId, progress.toInt(), progressText(line))
                                onProgress?.invoke(taskId, progress, eta, line)
                            }
                        }
                        mainHandler.post {
                            onComplete?.invoke(taskId, path)
                            stopForegroundCompat()
                            stopSelf()
                        }
                    } catch (e: Throwable) {
                        mainHandler.post {
                            onError?.invoke(taskId, e)
                            stopForegroundCompat()
                            stopSelf()
                        }
                    }
                }
            }
        }
        return START_NOT_STICKY
    }

    private fun ensureInitialized() {
        YoutubeDL.getInstance().init(applicationContext)
        FFmpeg.getInstance().init(applicationContext)
        runCatching { YtDlpUpdater.ensureBundled(applicationContext) }
    }

    private fun workDir(): File {
        val base = getExternalFilesDir(null) ?: filesDir
        return File(base, "media").apply { mkdirs() }
    }

    private fun cookiesFile(): File = File(filesDir, "cookies.txt")

    private fun runDownload(
        url: String,
        mediaArgs: List<String>,
        taskId: String,
        template: String,
        onProgress: (Float, Int, String) -> Unit,
    ): String {
        val dir = workDir()
        val existing = dir.listFiles()?.map { it.absolutePath }?.toHashSet() ?: emptySet<String>()
        val startedAt = System.currentTimeMillis()
        val request = YoutubeDLRequest(url).apply {
            addOption("--no-playlist")
            addOption("--no-mtime")
            addOption("--no-warnings")
            addOption("--no-colors")
            addOption("--newline")
            addOption("--windows-filenames")
            addOption("--socket-timeout", "20")
            addOption("--retries", "10")
            addOption("--fragment-retries", "15")
            // YouTube serves video in fragments; fetching several at once is the
            // main throughput lever on a fast connection.
            addOption("--concurrent-fragments", "8")
            // YouTube throttles each long request; smaller ranged chunks keep
            // the connection fast (measured ~20x on the same network).
            addOption("--http-chunk-size", "1M")
            if (cookiesFile().exists()) {
                addOption("--cookies", cookiesFile().absolutePath)
            }
            mediaArgs.forEach { addOption(it) }
            addOption("-o", "${dir.absolutePath}/$template")
            addOption("--no-simulate")
        }

        val response = YoutubeDL.getInstance().execute(request, taskId) { progress, eta, line ->
            onProgress(progress, eta.toInt(), line.takeLast(160))
        }

        val files = dir.listFiles()
            ?.filter { it.isFile && !it.name.endsWith(".part") }
            ?: emptyList()
        val produced = files
            .filter { it.absolutePath !in existing }
            .maxByOrNull { it.lastModified() }
            ?: files
                .filter { it.lastModified() >= startedAt - 2_000 }
                .maxByOrNull { it.lastModified() }
            ?: throw RuntimeException(
                "Unduhan selesai tetapi berkas tidak ditemukan (${response.out.takeLast(300)})"
            )
        return produced.absolutePath
    }

    /** "45% · 2,1 MB/s · 820 MB / 1,8 GB" from a yt-dlp download line. */
    private fun progressText(line: String): String {
        val match = PROGRESS_LINE.find(line) ?: return line.ifBlank { "Mengunduh…" }.take(80)
        val percent = match.groupValues[1].toDoubleOrNull() ?: return line.take(80)
        val totalValue = match.groupValues[2].toDoubleOrNull() ?: 0.0
        val unit = match.groupValues[3]
        val totalBytes = bytesOf(totalValue, unit)
        val speed = match.groupValues.getOrNull(4)?.toDoubleOrNull()?.let {
            humanBytes(bytesOf(it, match.groupValues[5])) + "/s"
        }
        return buildString {
            append(percent.toInt()).append('%')
            if (speed != null) append(" · ").append(speed)
            append(" · ")
                .append(humanBytes(totalBytes * percent / 100))
                .append(" / ")
                .append(humanBytes(totalBytes))
        }
    }

    private fun bytesOf(value: Double, unit: String): Double {
        val base = if (unit.contains('i')) 1024.0 else 1000.0
        val power = when (unit.firstOrNull()) {
            'K' -> 1
            'M' -> 2
            'G' -> 3
            'T' -> 4
            else -> 0
        }
        return value * base.pow(power)
    }

    private fun humanBytes(bytes: Double): String {
        val units = arrayOf("B", "KB", "MB", "GB", "TB")
        var value = bytes
        var index = 0
        while (value >= 1024 && index < units.lastIndex) {
            value /= 1024
            index++
        }
        val rendered = if (index == 0 || value >= 100) {
            String.format(Locale.US, "%.0f", value)
        } else {
            String.format(Locale.US, "%.1f", value)
        }
        return "$rendered ${units[index]}".replace('.', ',')
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Unduhan TubeGrab",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "Progres unduhan video" }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    private fun buildNotification(taskId: String, progress: Int, text: String): Notification {
        val cancelIntent = Intent(this, DownloadService::class.java).apply {
            action = ACTION_CANCEL
            putExtra(EXTRA_TASK_ID, taskId)
        }
        val cancelPending = PendingIntent.getService(
            this, 0, cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("TubeGrab")
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, progress.coerceIn(0, 100), progress <= 0)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Batal", cancelPending)
            .build()
    }

    private fun updateNotification(taskId: String, progress: Int, text: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID, buildNotification(taskId, progress, text))
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    override fun onDestroy() {
        worker.shutdownNow()
        super.onDestroy()
    }
}