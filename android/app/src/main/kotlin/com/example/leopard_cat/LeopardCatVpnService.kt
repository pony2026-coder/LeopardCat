package com.example.leopard_cat

import android.content.Intent
import android.net.VpnService
import android.os.IBinder

class LeopardCatVpnService : VpnService() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        isRunning = true
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? {
        return super.onBind(intent)
    }

    companion object {
        @Volatile
        var isRunning: Boolean = false
    }
}
