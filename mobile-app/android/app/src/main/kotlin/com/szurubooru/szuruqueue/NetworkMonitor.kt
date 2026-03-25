package com.szurubooru.szuruqueue

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.util.Log

class NetworkMonitor(
    private val context: Context,
    private val onNetworkAvailable: () -> Unit
) {
    private val TAG = "NetworkMonitor"
    private var connectivityManager: ConnectivityManager? = null
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var wasConnected = true

    fun start() {
        connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        val cm = connectivityManager ?: return
        wasConnected = isConnected(cm)

        callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                if (!wasConnected) {
                    Log.d(TAG, "Network restored, triggering reconnection")
                    wasConnected = true
                    onNetworkAvailable()
                }
            }

            override fun onLost(network: Network) {
                if (!isConnected(cm)) {
                    Log.d(TAG, "Network lost")
                    wasConnected = false
                }
            }
        }

        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        cm.registerNetworkCallback(request, callback!!)
        Log.d(TAG, "Network monitoring started")
    }

    fun stop() {
        callback?.let {
            try {
                connectivityManager?.unregisterNetworkCallback(it)
            } catch (e: Exception) {
                Log.w(TAG, "Error unregistering network callback", e)
            }
        }
        callback = null
        connectivityManager = null
    }

    private fun isConnected(cm: ConnectivityManager): Boolean {
        val network = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(network) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }
}
