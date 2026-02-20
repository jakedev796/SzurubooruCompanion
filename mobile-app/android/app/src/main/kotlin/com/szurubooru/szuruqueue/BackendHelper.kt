package com.szurubooru.szuruqueue

import android.content.Context
import android.net.Uri
import android.util.Log
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Shared helper for sending jobs to the CCC backend.
 * Used by ShareReceiverActivity, ClipboardReaderActivity, and any other
 * component that needs to queue URLs without going through Flutter.
 */
object BackendHelper {
    private const val TAG = "BackendHelper"
    private const val FLUTTER_PREFS_NAME = "FlutterSharedPreferences"
    private const val DEFAULT_SAFETY = "unsafe"

    val httpClient: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    data class Settings(
        val backendUrl: String?,
        val accessToken: String?,
        val defaultTags: String,
        val defaultSafety: String,
        val skipTagging: Boolean,
    )

    /** Read CCC settings from Flutter's SharedPreferences. */
    fun readSettings(context: Context): Settings {
        val prefs = context.getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
        val authTokensJson = prefs.getString("flutter.auth_tokens", null)
        var accessToken: String? = null
        if (!authTokensJson.isNullOrBlank()) {
            try {
                val json = org.json.JSONObject(authTokensJson)
                accessToken = json.optString("access_token", null).takeIf { it.isNotBlank() }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to parse auth_tokens", e)
            }
        }
        return Settings(
            backendUrl = prefs.getString("flutter.backendUrl", null),
            accessToken = accessToken,
            defaultTags = prefs.getString("flutter.defaultTags", "") ?: "",
            defaultSafety = prefs.getString("flutter.defaultSafety", DEFAULT_SAFETY) ?: DEFAULT_SAFETY,
            skipTagging = prefs.getBoolean("flutter.skipTagging", false),
        )
    }

    /** Extract and normalise the first URL from free-form text. */
    fun normalizeUrl(text: String?): String? {
        if (text.isNullOrBlank()) return null

        var normalized = text.trim()
            .replace("fxtwitter.com", "twitter.com")
            .replace("fixupx.com", "x.com")
            .replace("ddinstagram.com", "instagram.com")

        val urlRegex = Regex("https?://[^\\s,]+")
        val match = urlRegex.find(normalized)
        val urlCandidate = match?.value?.trimEnd('.', ',', ')', ']', '}') ?: return null
        
        // Validate URL format using Uri.parse()
        return validateUrl(urlCandidate)
    }

