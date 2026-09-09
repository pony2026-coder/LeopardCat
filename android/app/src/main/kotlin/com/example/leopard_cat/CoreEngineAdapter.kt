package com.example.leopard_cat

import android.util.Log
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SystemProxyStatus
import org.json.JSONObject

private const val TAG = "LeopardCatEngine"

interface CoreEngineAdapter {
    fun initialize()
    fun start(configJson: String): EngineResult
    fun reload(configJson: String): EngineResult
    fun stop(): EngineResult
    fun lastError(): String?
}

enum class EngineResult {
    RUNNING,
    STOPPED,
    INVALID_CONFIG,
    UNAVAILABLE,
}

class LibboxEngineAdapter(
    private val platformInterface: PlatformInterface,
    private val basePath: String,
    private val onDebugMessage: (String) -> Unit = {},
) : CoreEngineAdapter {
    private var configJson: String? = null
    private var latestError: String? = null
    private lateinit var commandServer: CommandServer

    val version: String
        get() = Libbox.version()

    override fun initialize() {
        Log.i(TAG, "initialize: libbox version=${Libbox.version()}")
        val setupOptions = io.nekohasekai.libbox.SetupOptions().apply {
            this.basePath = this@LibboxEngineAdapter.basePath
            workingPath = this@LibboxEngineAdapter.basePath
            tempPath = this@LibboxEngineAdapter.basePath
            appVersion = "0.1.0"
            appMarketingVersion = "0.1.0"
            fixAndroidStack = true
        }
        Libbox.setup(setupOptions)
        Log.i(TAG, "Libbox.setup done")
        commandServer = CommandServer(ServerHandler(), platformInterface)
        commandServer.start()
        Log.i(TAG, "CommandServer started")
    }

    override fun start(configJson: String): EngineResult {
        Log.i(TAG, "start: validating config")
        if (!isValidSingboxConfig(configJson)) {
            Log.e(TAG, "start: INVALID_CONFIG")
            return EngineResult.INVALID_CONFIG
        }
        this.configJson = configJson
        return try {
            Log.i(TAG, "start: calling startOrReloadService")
            commandServer.startOrReloadService(configJson, OverrideOptions())
            latestError = null
            Log.i(TAG, "start: service RUNNING")
            EngineResult.RUNNING
        } catch (t: Throwable) {
            latestError = t.message ?: t.toString()
            Log.e(TAG, "start: service failed", t)
            EngineResult.UNAVAILABLE
        }
    }

    override fun reload(configJson: String): EngineResult {
        Log.i(TAG, "reload: validating config")
        if (!isValidSingboxConfig(configJson)) {
            Log.e(TAG, "reload: INVALID_CONFIG")
            return EngineResult.INVALID_CONFIG
        }
        this.configJson = configJson
        return try {
            Log.i(TAG, "reload: calling startOrReloadService")
            commandServer.startOrReloadService(configJson, OverrideOptions())
            latestError = null
            Log.i(TAG, "reload: service RUNNING")
            EngineResult.RUNNING
        } catch (t: Throwable) {
            latestError = t.message ?: t.toString()
            Log.e(TAG, "reload: service failed", t)
            EngineResult.UNAVAILABLE
        }
    }

    override fun stop(): EngineResult {
        Log.i(TAG, "stop")
        configJson = null
        latestError = null
        if (::commandServer.isInitialized) {
            runCatching { commandServer.closeService() }
            runCatching { commandServer.close() }
        }
        return EngineResult.STOPPED
    }

    override fun lastError(): String? = latestError

    private inner class ServerHandler : CommandServerHandler {
        override fun connectSSHAgent(): Int = -1
        override fun getSystemProxyStatus(): SystemProxyStatus = SystemProxyStatus()
        override fun serviceReload() {
            Log.i(TAG, "serviceReload triggered")
            configJson?.let { commandServer.startOrReloadService(it, OverrideOptions()) }
        }
        override fun serviceStop() {
            Log.i(TAG, "serviceStop triggered")
            commandServer.closeService()
        }
        override fun setSystemProxyEnabled(isEnabled: Boolean) = Unit
        override fun triggerNativeCrash() = error("Native crash trigger is disabled")
        override fun writeDebugMessage(message: String) {
            Log.d(TAG, "sing-box: $message")
            onDebugMessage(message)
        }
    }

    private fun isValidSingboxConfig(configJson: String): Boolean {
        return try {
            val config = JSONObject(configJson)
            if (!config.has("inbounds") || !config.has("outbounds") || !config.has("route")) {
                latestError = "配置缺少 inbounds、outbounds 或 route"
                Log.e(TAG, "config missing required keys: inbounds/outbounds/route")
                return false
            }
            Log.i(TAG, "checkConfig...")
            Libbox.checkConfig(configJson)
            true
        } catch (t: Throwable) {
            latestError = t.message ?: t.toString()
            Log.e(TAG, "checkConfig failed", t)
            false
        }
    }
}
