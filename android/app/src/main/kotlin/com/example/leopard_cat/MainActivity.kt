package com.example.leopard_cat

import android.content.Intent
import android.net.VpnService
import io.nekohasekai.libbox.Libbox
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import android.os.Build

class MainActivity : FlutterActivity() {
	private val channelName = "leopard_cat/core"
	private val vpnPermissionRequestCode = 4101

	override fun onCreate(savedInstanceState: android.os.Bundle?) {
		super.onCreate(savedInstanceState)
		handleAutoStart(intent)
	}

	override fun onNewIntent(intent: Intent) {
		super.onNewIntent(intent)
		handleAutoStart(intent)
	}

	// Debug-only entry: `adb shell am start -n .../.MainActivity --ez auto_start true --es auto_start_config_file /data/local/tmp/leopardcat_config.json`
	private fun handleAutoStart(intent: Intent?) {
		if (intent == null || !intent.getBooleanExtra("auto_start", false)) return
		val config = intent.getStringExtra("auto_start_config")
			?: readConfigFromFile(intent.getStringExtra("auto_start_config_file"))
			?: return
		android.util.Log.i("LeopardCat", "auto-start config length=${config.length}")
		startCore(config, object : MethodChannel.Result {
			override fun success(result: Any?) {
				android.util.Log.i("LeopardCat", "auto-start result: $result")
			}
			override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
				android.util.Log.e("LeopardCat", "auto-start error: $errorCode $errorMessage")
			}
			override fun notImplemented() = Unit
		})
	}

	private fun readConfigFromFile(path: String?): String? {
		if (path == null) return null
		return try {
			java.io.File(path).readText()
		} catch (t: Throwable) {
			android.util.Log.e("LeopardCat", "failed to read config file: $t")
			null
		}
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"start" -> startCore(call.argument("config"), result)
					"reload" -> reloadCore(call.argument("config"), result)
					"stop" -> stopCore(result)
					"status" -> result.success(statusPayload())
					"queryTraffic" -> result.success(mapOf(
						"uplink_bytes" to LeopardCatVpnService.uplinkBytes,
						"downlink_bytes" to LeopardCatVpnService.downlinkBytes,
					))
					"coreVersion" -> result.success(Libbox.version())
					"delayTest" -> delayTest(call.argument("outbound"), result)
					"selectOutbound" -> selectOutbound(
						call.argument("group"),
						call.argument("outbound"),
						result,
					)
					else -> result.notImplemented()
				}
			}
	}

	private fun startCore(config: String?, result: MethodChannel.Result) {
		if (config == null) {
			result.success("unavailable")
			return
		}
		val permissionIntent = VpnService.prepare(this)
		if (permissionIntent != null) {
			pendingConfig = config
			startActivityForResult(permissionIntent, vpnPermissionRequestCode)
			result.success("permission_required")
			return
		}

		startVpnService(createServiceIntent(LeopardCatVpnService.ACTION_START, config))
		result.success("starting")
	}

	private fun reloadCore(config: String?, result: MethodChannel.Result) {
		if (config == null || LeopardCatVpnService.status == EngineResult.STOPPED) {
			result.success("stopped")
			return
		}
		startVpnService(createServiceIntent(LeopardCatVpnService.ACTION_RELOAD, config))
		result.success(currentStatus())
	}

	private fun stopCore(result: MethodChannel.Result) {
		val serviceIntent = Intent(this, LeopardCatVpnService::class.java)
		serviceIntent.action = LeopardCatVpnService.ACTION_STOP
		startVpnService(serviceIntent)
		result.success("stopped")
	}

	private fun delayTest(outbound: String?, result: MethodChannel.Result) {
		if (outbound.isNullOrBlank()) {
			result.success(null)
			return
		}
		Thread {
			val delay = LeopardCatVpnService.delayTest(outbound)
			runOnUiThread { result.success(delay) }
		}.start()
	}

	private fun selectOutbound(group: String?, outbound: String?, result: MethodChannel.Result) {
		if (group.isNullOrBlank() || outbound.isNullOrBlank()) {
			result.success(false)
			return
		}
		Thread {
			val selected = LeopardCatVpnService.selectOutbound(group, outbound)
			runOnUiThread { result.success(selected) }
		}.start()
	}

	private fun currentStatus(): String {
		return when (LeopardCatVpnService.status) {
			EngineResult.RUNNING -> "running"
			EngineResult.INVALID_CONFIG -> "unavailable"
			EngineResult.UNAVAILABLE -> "unavailable"
			EngineResult.STOPPED -> "stopped"
		}
	}

	private fun statusPayload(): Map<String, String?> = mapOf(
		"status" to currentStatus(),
		"error" to LeopardCatVpnService.lastError,
	)

	override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
		super.onActivityResult(requestCode, resultCode, data)
		if (requestCode == vpnPermissionRequestCode && resultCode == RESULT_OK) {
			pendingConfig?.let { config ->
				startVpnService(createServiceIntent(LeopardCatVpnService.ACTION_START, config))
			}
			pendingConfig = null
		}
	}

	private var pendingConfig: String? = null

	private fun createServiceIntent(action: String, config: String): Intent {
		val configFile = java.io.File(filesDir, "runtime-config.json")
		configFile.writeText(config)
		return Intent(this, LeopardCatVpnService::class.java).apply {
			this.action = action
			putExtra(LeopardCatVpnService.EXTRA_CONFIG_PATH, configFile.absolutePath)
		}
	}

	private fun startVpnService(intent: Intent) {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			startForegroundService(intent)
		} else {
			startService(intent)
		}
	}
}
