package com.szurubooru.szuruqueue

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import android.view.View
import android.view.WindowManager
import androidx.core.app.NotificationCompat

/**
 * Foreground service that renders a small floating bubble on top of other apps.
 * Tapping the bubble launches [ClipboardReaderActivity] to read the clipboard
 * and queue the URL to the CCC backend.
 * 
 * Used only when folder sync is NOT enabled (otherwise CompanionForegroundService handles it).
 * Uses specialUse type which will show Android's overlay permission notification.
 * This is expected behavior for overlay services.
 */
class FloatingBubbleService : Service() {

    private var windowManager: WindowManager? = null
    private var bubbleView: View? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            startForeground(NOTIFICATION_ID, buildNotification())
            showBubble()
        } catch (e: Exception) {
            Log.e(TAG, "onStartCommand failed", e)
        }
        return START_STICKY
    }

    override fun onDestroy() {
        removeBubble()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // -- Bubble overlay (BubbleOverlayHelper) ---------------------------------

    private fun showBubble() {
        if (bubbleView != null) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            Log.w(TAG, "Overlay permission not granted, skipping bubble")
            return
        }

        try {
            windowManager = getSystemService(WINDOW_SERVICE) as? WindowManager ?: return
            val (bubble, params) = BubbleOverlayHelper.createBubbleView(this, windowManager!!) {
                startActivity(Intent(this, ClipboardReaderActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                })
            }
            windowManager!!.addView(bubble, params)
            BubbleOverlayHelper.runEntryAnimation(bubble)
            bubbleView = bubble
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show bubble overlay", e)
        }
    }

    private fun removeBubble() {
        bubbleView?.let {
            try {
                windowManager?.removeView(it)
            } catch (e: Exception) {
                Log.w(TAG, "Error removing bubble view", e)
            }
        }
        bubbleView = null
    }

    // -- Notification ---------------------------------------------------------

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Floating Bubble",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps the quick-share bubble visible"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_SINGLE_TOP },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SzuruCompanion")
            .setContentText("Quick-share bubble active")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    companion object {
        private const val TAG = "FloatingBubble"
        const val NOTIFICATION_ID = 101
        const val CHANNEL_ID = "bubble"
    }
}
