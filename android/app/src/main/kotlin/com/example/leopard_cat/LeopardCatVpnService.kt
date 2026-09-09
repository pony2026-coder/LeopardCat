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
        startForegroundServiceNotification()
        platform = AndroidPlatformInterface(this) { descriptor ->
            Log.i(TAG, "TUN created, fd=${descriptor.fd}")
            tunDescriptor = descriptor
        }
        engine = LibboxEngineAdapter(platform, filesDir.absolutePath) { message ->
            Log.d(TAG, "sing-box: $message")
        }
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
                val config = intent.getStringExtra(EXTRA_CONFIG_JSON)
                status = if (config == null) {
                    Log.e(TAG, "ACTION_START: missing config")
                    EngineResult.INVALID_CONFIG
                } else {
                    engine.start(config)
                }
                Log.i(TAG, "ACTION_START -> status=$status")
            }
            ACTION_RELOAD -> {
                val config = intent.getStringExtra(EXTRA_CONFIG_JSON)
                status = if (config == null) {
                    Log.e(TAG, "ACTION_RELOAD: missing config")
                    EngineResult.INVALID_CONFIG
                } else {
                    engine.reload(config)
                }
                Log.i(TAG, "ACTION_RELOAD -> status=$status")
            }
            ACTION_STOP -> {
                Log.i(TAG, "ACTION_STOP")
                status = engine.stop()
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy")
        if (::engine.isInitialized) engine.stop()
        tunDescriptor?.close()
        status = EngineResult.STOPPED
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? {
        return super.onBind(intent)
    }

    companion object {
        const val ACTION_START = "com.example.leopard_cat.action.START"
        const val ACTION_RELOAD = "com.example.leopard_cat.action.RELOAD"
        const val ACTION_STOP = "com.example.leopard_cat.action.STOP"
        const val EXTRA_CONFIG_JSON = "config_json"

        @Volatile
        var status: EngineResult = EngineResult.STOPPED

        @Volatile
        var uplinkBytes: Long = 0

        @Volatile
        var downlinkBytes: Long = 0
    }
}
