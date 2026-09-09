package com.example.leopard_cat

import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import android.os.Build

class MainActivity : FlutterActivity() {
	private val channelName = "leopard_cat/core"
	private val vpnPermissionRequestCode = 4101

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"start" -> startCore(call.argument("config"), result)
					"reload" -> reloadCore(call.argument("config"), result)
					"stop" -> stopCore(result)
					"status" -> result.success(currentStatus())
					"queryTraffic" -> result.success(mapOf(
						"uplink_bytes" to LeopardCatVpnService.uplinkBytes,
						"downlink_bytes" to LeopardCatVpnService.downlinkBytes,
					))
					"delayTest" -> result.success(null)
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

		val serviceIntent = Intent(this, LeopardCatVpnService::class.java)
		serviceIntent.action = LeopardCatVpnService.ACTION_START
		serviceIntent.putExtra(LeopardCatVpnService.EXTRA_CONFIG_JSON, config)
		startVpnService(serviceIntent)
		result.success("starting")
	}

	private fun reloadCore(config: String?, result: MethodChannel.Result) {
		if (config == null || LeopardCatVpnService.status == EngineResult.STOPPED) {
			result.success("stopped")
			return
		}
		val serviceIntent = Intent(this, LeopardCatVpnService::class.java)
		serviceIntent.action = LeopardCatVpnService.ACTION_RELOAD
		serviceIntent.putExtra(LeopardCatVpnService.EXTRA_CONFIG_JSON, config)
		startVpnService(serviceIntent)
		result.success(currentStatus())
	}

	private fun stopCore(result: MethodChannel.Result) {
		val serviceIntent = Intent(this, LeopardCatVpnService::class.java)
		serviceIntent.action = LeopardCatVpnService.ACTION_STOP
		startVpnService(serviceIntent)
		result.success("stopped")
	}

	private fun currentStatus(): String {
		return when (LeopardCatVpnService.status) {
			EngineResult.RUNNING -> "running"
			EngineResult.INVALID_CONFIG -> "unavailable"
			EngineResult.UNAVAILABLE -> "unavailable"
			EngineResult.STOPPED -> "stopped"
		}
	}

	override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
		super.onActivityResult(requestCode, resultCode, data)
		if (requestCode == vpnPermissionRequestCode && resultCode == RESULT_OK) {
			pendingConfig?.let { config ->
				val serviceIntent = Intent(this, LeopardCatVpnService::class.java)
				serviceIntent.action = LeopardCatVpnService.ACTION_START
				serviceIntent.putExtra(LeopardCatVpnService.EXTRA_CONFIG_JSON, config)
				startVpnService(serviceIntent)
			}
			pendingConfig = null
		}
	}

	private var pendingConfig: String? = null

	private fun startVpnService(intent: Intent) {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			startForegroundService(intent)
		} else {
			startService(intent)
		}
	}
}
