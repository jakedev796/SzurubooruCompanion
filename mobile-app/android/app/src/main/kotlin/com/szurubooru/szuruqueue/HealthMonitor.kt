package com.szurubooru.szuruqueue

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.util.concurrent.TimeUnit

/**
 * Health monitoring utilities for validating app state and tracking failures.
 * Provides pre-flight validation and error rate tracking.
 * 
 * Thread-safe: Uses Mutex for synchronized access to SharedPreferences operations.
 */
object HealthMonitor {
    private const val TAG = "HealthMonitor"
    private const val PREFS_NAME = "HealthMonitor"
    private const val KEY_FAILURE_TIMESTAMPS = "failure_timestamps"
    private const val KEY_SUCCESS_COUNT = "success_count"
    private const val KEY_FAILURE_COUNT = "failure_count"
    
    // Error rate thresholds
    private const val MAX_FAILURES_IN_WINDOW = 3
    private const val FAILURE_WINDOW_MS = 5 * 60 * 1000L // 5 minutes
    
    // Mutex for thread-safe SharedPreferences access (for suspend functions)
    private val prefsMutex = Mutex()
    
    // Lock object for synchronized blocks (for non-suspend functions)
    private val prefsLock = Any()

    enum class HealthStatus {
        HEALTHY,
        MISSING_BACKEND_URL,
        MISSING_ACCESS_TOKEN,
        TOO_MANY_FAILURES,
        UNKNOWN
    }

    /**
     * Validate basic health (settings only, no network call).
     * Checks if backendUrl and accessToken are present.
     * 
     * Note: Only checks if token exists, not expiration.
     * Expired tokens will fail fast with 401 (acceptable UX).
     */
    fun validateBasicHealth(context: Context): HealthStatus {
        val settings = BackendHelper.readSettings(context)
        
        return when {
            settings.backendUrl.isNullOrBlank() -> HealthStatus.MISSING_BACKEND_URL
            settings.accessToken.isNullOrBlank() -> HealthStatus.MISSING_ACCESS_TOKEN
            isUnhealthy(context) -> HealthStatus.TOO_MANY_FAILURES
            else -> HealthStatus.HEALTHY
        }
    }

    /**
     * Validate full health (includes backend connectivity test).
     * This adds network latency, use sparingly.
     */
    suspend fun validateFullHealth(context: Context, backendUrl: String): HealthStatus {
        val basicStatus = validateBasicHealth(context)
        if (basicStatus != HealthStatus.HEALTHY) {
            return basicStatus
        }

        return withContext(Dispatchers.IO) {
            // testBackendConnectivity is blocking, so it's safe to call from IO dispatcher
            val isConnected = BackendHelper.testBackendConnectivity(backendUrl)
            if (isConnected) {
                HealthStatus.HEALTHY
            } else {
                HealthStatus.UNKNOWN
            }
        }
    }

    /**
     * Record a successful operation.
     * Thread-safe: Uses Mutex to prevent race conditions.
     */
    suspend fun recordSuccess(context: Context) {
        withContext(Dispatchers.IO) {
            prefsMutex.withLock {
                val prefs = getPrefs(context)
                val currentSuccess = prefs.getLong(KEY_SUCCESS_COUNT, 0)
                prefs.edit()
                    .putLong(KEY_SUCCESS_COUNT, currentSuccess + 1)
                    .apply()
                
                // Clean old failures periodically
                cleanOldFailures(prefs)
            }
        }
    }

    /**
     * Record a failed operation with optional error type.
     * Thread-safe: Uses Mutex to prevent race conditions.
     * 
     * Note: This is a suspend function for thread safety. For use from non-suspend contexts,
     * use recordFailureSync() which uses synchronized block.
     */
    suspend fun recordFailure(context: Context, errorType: String = "unknown") {
        withContext(Dispatchers.IO) {
            prefsMutex.withLock {
                val prefs = getPrefs(context)
                val now = System.currentTimeMillis()
                
                val failureTimestamps = getFailureTimestamps(prefs).toMutableList()
                failureTimestamps.add(now)
                
                val currentFailures = prefs.getLong(KEY_FAILURE_COUNT, 0)
                
                prefs.edit()
                    .putString(KEY_FAILURE_TIMESTAMPS, failureTimestamps.joinToString(","))
                    .putLong(KEY_FAILURE_COUNT, currentFailures + 1)
                    .apply()
                
                Log.d(TAG, "Recorded failure: $errorType (total failures: ${currentFailures + 1})")
            }
        }
    }
    
