package com.example.leopard_cat

import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SystemProxyStatus
import org.json.JSONObject

interface CoreEngineAdapter {
    fun initialize()
    fun start(configJson: String): EngineResult
    fun reload(configJson: String): EngineResult
    fun stop(): EngineResult
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
    private lateinit var commandServer: CommandServer

    val version: String
        get() = Libbox.version()

    override fun initialize() {
        val setupOptions = io.nekohasekai.libbox.SetupOptions().apply {
            this.basePath = this@LibboxEngineAdapter.basePath
            workingPath = this@LibboxEngineAdapter.basePath
            tempPath = this@LibboxEngineAdapter.basePath
            appVersion = "0.1.0"
            appMarketingVersion = "0.1.0"
            fixAndroidStack = true
        }
        Libbox.setup(setupOptions)
        commandServer = CommandServer(ServerHandler(), platformInterface)
        commandServer.start()
    }

    override fun start(configJson: String): EngineResult {
        if (!isValidSingboxConfig(configJson)) return EngineResult.INVALID_CONFIG
        this.configJson = configJson
        return try {
            commandServer.startOrReloadService(configJson, OverrideOptions())
            EngineResult.RUNNING
        } catch (_: Throwable) {
            EngineResult.UNAVAILABLE
        }
    }

    override fun reload(configJson: String): EngineResult {
        if (!isValidSingboxConfig(configJson)) return EngineResult.INVALID_CONFIG
        this.configJson = configJson
        return try {
            commandServer.startOrReloadService(configJson, OverrideOptions())
            EngineResult.RUNNING
        } catch (_: Throwable) {
            EngineResult.UNAVAILABLE
        }
    }

    override fun stop(): EngineResult {
        configJson = null
        if (::commandServer.isInitialized) {
            runCatching { commandServer.closeService() }
            runCatching { commandServer.close() }
        }
        return EngineResult.STOPPED
    }

    private inner class ServerHandler : CommandServerHandler {
        override fun connectSSHAgent(): Int = -1
        override fun getSystemProxyStatus(): SystemProxyStatus = SystemProxyStatus()
        override fun serviceReload() {
            configJson?.let { commandServer.startOrReloadService(it, OverrideOptions()) }
        }
        override fun serviceStop() {
            commandServer.closeService()
        }
        override fun setSystemProxyEnabled(isEnabled: Boolean) = Unit
        override fun triggerNativeCrash() = error("Native crash trigger is disabled")
        override fun writeDebugMessage(message: String) = onDebugMessage(message)
    }

    private fun isValidSingboxConfig(configJson: String): Boolean {
        return try {
            val config = JSONObject(configJson)
            if (!config.has("inbounds") || !config.has("outbounds") || !config.has("route")) {
                return false
            }
            Libbox.checkConfig(configJson)
            true
        } catch (_: Throwable) {
            false
        }
    }
}
