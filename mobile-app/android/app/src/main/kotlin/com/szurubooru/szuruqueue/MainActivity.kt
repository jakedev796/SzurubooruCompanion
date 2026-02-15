package com.szurubooru.szuruqueue

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.szurubooru.szuruqueue/share"
    private val TAG = "SzuruCompanion"
    private val PREFS_NAME = "szuruqueue_prefs"
    private val KEY_INTENT_HANDLED = "intent_handled_timestamp"
    
    private var initialShareData: Map<String, Any?>? = null
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "MainActivity onCreate, action=${intent?.action}")

        // Check for share intent on launch
        handleShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d(TAG, "MainActivity onNewIntent, action=${intent?.action}")
        setIntent(intent)

        // Handle new share intent while app is running
        handleShareIntent(intent, notifyFlutter = true)
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Storage permission channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.szurubooru.szuruqueue/storage").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasStoragePermission" -> {
                    val hasPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        Environment.isExternalStorageManager()
                    } else {
                        true // Not needed on older Android versions
                    }
                    result.success(hasPermission)
                }
                "requestStoragePermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        try {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error opening storage permission settings", e)
                            result.error("PERMISSION_ERROR", e.message, null)
                        }
                    } else {
                        result.success(null) // Not needed on older Android versions
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Share intent channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialShare" -> {
                    result.success(initialShareData)
                }
                "clearInitialShare" -> {
                    initialShareData = null
                    result.success(null)
                }
                "deleteContentUri" -> {
                    val uriStr = call.argument<String>("uri")
                    if (uriStr != null) {
                        try {
                            val uri = Uri.parse(uriStr)
                            val deleted = if (DocumentsContract.isDocumentUri(this, uri)) {
                                DocumentsContract.deleteDocument(contentResolver, uri)
                            } else {
                                contentResolver.delete(uri, null, null) > 0
                            }
                            result.success(deleted)
                        } catch (e: Exception) {
                            Log.e(TAG, "deleteContentUri failed", e)
                            result.success(false)
                        }
                    } else {
                        result.error("INVALID_ARGS", "uri required", null)
                    }
                }
                "startForegroundStatusService" -> {
                    val body = call.argument<String>("body") ?: "Folder sync enabled."
                    val intent = Intent(this, StatusForegroundService::class.java).apply {
                        putExtra(StatusForegroundService.EXTRA_BODY, body)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "stopForegroundStatusService" -> {
                    stopService(Intent(this, StatusForegroundService::class.java))
                    result.success(null)
                }
                "scheduleAlarmManagerSync" -> {
                    val intervalSeconds = call.argument<Int>("intervalSeconds") ?: 900
                    scheduleAlarmManagerSync(intervalSeconds)
                    result.success(null)
                }
                "cancelAlarmManagerSync" -> {
                    cancelAlarmManagerSync()
                    result.success(null)
                }
                "canScheduleExactAlarms" -> {
                    val canSchedule = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                        alarmManager.canScheduleExactAlarms()
                    } else {
                        true // Permission not required on older versions
                    }
                    result.success(canSchedule)
                }
                "requestExactAlarmPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        try {
                            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                            startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error opening exact alarm settings", e)
                            result.error("PERMISSION_ERROR", e.message, null)
                        }
                    } else {
                        result.success(null) // Not needed on older versions
                    }
                }
                "listMediaUrisFromTree" -> {
                    val treeUriStr = call.argument<String>("treeUri")
                    if (treeUriStr != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        try {
                            val uris = listMediaUrisRecursive(contentResolver, Uri.parse(treeUriStr))
                            result.success(uris)
                        } catch (e: Exception) {
                            Log.e(TAG, "listMediaUrisFromTree failed", e)
                            result.error("LIST_FAILED", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "treeUri required and API 21+", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private fun handleShareIntent(intent: Intent?, notifyFlutter: Boolean = false) {
        if (intent == null) return
        
        val action = intent.action
        Log.d(TAG, "handleShareIntent: action = $action")
        
        if (action != Intent.ACTION_SEND) return
        
        // Check if we recently handled this intent (prevents rotation re-processing)
        val now = System.currentTimeMillis()
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val lastHandledTime = prefs.getLong(KEY_INTENT_HANDLED, 0)
        
        if (now - lastHandledTime < 5000) {
            Log.d(TAG, "Intent recently handled (${now - lastHandledTime}ms ago), skipping")
            return
        }
        
        // Mark as handled
        prefs.edit().putLong(KEY_INTENT_HANDLED, now).apply()
        
        val type = intent.type
        Log.d(TAG, "Share intent type: $type")
        
        val shareData = mutableMapOf<String, Any?>()
        
        when {
            type?.startsWith("text/") == true -> {
                // Text/URL share
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                if (text != null) {
                    shareData["type"] = "text"
                    shareData["url"] = extractUrl(text)
                    Log.d(TAG, "Text share: ${shareData["url"]}")
                }
            }
            type?.startsWith("image/") == true || type?.startsWith("video/") == true -> {
                // File share
                val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                if (uri != null) {
                    shareData["type"] = if (type?.startsWith("video/") == true) "video" else "image"
                    shareData["path"] = uri.toString()
                    Log.d(TAG, "File share: ${shareData["path"]}")
                }
            }
        }
        
        if (shareData.isNotEmpty()) {
            if (notifyFlutter) {
                // Send to Flutter immediately
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, CHANNEL).invokeMethod("share", shareData)
                }
            } else {
                // Store for later retrieval
                initialShareData = shareData
            }
        }
    }
    
    private fun listMediaUrisRecursive(resolver: android.content.ContentResolver, treeUri: Uri): List<String> {
        if (!DocumentsContract.isTreeUri(treeUri)) return emptyList()
        val docId = DocumentsContract.getTreeDocumentId(treeUri)
        return listMediaUrisUnder(resolver, treeUri, docId)
    }

    private fun listMediaUrisUnder(resolver: android.content.ContentResolver, treeUri: Uri, docId: String): List<String> {
        val result = mutableListOf<String>()
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, docId)
        val cursor = resolver.query(
            childrenUri,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_MIME_TYPE
            ),
            null,
            null,
            null
        ) ?: return result
        cursor.use {
            val idIdx = it.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val mimeIdx = it.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
            while (it.moveToNext()) {
                val childId = it.getString(idIdx)
                val mime = it.getString(mimeIdx)
                val childUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, childId).toString()
                when {
                    mime == null || mime == DocumentsContract.Document.MIME_TYPE_DIR -> {
                        result.addAll(listMediaUrisUnder(resolver, treeUri, childId))
                    }
                    mime.startsWith("image/") || mime.startsWith("video/") -> result.add(childUri)
                    else -> {
                        val ext = childId.substringAfterLast('.', "").lowercase()
                        if (ext in listOf("jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "svg", "mp4", "webm", "mkv", "avi", "mov", "wmv", "flv", "m4v")) {
                            result.add(childUri)
                        }
                    }
                }
            }
        }
        return result
    }

    private fun extractUrl(text: String): String {
        // Handle fxtwitter URLs
        var normalizedText = text
            .replace("fxtwitter.com", "twitter.com")
            .replace("fixupx.com", "twitter.com")

        // Extract first URL
        val urlPattern = Regex("""https?://[^\s]+""")
        val match = urlPattern.find(normalizedText)
        return match?.value?.replace(Regex("""[.,;:)\]]+$"""), "") ?: normalizedText
    }

    /**
     * Schedule folder sync using AlarmManager for reliable exact-time execution.
     * Uses setExactAndAllowWhileIdle() to fire even in Doze mode.
     */
    private fun scheduleAlarmManagerSync(intervalSeconds: Int) {
        Log.d(TAG, "======================================")
        Log.d(TAG, "scheduleAlarmManagerSync: intervalSeconds=$intervalSeconds")

        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager

        // Check if we can schedule exact alarms (Android 12+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (!alarmManager.canScheduleExactAlarms()) {
                Log.e(TAG, "ERROR: Cannot schedule exact alarms! Permission not granted.")
                Log.e(TAG, "User must grant SCHEDULE_EXACT_ALARM permission in settings.")
                return
            }
        }

        // Create intent for the alarm receiver
        val intent = Intent(this, FolderSyncAlarmReceiver::class.java).apply {
            action = FolderSyncAlarmReceiver.ACTION_FOLDER_SYNC
        }

        val pendingIntent = PendingIntent.getBroadcast(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Calculate next sync time aligned to clock boundaries
        val now = System.currentTimeMillis()
        val intervalMillis = (intervalSeconds * 1000L).coerceIn(900000L, 604800000L) // 15 min to 7 days
        val intervalMinutes = (intervalMillis / 60000).toInt()

        // Align to clock boundaries (e.g., :00, :15, :30, :45 for 15-min interval)
        val nowMinutes = (now / 60000) % 1440 // Minutes since midnight
        val nextSlotMinutes = ((nowMinutes / intervalMinutes) + 1) * intervalMinutes
        val minutesToNext = nextSlotMinutes - nowMinutes
        val nextSyncTime = now + (minutesToNext * 60000)

        Log.d(TAG, "Current time: $now")
        Log.d(TAG, "Interval: ${intervalMillis}ms (${intervalMinutes} minutes)")
        Log.d(TAG, "Next sync time: $nextSyncTime (in ${minutesToNext} minutes)")
        Log.d(TAG, "Next sync at: ${java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US).format(java.util.Date(nextSyncTime))}")

        // Use setExactAndAllowWhileIdle for reliable execution even in Doze mode
        // This is what apps like Syncthing use for background sync
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                nextSyncTime,
                pendingIntent
            )
            Log.d(TAG, "Scheduled using setExactAndAllowWhileIdle (API 23+)")
        } else {
            alarmManager.setExact(
                AlarmManager.RTC_WAKEUP,
                nextSyncTime,
                pendingIntent
            )
            Log.d(TAG, "Scheduled using setExact (API < 23)")
        }

        Log.d(TAG, "AlarmManager sync scheduled successfully")
        Log.d(TAG, "======================================")
    }

    /**
     * Cancel the AlarmManager folder sync.
     */
    private fun cancelAlarmManagerSync() {
        Log.d(TAG, "cancelAlarmManagerSync: Cancelling folder sync alarm")

        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val intent = Intent(this, FolderSyncAlarmReceiver::class.java).apply {
            action = FolderSyncAlarmReceiver.ACTION_FOLDER_SYNC
        }

        val pendingIntent = PendingIntent.getBroadcast(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        alarmManager.cancel(pendingIntent)
        Log.d(TAG, "AlarmManager sync cancelled")
    }
}