    /**
     * Synchronous version of recordFailure for use from non-suspend contexts.
     * Uses synchronized block for thread safety.
     * 
     * Note: SharedPreferences individual operations are thread-safe, but read-modify-write
     * sequences need synchronization to prevent race conditions.
     */
    fun recordFailureSync(context: Context, errorType: String = "unknown") {
        synchronized(prefsLock) {
            val prefs = getPrefs(context)
            val now = System.currentTimeMillis()
            
            val failureTimestamps = getFailureTimestamps(prefs).toMutableList()
            failureTimestamps.add(now)
            
            val currentFailures = prefs.getLong(KEY_FAILURE_COUNT, 0)
            
            prefs.edit()
                .putString(KEY_FAILURE_TIMESTAMPS, failureTimestamps.joinToString(","))
                .putLong(KEY_FAILURE_COUNT, currentFailures + 1)
                .apply()
            
            Log.d(TAG, "Recorded failure: $errorType (total failures: ${currentFailures + 1})")
        }
    }
    
    /**
     * Synchronous version of recordSuccess for use from non-suspend contexts.
     * Uses synchronized block for thread safety.
     * 
     * Note: SharedPreferences individual operations are thread-safe, but read-modify-write
     * sequences need synchronization to prevent race conditions.
     */
    fun recordSuccessSync(context: Context) {
        synchronized(prefsLock) {
            val prefs = getPrefs(context)
            val currentSuccess = prefs.getLong(KEY_SUCCESS_COUNT, 0)
            prefs.edit()
                .putLong(KEY_SUCCESS_COUNT, currentSuccess + 1)
                .apply()
            
            // Clean old failures periodically
            cleanOldFailures(prefs)
        }
    }

    /**
     * Check if system is unhealthy based on error rate.
     */
    fun isUnhealthy(context: Context): Boolean {
        val prefs = getPrefs(context)
        val failures = getFailureTimestamps(prefs)
        val now = System.currentTimeMillis()
        
        // Count failures in the last window
        val recentFailures = failures.count { now - it < FAILURE_WINDOW_MS }
        
        return recentFailures >= MAX_FAILURES_IN_WINDOW
    }

    /**
     * Get user-friendly error message for health status.
     */
    fun getErrorMessage(status: HealthStatus): String {
        return when (status) {
            HealthStatus.HEALTHY -> ""
            HealthStatus.MISSING_BACKEND_URL -> "Configure backend URL in SzuruCompanion settings first"
            HealthStatus.MISSING_ACCESS_TOKEN -> "Login required - please log in to SzuruCompanion"
            HealthStatus.TOO_MANY_FAILURES -> "Too many recent failures - check your connection and settings"
            HealthStatus.UNKNOWN -> "Unable to reach backend - check your connection"
        }
    }

    /**
     * Reset failure tracking (useful for testing or after fixing issues).
     */
    fun resetTracking(context: Context) {
        val prefs = getPrefs(context)
        prefs.edit()
            .remove(KEY_FAILURE_TIMESTAMPS)
            .putLong(KEY_FAILURE_COUNT, 0)
            .putLong(KEY_SUCCESS_COUNT, 0)
            .apply()
    }

    private fun getPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private fun getFailureTimestamps(prefs: SharedPreferences): List<Long> {
        val timestampsStr = prefs.getString(KEY_FAILURE_TIMESTAMPS, null) ?: return emptyList()
        return timestampsStr.split(",")
            .mapNotNull { it.toLongOrNull() }
            .sorted()
    }

    private fun cleanOldFailures(prefs: SharedPreferences) {
        val now = System.currentTimeMillis()
        val failures = getFailureTimestamps(prefs)
        val recentFailures = failures.filter { now - it < FAILURE_WINDOW_MS }
        
        if (recentFailures.size != failures.size) {
            prefs.edit()
                .putString(KEY_FAILURE_TIMESTAMPS, recentFailures.joinToString(","))
                .apply()
        }
    }
}
