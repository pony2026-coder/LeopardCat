package com.example.leopard_cat

import android.content.Intent
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.net.VpnService
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.util.Log

private const val TAG = "LeopardCatVpn"

class LeopardCatVpnService : VpnService() {
    private lateinit var platform: AndroidPlatformInterface
    private lateinit var engine: LibboxEngineAdapter
    private var tunDescriptor: ParcelFileDescriptor? = null

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "onCreate")
        activeService = this
        startForegroundServiceNotification()
        platform = AndroidPlatformInterface(this) { descriptor ->
            Log.i(TAG, "TUN created, fd=${descriptor.fd}")
            tunDescriptor = descriptor
        }
        engine = LibboxEngineAdapter(
            platformInterface = platform,
            basePath = filesDir.absolutePath,
            onDebugMessage = { message -> Log.d(TAG, "sing-box: $message") },
            onTrafficChanged = { uplink, downlink ->
                uplinkBytes = uplink
                downlinkBytes = downlink
            },
        )
        engine.initialize()
    }

    private fun startForegroundServiceNotification() {
        Log.i(TAG, "starting foreground notification")
        val channelId = "leopard_cat_vpn"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "LeopardCat VPN",
                NotificationManager.IMPORTANCE_LOW,
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            Notification.Builder(this)
        }.setContentTitle("LeopardCat")
            .setContentText("VPN service is running")
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .build()
        startForeground(1001, notification)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "onStartCommand: action=${intent?.action}")
        when (intent?.action) {
            ACTION_START -> {
                uplinkBytes = 0
                downlinkBytes = 0
                val config = readConfig(intent)
                status = if (config == null) {
                    Log.e(TAG, "ACTION_START: missing config")
                    EngineResult.INVALID_CONFIG
                } else {
                    engine.start(config)
                }
                lastError = engine.lastError()
                Log.i(TAG, "ACTION_START -> status=$status")
            }
            ACTION_RELOAD -> {
                val config = readConfig(intent)
                status = if (config == null) {
                    Log.e(TAG, "ACTION_RELOAD: missing config")
                    EngineResult.INVALID_CONFIG
                } else {
                    engine.reload(config)
                }
                lastError = engine.lastError()
                Log.i(TAG, "ACTION_RELOAD -> status=$status")
            }
            ACTION_STOP -> {
                Log.i(TAG, "ACTION_STOP")
                status = engine.stop()
                lastError = null
                stopForegroundService()
                stopSelf()
            }
        }
        return START_STICKY
    }

    private fun readConfig(intent: Intent): String? {
        val path = intent.getStringExtra(EXTRA_CONFIG_PATH)
        if (path != null) {
            return runCatching { java.io.File(path).readText() }
                .onFailure { Log.e(TAG, "failed to read runtime config", it) }
                .getOrNull()
        }
        return intent.getStringExtra(EXTRA_CONFIG_JSON)
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy")
        if (::engine.isInitialized) engine.stop()
        tunDescriptor?.close()
        tunDescriptor = null
        stopForegroundService()
        activeService = null
        status = EngineResult.STOPPED
        lastError = null
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    private fun stopForegroundService() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            stopForeground(true)
        }
    }

    override fun onBind(intent: Intent?): IBinder? {
        return super.onBind(intent)
    }

    companion object {
        const val ACTION_START = "com.example.leopard_cat.action.START"
        const val ACTION_RELOAD = "com.example.leopard_cat.action.RELOAD"
        const val ACTION_STOP = "com.example.leopard_cat.action.STOP"
        const val EXTRA_CONFIG_JSON = "config_json"
        const val EXTRA_CONFIG_PATH = "config_path"

        @Volatile
        var status: EngineResult = EngineResult.STOPPED

        @Volatile
        var uplinkBytes: Long = 0

        @Volatile
        var downlinkBytes: Long = 0

        @Volatile
        var lastError: String? = null

        @Volatile
        private var activeService: LeopardCatVpnService? = null

        fun delayTest(outbound: String): Int? = activeService?.engine?.delayTest(outbound)

        fun selectOutbound(group: String, outbound: String): Boolean =
            activeService?.engine?.selectOutbound(group, outbound) ?: false
    }
}
