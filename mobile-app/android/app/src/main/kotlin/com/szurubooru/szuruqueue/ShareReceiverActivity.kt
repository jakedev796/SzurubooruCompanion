package com.szurubooru.szuruqueue

import android.app.Activity
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

class ShareReceiverActivity : Activity() {
    companion object {
        private const val TAG = "ShareReceiver"
    }

    private val activityScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

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

        val settings = BackendHelper.readSettings(this)

        Log.d(TAG, "Settings loaded - backendUrl: ${settings.backendUrl}, accessToken: ${if (settings.accessToken.isNullOrBlank()) "not set" else "present"}")
        Log.d(TAG, "Default settings - tags: ${settings.defaultTags}, safety: ${settings.defaultSafety}, skipTagging: ${settings.skipTagging}")

        if (settings.backendUrl.isNullOrBlank()) {
            showToast("Configure backend URL in SzuruCompanion settings first")
            finish()
            return
        }

        val tags = BackendHelper.parseTags(settings.defaultTags)
        val extractedUrls = extractUrlsFromIntent(intent)

        if (extractedUrls.isEmpty()) {
            showToast("No valid content to share")
            finish()
            return
        }

        Log.d(TAG, "Extracted ${extractedUrls.size} URL(s) to queue")

        activityScope.launch {
            var successCount = 0
            var failCount = 0

            for (urlData in extractedUrls) {
                val payload = BackendHelper.buildPayload(
                    url = urlData.url,
                    tags = tags,
                    safety = settings.defaultSafety,
                    skipTagging = settings.skipTagging,
                    mimeType = urlData.mimeType,
                )
                val success = withContext(Dispatchers.IO) {
                    BackendHelper.sendJobToBackend(settings.backendUrl, settings.accessToken, payload)
                }
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
                if (mimeType?.startsWith("text/") == true) {
                    val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                    val url = BackendHelper.normalizeUrl(text)
                    if (!url.isNullOrBlank()) {
                        urls.add(UrlData(url))
                    }
                } else if (mimeType?.startsWith("image/") == true || mimeType?.startsWith("video/") == true) {
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

    private fun showToast(message: String) {
        runOnUiThread {
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
        }
    }
}
