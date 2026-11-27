package com.ytdlp.yt_downloader

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/**
 * Downloads the latest yt-dlp release and installs it where youtubedl-android
 * looks for the binary.
 *
 * The library's own updater uses a 10 s read timeout for a ~3 MB file and talks
 * to the rate-limited GitHub API, which fails on many mobile connections. This
 * version uses longer timeouts, retries, and falls back to the direct release
 * download URL.
 */
object YtDlpUpdater {
    private const val TAG = "YtDlpUpdater"
    private const val RELEASE_API = "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"
    private const val DIRECT_URL = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp"
    private const val BIN_NAME = "yt-dlp"
    private const val MIN_BYTES = 1_000_000L

    @Synchronized
    @Throws(IOException::class)
    fun update(context: Context): String {
        val (url, version) = resolveLatest()
        Log.i(TAG, "downloading yt-dlp $version from $url")
        val downloaded = download(context, url)
        try {
            install(context, downloaded)
        } finally {
            downloaded.delete()
        }
        // Same store youtubedl-android reads version() from.
        context.getSharedPreferences("youtubedl-android", Context.MODE_PRIVATE)
            .edit()
            .putString("dlpVersion", version)
            .putString("dlpVersionName", "yt-dlp $version")
            .apply()
        Log.i(TAG, "installed yt-dlp $version")
        return version
    }

    private fun resolveLatest(): Pair<String, String> {
        try {
            val conn = (URL(RELEASE_API).openConnection() as HttpURLConnection).apply {
                connectTimeout = 15_000
                readTimeout = 20_000
                setRequestProperty("User-Agent", "TubeGrab")
                setRequestProperty("Accept", "application/vnd.github+json")
            }
            try {
                if (conn.responseCode in 200..299) {
                    val body = conn.inputStream.bufferedReader().use { it.readText() }
                    val json = JSONObject(body)
                    val tag = json.optString("tag_name").ifBlank { "terbaru" }
                    val assets = json.optJSONArray("assets")
                    if (assets != null) {
                        for (i in 0 until assets.length()) {
                            val asset = assets.optJSONObject(i) ?: continue
                            if (asset.optString("name") == BIN_NAME) {
                                val url = asset.optString("browser_download_url")
                                if (url.isNotBlank()) return url to tag
                            }
                        }
                    }
                }
            } finally {
                conn.disconnect()
            }
        } catch (e: Throwable) {
            Log.w(TAG, "release lookup failed, using direct URL", e)
        }
        return DIRECT_URL to "terbaru"
    }

    private fun download(context: Context, url: String): File {
        var lastError: Throwable? = null
        repeat(3) { attempt ->
            val file = File.createTempFile("yt-dlp", ".tmp", context.cacheDir)
            try {
                val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                    instanceFollowRedirects = true
                    connectTimeout = 30_000
                    readTimeout = 120_000
                    setRequestProperty("User-Agent", "TubeGrab")
                }
                try {
                    if (conn.responseCode !in 200..299) {
                        throw IOException("HTTP ${conn.responseCode}")
                    }
                    conn.inputStream.use { input ->
                        file.outputStream().use { output -> input.copyTo(output) }
                    }
                } finally {
                    conn.disconnect()
                }
                if (file.length() < MIN_BYTES) {
                    throw IOException("ukuran mesin tidak wajar (${file.length()} B)")
                }
                return file
            } catch (e: Throwable) {
                lastError = e
                file.delete()
                if (attempt < 2) Thread.sleep(1_500L * (attempt + 1))
            }
        }
        throw IOException("gagal mengunduh mesin yt-dlp", lastError)
    }

    private fun install(context: Context, downloaded: File) {
        val dir = File(File(context.noBackupFilesDir, "youtubedl-android"), "yt-dlp")
        if (!dir.exists() && !dir.mkdirs()) throw IOException("folder mesin tidak bisa dibuat")
        val target = File(dir, BIN_NAME)
        val temp = File(dir, "$BIN_NAME.new")
        downloaded.inputStream().use { input ->
            temp.outputStream().use { output -> input.copyTo(output) }
        }
        if (target.exists() && !target.delete()) throw IOException("mesin lama tidak bisa diganti")
        if (!temp.renameTo(target)) {
            temp.copyTo(target, overwrite = true)
            temp.delete()
        }
    }
}