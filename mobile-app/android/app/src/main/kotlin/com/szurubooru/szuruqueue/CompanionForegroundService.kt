package com.szurubooru.szuruqueue

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.view.View
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.Collections
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Single foreground service for SzuruCompanion: one persistent notification and optional
 * floating bubble. Replaces separate StatusForegroundService and FloatingBubbleService.
 * Use startCompanionForegroundService / updateCompanionNotification / stopCompanionForegroundService
 * via method channel.
 */
class CompanionForegroundService : Service() {

    private var windowManager: WindowManager? = null
    private var bubbleView: View? = null
    private var isForeground = false
    private var lastShowBubble = false
    private var sseThread: Thread? = null
    private val stopSse = AtomicBoolean(false)
    private val notifiedFailedJobs =
        Collections.synchronizedSet(mutableSetOf<String>())

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val updateBodyOnly = intent?.getBooleanExtra(EXTRA_UPDATE_BODY_ONLY, false) == true
        val body = intent?.getStringExtra(EXTRA_BODY) ?: "SzuruCompanion active"

        if (updateBodyOnly) {
            val notification = buildNotification(body)
            if (isForeground) {
                getSystemService(NotificationManager::class.java)?.notify(NOTIFICATION_ID, notification)
            } else {
                startForeground(NOTIFICATION_ID, notification)
                isForeground = true
            }
            return START_STICKY
        }

        val showBubble = intent?.getBooleanExtra(EXTRA_SHOW_BUBBLE, false) ?: false
        lastShowBubble = showBubble

        if (showBubble && bubbleView == null) {
            showBubbleOverlay()
        } else if (!showBubble && bubbleView != null) {
            removeBubbleOverlay()
        }

        val notification = buildNotification(body)
        if (isForeground) {
            getSystemService(NotificationManager::class.java)?.notify(NOTIFICATION_ID, notification)
        } else {
            startForeground(NOTIFICATION_ID, notification)
            isForeground = true
        }

