package com.example.leopard_cat

import android.util.Log
import io.nekohasekai.libbox.CommandClient
import io.nekohasekai.libbox.CommandClientHandler
import io.nekohasekai.libbox.CommandClientOptions
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.ConnectionEvents
import io.nekohasekai.libbox.LogIterator
import io.nekohasekai.libbox.OutboundGroupItemIterator
import io.nekohasekai.libbox.OutboundGroupIterator
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.StatusMessage
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.SystemProxyStatus
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

private const val TAG = "LeopardCatEngine"

interface CoreEngineAdapter {
    fun initialize()
    fun start(configJson: String): EngineResult
    fun reload(configJson: String): EngineResult
    fun stop(): EngineResult
    fun lastError(): String?
    fun delayTest(outbound: String): Int?
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
    private val onTrafficChanged: (uplinkBytes: Long, downlinkBytes: Long) -> Unit = { _, _ -> },
) : CoreEngineAdapter {
    private var configJson: String? = null
    private var latestError: String? = null
    private lateinit var commandServer: CommandServer
    private lateinit var commandClient: CommandClient
    private var telemetryConnected = false
    private val telemetryLock = Any()
    private val outboundDelays = mutableMapOf<String, OutboundDelay>()
    private val outboundUpdateGenerations = mutableMapOf<String, Long>()
    private val pendingDelayTests = mutableMapOf<String, PendingDelayTest>()

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
            startTelemetry()
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
            startTelemetry()
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
        stopTelemetry()
        if (::commandServer.isInitialized) {
            runCatching { commandServer.closeService() }
            runCatching { commandServer.close() }
        }
        return EngineResult.STOPPED
    }

    override fun lastError(): String? = latestError

    override fun delayTest(outbound: String): Int? {
        if (outbound.isBlank() || !telemetryConnected) return null
        val pending = synchronized(telemetryLock) {
            val previous = outboundDelays[outbound]
            PendingDelayTest(
                previousGeneration = outboundUpdateGenerations[outbound] ?: 0,
                startedAtSeconds = TimeUnit.MILLISECONDS.toSeconds(System.currentTimeMillis()),
            ).also { pendingDelayTests[outbound] = it }
        }
        return try {
            commandClient.urlTest(outbound)
            if (pending.result.await(urlTestTimeoutSeconds, TimeUnit.SECONDS)) {
                pending.delay
            } else {
                null
            }
        } catch (t: Throwable) {
            Log.w(TAG, "url test failed for $outbound", t)
            null
        } finally {
            synchronized(telemetryLock) {
                if (pendingDelayTests[outbound] === pending) {
                    pendingDelayTests.remove(outbound)
                }
            }
        }
    }

    private fun startTelemetry() {
        if (!::commandClient.isInitialized) {
            val options = CommandClientOptions().apply {
                addCommand(Libbox.CommandStatus)
                addCommand(Libbox.CommandOutbounds)
                statusInterval = TimeUnit.SECONDS.toNanos(1)
            }
            commandClient = CommandClient(TelemetryHandler(), options)
        }
        if (!telemetryConnected) {
            commandClient.connect()
            telemetryConnected = true
        }
    }

    private fun stopTelemetry() {
        if (::commandClient.isInitialized) {
            runCatching { commandClient.disconnect() }
        }
        telemetryConnected = false
        synchronized(telemetryLock) {
            pendingDelayTests.values.forEach { it.result.countDown() }
            pendingDelayTests.clear()
        }
    }

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

    private inner class TelemetryHandler : CommandClientHandler {
        override fun clearLogs() = Unit

        override fun connected() {
            Log.i(TAG, "telemetry command client connected")
        }

        override fun disconnected(message: String) {
            Log.d(TAG, "telemetry command client disconnected: $message")
        }

        override fun initializeClashMode(modeList: StringIterator, currentMode: String) = Unit

        override fun setDefaultLogLevel(level: Int) = Unit

        override fun updateClashMode(newMode: String) = Unit

        override fun writeConnectionEvents(events: ConnectionEvents) = Unit

        override fun writeGroups(message: OutboundGroupIterator) = Unit

        override fun writeLogs(messageList: LogIterator) = Unit

        override fun writeStatus(message: StatusMessage) {
            if (message.trafficAvailable) {
                onTrafficChanged(
                    message.uplinkTotal.coerceAtLeast(0),
                    message.downlinkTotal.coerceAtLeast(0),
                )
            }
        }

        override fun writeOutbounds(message: OutboundGroupItemIterator) {
            while (message.hasNext()) {
                val item = message.next()
                synchronized(telemetryLock) {
                    val delay = OutboundDelay(item.getURLTestTime(), item.getURLTestDelay())
                    outboundDelays[item.tag] = delay
                    val generation = (outboundUpdateGenerations[item.tag] ?: 0) + 1
                    outboundUpdateGenerations[item.tag] = generation
                    val pending = pendingDelayTests[item.tag] ?: continue
                    if (generation > pending.previousGeneration && delay.testTime >= pending.startedAtSeconds) {
                        pending.delay = delay.value
                        pending.result.countDown()
                    }
                }
            }
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

    private data class OutboundDelay(val testTime: Long, val value: Int)

    private class PendingDelayTest(
        val previousGeneration: Long,
        val startedAtSeconds: Long,
    ) {
        val result = CountDownLatch(1)
        var delay: Int? = null
    }

    private companion object {
        const val urlTestTimeoutSeconds = 15L
    }
}