    /**
     * Validate URL format using Uri.parse().
     * Returns the URL if valid, null otherwise.
     */
    fun validateUrl(url: String?): String? {
        if (url.isNullOrBlank()) return null
        
        return try {
            val uri = Uri.parse(url)
            // Check for valid scheme (http/https) and host
            if (uri.scheme != null && (uri.scheme == "http" || uri.scheme == "https") && 
                !uri.host.isNullOrBlank()) {
                url
            } else {
                Log.w(TAG, "Invalid URL format: missing scheme or host - $url")
                null
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse URL: $url", e)
            null
        }
    }

    /**
     * Test backend connectivity using the /api/health endpoint (no auth required).
     * Mirrors the Dart BackendClient.checkConnection() pattern.
     * 
     * Note: This is a blocking function. Use from background thread or coroutine context.
     * Uses the singleton httpClient with custom timeout via newBuilder() to reuse connection pool.
     * 
     * @param backendUrl The backend base URL
     * @param timeoutSeconds Timeout in seconds (default: 5)
     * @return true if backend is reachable and healthy, false otherwise
     */
    fun testBackendConnectivity(backendUrl: String, timeoutSeconds: Int = 5): Boolean {
        return try {
            val healthUrl = "${backendUrl.trimEnd('/')}/api/health"
            val request = Request.Builder()
                .url(healthUrl)
                .get()
                .build()
            
            // Reuse singleton client with custom timeout via newBuilder()
            // This maintains the connection pool while allowing per-call timeout customization
            val clientWithTimeout = httpClient.newBuilder()
                .connectTimeout(timeoutSeconds.toLong(), TimeUnit.SECONDS)
                .readTimeout(timeoutSeconds.toLong(), TimeUnit.SECONDS)
                .build()
            
            val response = clientWithTimeout.newCall(request).execute()
            val isHealthy = response.isSuccessful && response.code == 200
            response.close()
            isHealthy
        } catch (e: Exception) {
            Log.d(TAG, "Backend connectivity test failed: ${e.message}")
            false
        }
    }

    /** Split a tag string (space/comma separated) into a list. */
    fun parseTags(tagsString: String): List<String> {
        return tagsString
            .split(Regex("[\\s,]+"))
            .mapNotNull { if (it.isNotBlank()) it.trim() else null }
            .map { it.trim('[', ']', '(', ')') }
            .filter { it.isNotEmpty() }
    }

    /** Build the JSON payload for POST /api/jobs. */
    fun buildPayload(
        url: String,
        tags: List<String>,
        safety: String,
        skipTagging: Boolean,
        mimeType: String? = null,
    ): JSONObject {
        return JSONObject().apply {
            put("url", url)
            put("source", url)
            if (tags.isNotEmpty()) put("tags", JSONArray(tags))
            put("safety", safety)
            put("skip_tagging", skipTagging)
            if (mimeType != null) put("content_type", mimeType)
        }
    }

    /**
     * POST a job payload to the CCC backend. Returns true on success.
     * Automatically tracks failures/successes for health monitoring.
     * 
     * @param context Context for health tracking (can be null if tracking not needed)
     * @param baseUrl Backend base URL
     * @param accessToken Access token (can be null)
     * @param payload Job payload JSON
     * @return true on success, false on failure
     */
    fun sendJobToBackend(
        baseUrl: String, 
        accessToken: String?, 
        payload: JSONObject,
        context: Context? = null
    ): Boolean {
        return try {
            val endpoint = "${baseUrl.trimEnd('/')}/api/jobs"
            Log.d(TAG, "Sending job to: $endpoint")
            Log.d(TAG, "Payload: $payload")

            val requestBody = payload.toString()
                .toRequestBody("application/json; charset=utf-8".toMediaType())

            val requestBuilder = Request.Builder()
                .url(endpoint)
                .post(requestBody)
                .header("Content-Type", "application/json")

            if (!accessToken.isNullOrBlank()) {
                requestBuilder.header("Authorization", "Bearer $accessToken")
            }

            val response = httpClient.newCall(requestBuilder.build()).execute()
            val success = response.isSuccessful
            val statusCode = response.code
            val responseBody = response.body?.string()

            if (success) {
                Log.d(TAG, "Job queued successfully: $responseBody")
                // Track success (using sync version since we're in blocking context)
                context?.let { HealthMonitor.recordSuccessSync(it) }
            } else {
                // Determine error type for better tracking
                val errorType = when (statusCode) {
                    401 -> "auth_error"
                    400 -> "validation_error"
                    in 500..599 -> "backend_error"
                    else -> "http_error_$statusCode"
                }
                val errorMessage = getErrorMessageForStatusCode(statusCode)
                Log.e(TAG, "Job queue failed: $statusCode - $errorMessage - $responseBody")
                // Track failure (using sync version since we're in blocking context)
                context?.let { HealthMonitor.recordFailureSync(it, errorType) }
            }

            response.close()
            success
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send job to backend", e)
            // Track network error (using sync version since we're in blocking context)
            context?.let { HealthMonitor.recordFailureSync(it, "network_error") }
            false
        }
    }

    /**
     * Get user-friendly error message for HTTP status code.
     */
    private fun getErrorMessageForStatusCode(statusCode: Int): String {
        return when (statusCode) {
            401 -> "Login required"
            400 -> "Invalid request"
            403 -> "Forbidden"
            404 -> "Not found"
            500 -> "Backend error"
            502 -> "Bad gateway"
            503 -> "Service unavailable"
            in 400..499 -> "Client error ($statusCode)"
            in 500..599 -> "Server error ($statusCode)"
            else -> "Error ($statusCode)"
        }
    }
}
