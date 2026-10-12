package com.szurubooru.szuruqueue

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Handles the persistent notification action to toggle the floating bubble.
 * Starts CompanionForegroundService with EXTRA_TOGGLE_BUBBLE so the service
 * updates prefs, overlay, and rebuilds the notification with the other action label.
 */
class CompanionNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != ACTION_TOGGLE_BUBBLE) return
        val serviceIntent = Intent(context, CompanionForegroundService::class.java).apply {
            putExtra(CompanionForegroundService.EXTRA_TOGGLE_BUBBLE, true)
        }
        CompanionForegroundService.start(context, serviceIntent)
    }

    companion object {
        const val ACTION_TOGGLE_BUBBLE = "com.szurubooru.szuruqueue.TOGGLE_BUBBLE"
    }
}
