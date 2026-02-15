package com.szurubooru.szuruqueue

import android.content.Context
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * WorkManager Worker that triggers the workmanager plugin's callback dispatcher.
 * This is called by AlarmManager via FolderSyncAlarmReceiver.
 * We use this as a bridge to execute the Flutter isolate callback.
 */
class FolderSyncWorker(
    context: Context,
    params: WorkerParameters
) : Worker(context, params) {

    companion object {
        private const val TAG = "FolderSyncWorker"
    }

    override fun doWork(): Result {
        Log.d(TAG, "======================================")
        Log.d(TAG, "FolderSyncWorker started")
        Log.d(TAG, "Time: ${System.currentTimeMillis()}")
        Log.d(TAG, "This will be handled by workmanager plugin callback")
        Log.d(TAG, "======================================")

        // The actual work is done by the workmanager plugin's BackgroundWorker
        // which calls our Dart callbackDispatcher().
        // We return success here as this is just a trigger point.

        return Result.success()
    }
}
