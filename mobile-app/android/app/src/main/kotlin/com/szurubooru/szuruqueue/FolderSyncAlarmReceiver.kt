package com.szurubooru.szuruqueue

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager

/**
 * BroadcastReceiver that handles AlarmManager alarms for folder sync.
 * Fires at exact times even in Doze mode using setExactAndAllowWhileIdle().
 *
 * Flow:
 * 1. AlarmManager fires → FolderSyncAlarmReceiver.onReceive()
 * 2. Enqueues workmanager plugin task (using special task name)
 * 3. Workmanager plugin's BackgroundWorker executes
 * 4. Calls callbackDispatcher() in Dart
 * 5. Dart code processes folders
 */
class FolderSyncAlarmReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "FolderSyncAlarm"
        const val ACTION_FOLDER_SYNC = "com.szurubooru.szuruqueue.FOLDER_SYNC"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_FOLDER_SYNC) {
            Log.d(TAG, "Ignoring unknown action: ${intent.action}")
            return
        }

        Log.d(TAG, "======================================")
        Log.d(TAG, "AlarmManager alarm fired!")
        Log.d(TAG, "Time: ${System.currentTimeMillis()}")
        Log.d(TAG, "Date: ${java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US).format(java.util.Date())}")
        Log.d(TAG, "======================================")

        // IMPORTANT: Reschedule the next alarm BEFORE running the task
        // This ensures periodic execution continues even if the task fails
        rescheduleNextAlarm(context)

        try {
            // Use the workmanager plugin's internal Worker by using the magic task name
            // The workmanager plugin registers its BackgroundWorker with a specific format
            val inputData = Data.Builder()
                .putLong("triggerTime", System.currentTimeMillis())
                .build()

            // Create a one-time work request that will be picked up by workmanager plugin
            // We use the plugin's BackgroundWorker class directly
            val workRequest = OneTimeWorkRequestBuilder<dev.fluttercommunity.workmanager.BackgroundWorker>()
                .setInputData(inputData)
                .addTag("dev.fluttercommunity.workmanager.folderScanTask")
                .build()

            WorkManager.getInstance(context).enqueueUniqueWork(
                "folder_scan_from_alarm",
                ExistingWorkPolicy.REPLACE,
                workRequest
            )

            Log.d(TAG, "WorkManager task enqueued successfully")
            Log.d(TAG, "Will call callbackDispatcher() in Dart")
        } catch (e: Exception) {
            Log.e(TAG, "Error enqueueing work: ${e.message}", e)
        }
    }

    /**
     * Reschedule the next alarm to maintain periodic execution.
     * Reads the interval from SharedPreferences (set by Dart side).
     */
    private fun rescheduleNextAlarm(context: Context) {
        try {
            // Read sync interval from SharedPreferences
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val intervalSeconds = prefs.getLong("flutter.folderSyncIntervalSeconds", 900L).toInt()

            Log.d(TAG, "Rescheduling next alarm with interval: ${intervalSeconds}s")

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

            // Check permission on Android 12+
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (!alarmManager.canScheduleExactAlarms()) {
                    Log.e(TAG, "Cannot reschedule: exact alarm permission not granted")
                    return
                }
            }

            // Create intent for next alarm
            val intent = Intent(context, FolderSyncAlarmReceiver::class.java).apply {
                action = ACTION_FOLDER_SYNC
            }

            val pendingIntent = PendingIntent.getBroadcast(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Calculate next sync time aligned to clock boundaries
            val now = System.currentTimeMillis()
            val intervalMillis = (intervalSeconds * 1000L).coerceIn(900000L, 604800000L)
            val intervalMinutes = (intervalMillis / 60000).toInt()
            val nowMinutes = (now / 60000) % 1440
            val nextSlotMinutes = ((nowMinutes / intervalMinutes) + 1) * intervalMinutes
            val minutesToNext = nextSlotMinutes - nowMinutes
            val nextSyncTime = now + (minutesToNext * 60000)

            Log.d(TAG, "Next alarm at: ${java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US).format(java.util.Date(nextSyncTime))}")

            // Schedule next alarm
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

            Log.d(TAG, "Next alarm scheduled successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error rescheduling alarm: ${e.message}", e)
        }
    }
}
