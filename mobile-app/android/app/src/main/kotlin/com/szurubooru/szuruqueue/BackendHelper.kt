package com.szurubooru.szuruqueue

import android.content.Context
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
        return match?.value?.trimEnd('.', ',', ')', ']', '}')
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

    /** POST a job payload to the CCC backend. Returns true on success. */
    fun sendJobToBackend(baseUrl: String, accessToken: String?, payload: JSONObject): Boolean {
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
            false
        }
    }
}
