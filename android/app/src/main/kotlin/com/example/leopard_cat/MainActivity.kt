package com.example.leopard_cat

import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val channelName = "leopard_cat/core"
	private val vpnPermissionRequestCode = 4101

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"start" -> startCore(result)
					"stop" -> stopCore(result)
					"status" -> result.success(currentStatus())
					else -> result.notImplemented()
				}
			}
	}

	private fun startCore(result: MethodChannel.Result) {
		val permissionIntent = VpnService.prepare(this)
		if (permissionIntent != null) {
			startActivityForResult(permissionIntent, vpnPermissionRequestCode)
			result.success("permission_required")
			return
		}

		startService(Intent(this, LeopardCatVpnService::class.java))
		result.success("starting")
	}

	private fun stopCore(result: MethodChannel.Result) {
		stopService(Intent(this, LeopardCatVpnService::class.java))
		result.success("stopped")
	}

	private fun currentStatus(): String {
		return if (LeopardCatVpnService.isRunning) "running" else "stopped"
	}

	override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
		super.onActivityResult(requestCode, resultCode, data)
		if (requestCode == vpnPermissionRequestCode && resultCode == RESULT_OK) {
			startService(Intent(this, LeopardCatVpnService::class.java))
		}
	}
}