        // Ensure native SSE listener is running so job failure notifications
        // work even when the main Flutter UI has been swiped away.
        startSseListenerIfNeeded()
        return START_STICKY
    }

    override fun onDestroy() {
        removeBubbleOverlay()
        stopSse.set(true)
        sseThread?.interrupt()
        sseThread = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // -- Notification ---------------------------------------------------------
    // Persistent notification uses a dedicated channel so other notifications
    // (errors, success, folder sync) do not pool under it.

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Companion status",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Connection and folder sync status"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(body: String): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_SINGLE_TOP },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SzuruCompanion")
            .setContentText(body)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setGroup(COMPANION_GROUP_KEY)
            .setGroupSummary(false)
            .build()
    }

    // -- Bubble overlay (BubbleOverlayHelper) ---------------------------------

    private fun showBubbleOverlay() {
        if (bubbleView != null) return

        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        windowManager = wm
        val (bubble, params) = BubbleOverlayHelper.createBubbleView(this, wm) {
            startActivity(Intent(this, ClipboardReaderActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
        }
        wm.addView(bubble, params)
        BubbleOverlayHelper.runEntryAnimation(bubble)
        bubbleView = bubble
    }

    private fun removeBubbleOverlay() {
        bubbleView?.let {
            try {
                windowManager?.removeView(it)
            } catch (e: Exception) {
                Log.w(TAG, "Error removing bubble view", e)
            }
        }
        bubbleView = null
    }

    // -- Native SSE listener for job failures ---------------------------------

    private fun startSseListenerIfNeeded() {
        if (sseThread != null && sseThread?.isAlive == true) return

        stopSse.set(false)
        sseThread = Thread {
            sseLoop()
        }.apply {
            name = "CCC-JobSseListener"
            isDaemon = true
            start()
        }
    }

    private fun sseLoop() {
        while (!stopSse.get()) {
            try {
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val backendUrl = prefs.getString("flutter.backendUrl", "") ?: ""
                val authJson = prefs.getString("flutter.auth_tokens", null)
                val username = prefs.getString("flutter.username", null)

                if (backendUrl.isBlank() || authJson.isNullOrBlank() || username.isNullOrBlank()) {
                    Thread.sleep(10_000)
                    continue
                }

                val token = try {
                    JSONObject(authJson).optString("access_token", "")
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to parse auth_tokens JSON", e)
                    ""
                }
                if (token.isBlank()) {
                    Thread.sleep(10_000)
                    continue
                }

                val sseUrl = (if (backendUrl.endsWith("/")) backendUrl.dropLast(1) else backendUrl) + "/api/events"
                val url = URL(sseUrl)
                val conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    setRequestProperty("Accept", "text/event-stream")
                    setRequestProperty("Cache-Control", "no-cache")
                    setRequestProperty("Connection", "keep-alive")
                    setRequestProperty("Authorization", "Bearer $token")
                    connectTimeout = 10_000
                    readTimeout = 60_000
                }

                try {
                    conn.connect()
                    if (conn.responseCode != HttpURLConnection.HTTP_OK) {
                        Log.w(TAG, "SSE connection failed: ${conn.responseCode}")
                        conn.disconnect()
                        Thread.sleep(5_000)
                        continue
                    }

                    val reader = BufferedReader(InputStreamReader(conn.inputStream))
                    var line: String? = null
                    var dataBuffer = StringBuilder()
                    while (!stopSse.get() && reader.readLine().also { line = it } != null) {
                        val l = line ?: break
                        // Ignore comments and heartbeat lines (starting with ':')
                        if (l.startsWith(":")) continue

                        if (l.startsWith("data:")) {
                            dataBuffer.append(l.substring(5).trim()).append('\n')
                        } else if (l.isBlank()) {
                            val payload = dataBuffer.toString().trim()
                            dataBuffer = StringBuilder()
                            if (payload.isNotEmpty()) {
                                handleSseData(payload, backendUrl, token, username)
                            }
                        }
                    }
                    reader.close()
                } finally {
                    conn.disconnect()
                }
            } catch (e: InterruptedException) {
                // Thread interrupted during sleep or read; exit if stopping
                if (stopSse.get()) return
            } catch (e: Exception) {
                Log.w(TAG, "Error in SSE loop", e)
            }

            try {
                Thread.sleep(3_000)
            } catch (e: InterruptedException) {
                if (stopSse.get()) return
            }
        }
    }

    private fun handleSseData(
        payload: String,
        backendUrl: String,
        token: String,
        currentUsername: String
    ) {
        try {
            val json = JSONObject(payload)
            val status = json.optString("status", "").lowercase(Locale.ROOT)
            val jobId = json.optString("job_id", "")
            if (status != "failed" || jobId.isBlank()) return

            synchronized(notifiedFailedJobs) {
                if (notifiedFailedJobs.contains(jobId)) {
                    return
                }
            }

            val base = if (backendUrl.endsWith("/")) backendUrl.dropLast(1) else backendUrl
            val jobUrl = URL("$base/api/jobs/$jobId")
            val conn = (jobUrl.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                setRequestProperty("Accept", "application/json")
                setRequestProperty("Authorization", "Bearer $token")
                connectTimeout = 10_000
                readTimeout = 10_000
            }

            val body = try {
                conn.connect()
                if (conn.responseCode != HttpURLConnection.HTTP_OK) {
                    // Not visible or not found; treat as not for this user
                    return
                }
                conn.inputStream.bufferedReader().use { it.readText() }
            } finally {
                conn.disconnect()
            }

            val job = JSONObject(body)
            val jobStatus = job.optString("status", "").lowercase(Locale.ROOT)
            if (jobStatus != "failed") return

            val szuruUser = job.optString("szuru_user", "")
            val dashboardUser = job.optString("dashboard_username", "")
            if (currentUsername != szuruUser && currentUsername != dashboardUser) {
                // Job belongs to another user; ignore
                return
            }

            val sourceOverride = job.optString("source_override", "")
            val url = job.optString("url", "")
            val primarySource = when {
                !sourceOverride.isNullOrBlank() -> sourceOverride
                !url.isNullOrBlank() -> url
                else -> null
            }

            var websiteName = "Processing"
            var fullDomain = ""
            if (primarySource != null) {
                try {
                    val uri = Uri.parse(primarySource)
                    val host = uri.host ?: primarySource
                    websiteName = if (host.startsWith("www.")) host.substring(4) else host
                    fullDomain = primarySource
                } catch (_: Exception) {
                    websiteName = primarySource
                    fullDomain = primarySource
                }
            }

            showJobFailureNotification(jobId, websiteName, fullDomain)
            synchronized(notifiedFailedJobs) {
                notifiedFailedJobs.add(jobId)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to handle SSE data: $payload", e)
        }
    }

    private fun showJobFailureNotification(
        jobId: String,
        websiteName: String,
        fullDomain: String
    ) {
        val manager = getSystemService(NotificationManager::class.java) ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                JOB_FAILURE_CHANNEL_ID,
                "Job failure notifications",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for failed uploads and processing errors"
            }
            manager.createNotificationChannel(channel)
        }

        val notificationId = kotlin.math.abs(jobId.hashCode()) % 100000
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val contentText =
            if (fullDomain.isNotEmpty()) "Failed to upload from $fullDomain" else "A job has failed"

        val notification = NotificationCompat.Builder(this, JOB_FAILURE_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Upload failed: $websiteName")
            .setContentText(contentText)
            .setStyle(NotificationCompat.BigTextStyle().bigText(contentText))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .build()

        manager.notify(notificationId, notification)
    }

    companion object {
        private const val TAG = "CompanionFgService"
        const val NOTIFICATION_ID = 100
        const val CHANNEL_ID = "companion_status"
        private const val COMPANION_GROUP_KEY = "companion_persistent"
        private const val JOB_FAILURE_CHANNEL_ID = "job_failures"
        const val EXTRA_SHOW_BUBBLE = "showBubble"
        const val EXTRA_BODY = "body"
        const val EXTRA_UPDATE_BODY_ONLY = "updateBodyOnly"
    }
}
