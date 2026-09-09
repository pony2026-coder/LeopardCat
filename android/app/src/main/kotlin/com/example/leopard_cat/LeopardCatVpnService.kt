package com.example.leopard_cat

import android.content.Intent
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.net.VpnService
import android.os.IBinder
import android.os.ParcelFileDescriptor

class LeopardCatVpnService : VpnService() {
    private lateinit var platform: AndroidPlatformInterface
    private lateinit var engine: LibboxEngineAdapter
    private var tunDescriptor: ParcelFileDescriptor? = null

    override fun onCreate() {
        super.onCreate()
        startForegroundServiceNotification()
        platform = AndroidPlatformInterface(this) { descriptor -> tunDescriptor = descriptor }
        engine = LibboxEngineAdapter(platform, filesDir.absolutePath)
        engine.initialize()
    }

    private fun startForegroundServiceNotification() {
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
        when (intent?.action) {
            ACTION_START -> {
                val config = intent.getStringExtra(EXTRA_CONFIG_JSON)
                status = if (config == null) {
                    EngineResult.INVALID_CONFIG
                } else {
                    engine.start(config)
                }
            }
            ACTION_RELOAD -> {
                val config = intent.getStringExtra(EXTRA_CONFIG_JSON)
                status = if (config == null) {
                    EngineResult.INVALID_CONFIG
                } else {
                    engine.reload(config)
                }
            }
            ACTION_STOP -> {
                status = engine.stop()
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
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
