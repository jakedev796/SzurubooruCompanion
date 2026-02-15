package com.szurubooru.szuruqueue

import android.app.Activity
import android.content.ClipData
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.TimeUnit

class ShareReceiverActivity : Activity() {
    companion object {
        private const val TAG = "ShareReceiver"
        // Flutter's shared_preferences uses this prefix for keys
        private const val FLUTTER_PREFS_NAME = "FlutterSharedPreferences"
        private const val DEFAULT_SAFETY = "unsafe"
        private const val DEFAULT_BACKEND_PORT = 21425
    }

    private val activityScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    override fun onDestroy() {
        super.onDestroy()
        activityScope.cancel()
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) {
            finish()
            return
        }
        
        val action = intent.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) {
            Log.w(TAG, "Unexpected action: $action")
            finish()
            return
        }

        Log.d(TAG, "Handling share intent with action: $action, type: ${intent.type}")

        // Read settings from Flutter's SharedPreferences
        val prefs = getSharedPreferences(FLUTTER_PREFS_NAME, MODE_PRIVATE)
        val backendUrl = prefs.getString("flutter.backendUrl", null)
        val apiKey = prefs.getString("flutter.apiKey", null)
        val defaultTags = prefs.getString("flutter.defaultTags", "") ?: ""
        val defaultSafety = prefs.getString("flutter.defaultSafety", DEFAULT_SAFETY) ?: DEFAULT_SAFETY
        val skipTagging = prefs.getBoolean("flutter.skipTagging", false)

        Log.d(TAG, "Settings loaded - backendUrl: $backendUrl, apiKey: ${if (apiKey.isNullOrBlank()) "not set" else "present"}")
        Log.d(TAG, "Default settings - tags: $defaultTags, safety: $defaultSafety, skipTagging: $skipTagging")

        if (backendUrl.isNullOrBlank()) {
            showToast("Configure backend URL in SzuruCompanion settings first")
            finish()
            return
        }

        // Parse tags
        val tags = parseTags(defaultTags)

        // Extract content from intent
        val extractedUrls = extractUrlsFromIntent(intent)
        
        if (extractedUrls.isEmpty()) {
            showToast("No valid content to share")
            finish()
            return
        }

        Log.d(TAG, "Extracted ${extractedUrls.size} URL(s) to queue")

        // Launch coroutine to send jobs
        activityScope.launch {
            var successCount = 0
            var failCount = 0

            for (urlData in extractedUrls) {
                val payload = buildPayload(urlData, tags, defaultSafety, skipTagging)
                val success = sendJobToBackend(backendUrl, apiKey, payload)
                if (success) successCount++ else failCount++
            }

            withContext(Dispatchers.Main) {
                if (failCount == 0) {
                    showToast(if (successCount == 1) "Share queued" else "${successCount} shares queued")
                } else if (successCount > 0) {
                    showToast("${successCount} queued, ${failCount} failed")
                } else {
                    showToast("Failed to queue share")
                }
                finish()
            }
        }
    }

    private data class UrlData(
        val url: String,
        val isLocalFile: Boolean = false,
        val mimeType: String? = null
    )

    private fun extractUrlsFromIntent(intent: Intent): List<UrlData> {
        val urls = mutableListOf<UrlData>()
        val mimeType = intent.type

        when (intent.action) {
            Intent.ACTION_SEND -> {
                // Single item share
                if (mimeType?.startsWith("text/") == true) {
                    // Text share - extract URL from text
                    val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                    val url = normalizeUrl(text)
                    if (!url.isNullOrBlank()) {
                        urls.add(UrlData(url))
                    }
                } else if (mimeType?.startsWith("image/") == true || mimeType?.startsWith("video/") == true) {
                    // Media share - get URI
                    val uri = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(Intent.EXTRA_STREAM)
                    }
                    
                    if (uri != null) {
                        val url = uri.toString()
                        Log.d(TAG, "Media share URI: $url, mimeType: $mimeType")
                        urls.add(UrlData(url, isLocalFile = true, mimeType = mimeType))
                    }
                }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                // Multiple items share
                @Suppress("DEPRECATION")
                val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                uris?.forEach { uri ->
                    val url = uri.toString()
                    Log.d(TAG, "Multiple share URI: $url")
                    urls.add(UrlData(url, isLocalFile = true, mimeType = mimeType))
                }
            }
        }

        return urls
    }

    private fun parseTags(tagsString: String): List<String> {
        return tagsString
            .split(Regex("[\\s,]+"))
            .mapNotNull { if (it.isNotBlank()) it.trim() else null }
            .map { it.trim('[', ']', '(', ')') }
            .filter { it.isNotEmpty() }
    }

    private fun buildPayload(
        urlData: UrlData,
        tags: List<String>,
        safety: String,
        skipTagging: Boolean
    ): JSONObject {
        return JSONObject().apply {
            put("url", urlData.url)
            put("source", urlData.url)
            
            if (tags.isNotEmpty()) {
                put("tags", JSONArray(tags))
            }
            
            put("safety", safety)
            put("skip_tagging", skipTagging)
            
            if (urlData.mimeType != null) {
                put("content_type", urlData.mimeType)
            }
        }
    }

    private suspend fun sendJobToBackend(
        baseUrl: String,
        apiKey: String?,
        payload: JSONObject
    ): Boolean = withContext(Dispatchers.IO) {
        try {
            // Normalize URL - ensure no double slashes and proper endpoint
            val normalizedBaseUrl = baseUrl.trimEnd('/')
            val endpoint = "$normalizedBaseUrl/api/jobs"
            
            Log.d(TAG, "Sending job to: $endpoint")
            Log.d(TAG, "Payload: ${payload.toString()}")

            val requestBody = payload.toString()
                .toRequestBody("application/json; charset=utf-8".toMediaType())

            val requestBuilder = Request.Builder()
                .url(endpoint)
                .post(requestBody)
                .header("Content-Type", "application/json")

            // Add API key header if configured
            if (!apiKey.isNullOrBlank()) {
                requestBuilder.header("X-API-Key", apiKey)
            }

            val request = requestBuilder.build()
            val response = httpClient.newCall(request).execute()

            val success = response.isSuccessful
            val responseBody = response.body?.string()
            
            if (success) {
                Log.d(TAG, "Job queued successfully: $responseBody")
            } else {
                Log.e(TAG, "Job queue failed: ${response.code} - $responseBody")
            }
            
            response.close()
            success
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send job to backend", e)
            withContext(Dispatchers.Main) {
                showToast("Error: ${e.message}")
            }
            false
        }
    }

    private fun normalizeUrl(text: String?): String? {
        if (text.isNullOrBlank()) return null
        
        var normalized = text.trim()
        
        // Replace common Twitter/X redirect domains
        normalized = normalized
            .replace("fxtwitter.com", "twitter.com")
            .replace("fixupx.com", "x.com")
            .replace("ddinstagram.com", "instagram.com")

        // Extract URL using regex
        val urlRegex = Regex("https?://[^\\s,]+")
        val match = urlRegex.find(normalized)
        
        return match?.value?.trimEnd('.', ',', ')', ']', '}')
    }

    private fun showToast(message: String) {
        runOnUiThread {
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
        }
    }
}
