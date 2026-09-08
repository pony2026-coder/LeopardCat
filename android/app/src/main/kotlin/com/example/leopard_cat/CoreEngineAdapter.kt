package com.example.leopard_cat

import org.json.JSONObject

interface CoreEngineAdapter {
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

class LibboxEngineAdapter : CoreEngineAdapter {
    private var configJson: String? = null

    override fun start(configJson: String): EngineResult {
        if (!isValidSingboxConfig(configJson)) return EngineResult.INVALID_CONFIG
        this.configJson = configJson
        return EngineResult.UNAVAILABLE
    }

    override fun reload(configJson: String): EngineResult {
        if (!isValidSingboxConfig(configJson)) return EngineResult.INVALID_CONFIG
        this.configJson = configJson
        return EngineResult.UNAVAILABLE
    }

    override fun stop(): EngineResult {
        configJson = null
        return EngineResult.STOPPED
    }

    private fun isValidSingboxConfig(configJson: String): Boolean {
        return try {
            val config = JSONObject(configJson)
            config.has("inbounds") && config.has("outbounds") && config.has("route")
        } catch (_: Exception) {
            false
        }
    }
}
