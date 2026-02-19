package com.szurubooru.szuruqueue

import android.app.Activity
import android.content.ClipboardManager
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Transparent activity that briefly takes focus so it can read the clipboard
 * (required on Android 10+ where only the foreground app may read clipboard).
 *
 * Clipboard reading is deferred to [onWindowFocusChanged] so the activity has
 * full input focus before accessing the ClipboardManager.
 */
class ClipboardReaderActivity : Activity() {
    companion object {
        private const val TAG = "ClipboardReader"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var handled = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Don't read clipboard here - wait for window focus
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && !handled) {
            handled = true
            handleClipboard()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
    }

    private fun handleClipboard() {
        val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager

        if (!clipboard.hasPrimaryClip()) {
            showToast("Clipboard is empty")
            BubbleOverlayHelper.triggerResult(false)
            finish()
            return
        }

        val clip = clipboard.primaryClip
        if (clip == null || clip.itemCount == 0) {
            showToast("Clipboard is empty")
            BubbleOverlayHelper.triggerResult(false)
            finish()
            return
        }

        val text = clip.getItemAt(0).coerceToText(this)?.toString()
        val url = BackendHelper.normalizeUrl(text)

        if (url.isNullOrBlank()) {
            showToast("No valid URL in clipboard")
            BubbleOverlayHelper.triggerResult(false)
            finish()
            return
        }

        Log.d(TAG, "URL from clipboard: $url")

        // Pre-flight health check
        val healthStatus = HealthMonitor.validateBasicHealth(this)
        if (healthStatus != HealthMonitor.HealthStatus.HEALTHY) {
            val errorMessage = HealthMonitor.getErrorMessage(healthStatus)
            showToast(errorMessage)
            BubbleOverlayHelper.triggerResult(false)
            finish()
            return
        }

        val settings = BackendHelper.readSettings(this)

        val tags = BackendHelper.parseTags(settings.defaultTags)
        val payload = BackendHelper.buildPayload(
            url = url,
            tags = tags,
            safety = settings.defaultSafety,
            skipTagging = settings.skipTagging,
        )

        scope.launch {
            val success = withContext(Dispatchers.IO) {
                BackendHelper.sendJobToBackend(
                    baseUrl = settings.backendUrl!!,
                    accessToken = settings.accessToken,
                    payload = payload,
                    context = this@ClipboardReaderActivity
                )
            }
            withContext(Dispatchers.Main) {
                showToast(if (success) "Share queued" else "Failed to queue share")
                // Trigger bubble animation
                BubbleOverlayHelper.triggerResult(success)
                finish()
            }
        }
    }

    private fun showToast(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
    }
}
