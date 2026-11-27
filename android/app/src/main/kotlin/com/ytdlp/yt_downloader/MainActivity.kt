package com.ytdlp.yt_downloader

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import android.webkit.MimeTypeMap
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Hosts the on-device yt-dlp engine (youtubedl-android) and the small amount of
 * Android glue the downloader needs: progress events, MediaStore copies into the
 * public Download folder, and opening/sharing/deleting the finished files.
 */
class MainActivity : FlutterActivity() {

    private val worker = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var progressSink: EventChannel.EventSink? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    @Volatile
    private var initialized = false

    @Volatile
    private var updating = false

    @Volatile
    private var lastUpdateStatus: String = "not-attempted"

    @Volatile
    private var pendingCookiesResult: MethodChannel.Result? = null

    @Volatile
    private var pendingDownloadResult: MethodChannel.Result? = null

    @Volatile
    private var pendingDownloadTaskId: String? = null

    private val cookiesFile by lazy { File(filesDir, "cookies.txt") }

    private val prefs by lazy { getSharedPreferences("tubegrab_engine", MODE_PRIVATE) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "tubegrab/progress")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    progressSink = events
                }

                override fun onCancel(arguments: Any?) {
                    progressSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tubegrab/engine")
            .setMethodCallHandler { call, result -> dispatch(call, result) }
    }

    private fun dispatch(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> runAsync(result) {
                ensureInitialized()
                engineInfo()
            }

            "engineInfo" -> runAsync(result) { engineInfo() }

            "updateEngine" -> runAsync(result) {
                ensureInitialized()
                updateEngine(force = true)
                engineInfo()
            }

            "workDir" -> runAsync(result) { workDir().absolutePath }

            "analyze" -> {
                val url = call.argument<String>("url")
                    ?: return result.error("BAD_ARGS", "url wajib diisi", null)
                runAsync(result) {
                    ensureInitialized()
                    // Prefer a freshly updated engine when one is being fetched.
                    val deadline = System.currentTimeMillis() + 8_000
                    while (updating && System.currentTimeMillis() < deadline) {
                        Thread.sleep(200)
                    }
                    val request = YoutubeDLRequest(url).apply {
                        addOption("--dump-single-json")
                        addOption("--no-playlist")
                        addOption("--no-warnings")
                        addOption("--no-check-formats")
                        addOption("--no-colors")
                        addOption("--socket-timeout", "20")
                        // The Android client only exposes ~360p without a PO token, while the
                        // TV client returns full HD/4K streams without one.
                        addOption("--extractor-args", "youtube:player_client=tv")
                        if (cookiesFile.exists()) {
                            addOption("--cookies", cookiesFile.absolutePath)
                        }
                    }
                    YoutubeDL.getInstance().execute(request).out.trim()
                }
            }

            "download" -> {
                val url = call.argument<String>("url")
                    ?: return result.error("BAD_ARGS", "url wajib diisi", null)
                val taskId = call.argument<String>("taskId")
                    ?: return result.error("BAD_ARGS", "taskId wajib diisi", null)
                val mediaArgs = call.argument<List<String>>("args") ?: emptyList()
                val template = call.argument<String>("template")
                    ?: "%(title).100B [%(id)s].%(ext)s"

                // Wire the service callbacks to this (single) download.
                DownloadService.onProgress = { tId, progress, eta, line ->
                    if (tId == taskId) {
                        mainHandler.post {
                            progressSink?.success(
                                mapOf(
                                    "taskId" to tId,
                                    "progress" to progress,
                                    "eta" to eta,
                                    "line" to line,
                                )
                            )
                        }
                    }
                }
                DownloadService.onComplete = { tId, path ->
                    if (tId == taskId) {
                        mainHandler.post {
                            pendingDownloadResult?.success(path)
                            pendingDownloadResult = null
                            pendingDownloadTaskId = null
                        }
                    }
                }
                DownloadService.onError = { tId, e ->
                    if (tId == taskId) {
                        mainHandler.post {
                            pendingDownloadResult?.error("ENGINE_ERROR", cleanMessage(e), null)
                            pendingDownloadResult = null
                            pendingDownloadTaskId = null
                        }
                    }
                }

                pendingDownloadResult = result
                pendingDownloadTaskId = taskId

                worker.execute {
                    try {
                        ensureInitialized()
                        val deadline = System.currentTimeMillis() + 15_000
                        while (updating && System.currentTimeMillis() < deadline) {
                            Thread.sleep(200)
                        }
                        val intent = Intent(this@MainActivity, DownloadService::class.java).apply {
                            action = DownloadService.ACTION_START
                            putExtra(DownloadService.EXTRA_URL, url)
                            putStringArrayListExtra(DownloadService.EXTRA_ARGS, ArrayList(mediaArgs))
                            putExtra(DownloadService.EXTRA_TASK_ID, taskId)
                            putExtra(DownloadService.EXTRA_TEMPLATE, template)
                        }
                        androidx.core.content.ContextCompat.startForegroundService(this@MainActivity, intent)
                    } catch (e: Throwable) {
                        mainHandler.post {
                            pendingDownloadResult?.error("ENGINE_ERROR", cleanMessage(e), null)
                            pendingDownloadResult = null
                            pendingDownloadTaskId = null
                        }
                    }
                }
            }

            "cancel" -> {
                val taskId = call.argument<String>("taskId")
                    ?: return result.error("BAD_ARGS", "taskId wajib diisi", null)
                try {
                    YoutubeDL.getInstance().destroyProcessById(taskId)
                } catch (_: Throwable) {}
                val intent = Intent(this@MainActivity, DownloadService::class.java).apply {
                    action = DownloadService.ACTION_CANCEL
                    putExtra(DownloadService.EXTRA_TASK_ID, taskId)
                }
                startService(intent)
                result.success(true)
            }

            "fileSize" -> {
                val path = call.argument<String>("path") ?: ""
                result.success(if (path.isEmpty()) 0 else File(path).length())
            }

            "saveToDownloads" -> {
                val path = call.argument<String>("path")
                    ?: return result.error("BAD_ARGS", "path wajib diisi", null)
                val mime = call.argument<String>("mime") ?: guessMime(path)
                val name = call.argument<String>("name") ?: File(path).name
                if (needsLegacyStoragePermission()) {
                    return result.error("PERMISSION_REQUIRED", "Izin penyimpanan diperlukan", null)
                }
                runAsync(result) { saveToDownloads(path, mime, name) }
            }

            "requestStoragePermission" -> requestStoragePermission(result)

            "openFile" -> {
                val locator = call.argument<String>("locator")
                    ?: return result.error("BAD_ARGS", "locator wajib diisi", null)
                val mime = call.argument<String>("mime") ?: guessMime(locator)
                openOrShare(Intent.ACTION_VIEW, locator, mime, result)
            }

            "shareFile" -> {
                val locator = call.argument<String>("locator")
                    ?: return result.error("BAD_ARGS", "locator wajib diisi", null)
                val mime = call.argument<String>("mime") ?: guessMime(locator)
                openOrShare(Intent.ACTION_SEND, locator, mime, result)
            }

            "deleteFile" -> {
                val locator = call.argument<String>("locator")
                    ?: return result.error("BAD_ARGS", "locator wajib diisi", null)
                runAsync(result) { deleteLocator(locator) }
            }

            "cookiesStatus" -> runAsync(result) { cookiesStatus() }

            "saveCookies" -> {
                val content = call.argument<String>("content")
                    ?: return result.error("BAD_ARGS", "content wajib diisi", null)
                runAsync(result) { saveCookies(content) }
            }

            "clearCookies" -> runAsync(result) { clearCookies() }

            "pickCookiesFile" -> pickCookiesFile(result)

            else -> result.notImplemented()
        }
    }

    // ---------------------------------------------------------------- engine

    @Synchronized
    private fun ensureInitialized() {
        if (initialized) return
        YoutubeDL.getInstance().init(applicationContext)
        FFmpeg.getInstance().init(applicationContext)
        // Mark ready immediately so analysis/downloads are not blocked by the
        // optional network update of yt-dlp. The update runs in the background.
        initialized = true
        scheduleEngineUpdate()
    }

    private fun scheduleEngineUpdate() {
        val lastRun = prefs.getLong("last_update", 0L)
        if (System.currentTimeMillis() - lastRun <= UPDATE_INTERVAL_MS) return
        if (updating) return
        updating = true
        worker.execute {
            try {
                prefs.edit().putLong("last_update", System.currentTimeMillis()).apply()
                updateEngine(force = false)
            } catch (e: Throwable) {
                lastUpdateStatus = "gagal: ${e.message}"
            } finally {
                updating = false
            }
        }
    }

    private fun updateEngine(force: Boolean): String {
        return try {
            val status = YoutubeDL.getInstance()
                .updateYoutubeDL(applicationContext, YoutubeDL.UpdateChannel.STABLE)
            lastUpdateStatus = status?.name ?: "siap"
            prefs.edit().putLong("last_update", System.currentTimeMillis()).apply()
            lastUpdateStatus
        } catch (e: Throwable) {
            lastUpdateStatus = "gagal: ${e.message}"
            if (force) throw RuntimeException("Pembaruan mesin gagal: ${e.message}")
            lastUpdateStatus
        }
    }

    private fun engineInfo(): Map<String, Any?> {
        val version = runCatching { YoutubeDL.getInstance().version(applicationContext) }.getOrNull()
        return mapOf(
            "version" to (version ?: "bundled"),
            "update" to lastUpdateStatus,
            "ready" to true,
        )
    }

    private fun workDir(): File {
        val base = getExternalFilesDir(null) ?: filesDir
        return File(base, "media").apply { mkdirs() }
    }

    private fun download(
        url: String,
        mediaArgs: List<String>,
        taskId: String,
        template: String,
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
            // Fail fast on a dead connection instead of hanging at 0%.
            addOption("--socket-timeout", "20")
            addOption("--retries", "5")
            addOption("--fragment-retries", "10")
            // YouTube serves video in fragments; parallel fetches are much faster.
            addOption("--concurrent-fragments", "4")
            // The TV client returns full HD/4K streams without a PO token and is
            // less likely to be answered with HTTP 403 than the default web client.
            addOption("--extractor-args", "youtube:player_client=tv")
            if (cookiesFile.exists()) {
                addOption("--cookies", cookiesFile.absolutePath)
            }
            mediaArgs.forEach { addOption(it) }
            addOption("-o", "${dir.absolutePath}/$template")
            addOption("--no-simulate")
        }

        val response = YoutubeDL.getInstance().execute(request, taskId) { progress, eta, line ->
            mainHandler.post {
                progressSink?.success(
                    mapOf(
                        "taskId" to taskId,
                        "progress" to progress,
                        "eta" to eta,
                        "line" to line.takeLast(160),
                    )
                )
            }
        }

        // yt-dlp writes the final file into our own directory, so the newest new
        // file is the result. (Using --print to ask for the path would switch
        // yt-dlp into quiet mode and hide the progress lines the UI streams.)
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

    // --------------------------------------------------------------- storage

    private fun needsLegacyStoragePermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.WRITE_EXTERNAL_STORAGE,
            ) != PackageManager.PERMISSION_GRANTED

    private fun requestStoragePermission(result: MethodChannel.Result) {
        if (!needsLegacyStoragePermission()) {
            result.success(true)
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            STORAGE_PERMISSION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != STORAGE_PERMISSION_REQUEST) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    private fun saveToDownloads(sourcePath: String, mime: String, displayName: String): String {
        val source = File(sourcePath)
        if (!source.exists()) throw RuntimeException("Berkas hasil unduhan hilang")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, displayName)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(
                    MediaStore.Downloads.RELATIVE_PATH,
                    Environment.DIRECTORY_DOWNLOADS + File.separator + FOLDER_NAME,
                )
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw RuntimeException("Tidak bisa membuat berkas di folder Download")
            try {
                resolver.openOutputStream(uri)?.use { out ->
                    source.inputStream().use { input -> input.copyTo(out) }
                } ?: throw RuntimeException("Tidak bisa menulis ke folder Download")
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            } catch (e: Exception) {
                runCatching { resolver.delete(uri, null, null) }
                throw e
            }
            source.delete()
            return uri.toString()
        }

        val publicDir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            FOLDER_NAME,
        ).apply { mkdirs() }
        val target = uniqueFile(publicDir, displayName)
        source.copyTo(target, overwrite = true)
        source.delete()
        MediaScannerConnection.scanFile(this, arrayOf(target.absolutePath), arrayOf(mime), null)
        return target.absolutePath
    }

    private fun uniqueFile(dir: File, name: String): File {
        var candidate = File(dir, name)
        if (!candidate.exists()) return candidate
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var index = 1
        while (candidate.exists()) {
            candidate = File(dir, "$base ($index)$ext")
            index++
        }
        return candidate
    }

    private fun openOrShare(action: String, locator: String, mime: String, result: MethodChannel.Result) {
        try {
            val uri: Uri = if (locator.startsWith("content://")) {
                Uri.parse(locator)
            } else {
                FileProvider.getUriForFile(
                    this,
                    "$packageName.fileprovider",
                    File(locator),
                )
            }
            val intent = if (action == Intent.ACTION_VIEW) {
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, mime)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            } else {
                Intent(Intent.ACTION_SEND).apply {
                    type = mime
                    putExtra(Intent.EXTRA_STREAM, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            }
            startActivity(Intent.createChooser(intent, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            result.success(true)
        } catch (e: ActivityNotFoundException) {
            result.error("NO_APP", "Tidak ada aplikasi untuk membuka berkas ini", null)
        } catch (e: Exception) {
            result.error("OPEN_FAILED", e.message, null)
        }
    }

    private fun deleteLocator(locator: String): Boolean {
        return try {
            if (locator.startsWith("content://")) {
                contentResolver.delete(Uri.parse(locator), null, null) > 0
            } else {
                File(locator).delete()
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun guessMime(path: String): String {
        val ext = path.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
            ?: if (ext in listOf("mkv", "webm")) "video/*" else "*/*"
    }

    private fun cookiesStatus(): Map<String, Any?> {
        val file = cookiesFile
        return mapOf(
            "exists" to file.exists(),
            "path" to file.absolutePath,
            "size" to if (file.exists()) file.length() else 0L,
        )
    }

    private fun saveCookies(content: String): String {
        cookiesFile.writeText(content)
        return cookiesFile.absolutePath
    }

    private fun clearCookies(): Boolean = cookiesFile.delete()

    private fun pickCookiesFile(result: MethodChannel.Result) {
        mainHandler.post {
            if (pendingCookiesResult != null) {
                result.error("BUSY", "Pemilih berkas sedang berjalan", null)
                return@post
            }
            pendingCookiesResult = result
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
            }
            startActivityForResult(intent, COOKIES_PICK_REQUEST)
        }
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != COOKIES_PICK_REQUEST) return
        val result = pendingCookiesResult
        pendingCookiesResult = null
        if (result == null) return
        if (resultCode != RESULT_OK || data?.data == null) {
            mainHandler.post { result.success(null) }
            return
        }
        try {
            contentResolver.openInputStream(data.data!!)?.use { input ->
                cookiesFile.outputStream().use { output -> input.copyTo(output) }
            } ?: throw RuntimeException("Berkas tidak bisa dibaca")
            mainHandler.post { result.success(cookiesFile.absolutePath) }
        } catch (e: Exception) {
            Log.e(TAG, "gagal mengimpor cookies", e)
            mainHandler.post { result.error("IMPORT_FAILED", e.message, null) }
        }
    }

    private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
        worker.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: YoutubeDL.CanceledException) {
                mainHandler.post { result.error("CANCELLED", "Unduhan dibatalkan", null) }
            } catch (e: Throwable) {
                Log.e(TAG, "engine call failed", e)
                mainHandler.post {
                    result.error("ENGINE_ERROR", cleanMessage(e), null)
                }
            }
        }
    }

    private fun cleanMessage(e: Throwable): String {
        val chain = generateSequence(e) { it.cause }
            .take(3)
            .joinToString("\n") { "${it.javaClass.simpleName}: ${it.message.orEmpty()}" }
        return chain
            .lineSequence()
            .filter { it.isNotBlank() }
            .toList()
            .takeLast(6)
            .joinToString("\n")
            .ifBlank { "Terjadi kesalahan pada mesin unduhan" }
    }

    override fun onDestroy() {
        worker.shutdownNow()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "TubeGrab"
        private const val FOLDER_NAME = "TubeGrab"
        private const val STORAGE_PERMISSION_REQUEST = 4711
        private const val UPDATE_INTERVAL_MS = 12 * 60 * 60 * 1000L
        private const val COOKIES_PICK_REQUEST = 9001
    }
}
