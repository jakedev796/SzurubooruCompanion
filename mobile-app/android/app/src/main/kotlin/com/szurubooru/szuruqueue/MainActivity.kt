package com.szurubooru.szuruqueue

import android.content.Intent
import android.net.Uri
import android.os.Bundle
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
        Log.d(TAG, "MainActivity onCreate")
        
        // Check for share intent on launch
        handleShareIntent(intent)
    }
    
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d(TAG, "MainActivity onNewIntent")
        setIntent(intent)
        
        // Handle new share intent while app is running
        handleShareIntent(intent, notifyFlutter = true)
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialShare" -> {
                    result.success(initialShareData)
                }
                "clearInitialShare" -> {
                    initialShareData = null
                    result.success(null)
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
}
