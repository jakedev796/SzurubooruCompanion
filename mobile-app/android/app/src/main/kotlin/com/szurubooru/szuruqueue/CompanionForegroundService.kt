package com.szurubooru.szuruqueue

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.view.View
import android.view.WindowManager
import androidx.core.app.NotificationCompat

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
        return START_STICKY
    }

    override fun onDestroy() {
        removeBubbleOverlay()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // -- Notification ---------------------------------------------------------

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "SzuruCompanion Notifications",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "App status and folder sync"
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

    companion object {
        private const val TAG = "CompanionFgService"
        const val NOTIFICATION_ID = 100
        const val CHANNEL_ID = "status"
        const val EXTRA_SHOW_BUBBLE = "showBubble"
        const val EXTRA_BODY = "body"
        const val EXTRA_UPDATE_BODY_ONLY = "updateBodyOnly"
    }
}
