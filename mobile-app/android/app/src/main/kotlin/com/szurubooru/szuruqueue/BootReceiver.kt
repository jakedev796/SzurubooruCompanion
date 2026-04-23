package com.szurubooru.szuruqueue

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Re-registers the folder sync alarm after a device reboot or app upgrade.
 * AlarmManager alarms do not persist across reboots, so without this the
 * scheduled folder sync silently stops firing until the user opens the app
 * and saves settings again.
 */
class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) {
            return
        }

        Log.i(TAG, "Received ${intent.action}, re-registering folder sync alarm")

        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val intervalSeconds = prefs.getLong("flutter.folderSyncIntervalSeconds", 900L).toInt()

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
            Log.w(TAG, "Cannot schedule exact alarms after boot; user must re-grant permission")
            return
        }

        val alarmIntent = Intent(context, FolderSyncAlarmReceiver::class.java).apply {
            action = FolderSyncAlarmReceiver.ACTION_FOLDER_SYNC
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            alarmIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val now = System.currentTimeMillis()
        val intervalMillis = (intervalSeconds * 1000L).coerceIn(900000L, 604800000L)
        val intervalMinutes = (intervalMillis / 60000).toInt()
        val nowMinutes = (now / 60000) % 1440
        val nextSlotMinutes = ((nowMinutes / intervalMinutes) + 1) * intervalMinutes
        val minutesToNext = nextSlotMinutes - nowMinutes
        val nextSyncTime = now + (minutesToNext * 60000)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    nextSyncTime,
                    pendingIntent
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    nextSyncTime,
                    pendingIntent
                )
            }
            Log.i(TAG, "Alarm re-registered for ${java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US).format(java.util.Date(nextSyncTime))}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to re-register alarm after boot", e)
        }
    }
}
