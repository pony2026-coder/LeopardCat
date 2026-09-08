package com.example.leopard_cat

import android.content.Intent
import android.net.VpnService
import android.os.IBinder

class LeopardCatVpnService : VpnService() {
    private val engine = LibboxEngineAdapter()

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
        engine.stop()
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
