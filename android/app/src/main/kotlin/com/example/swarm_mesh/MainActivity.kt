package com.example.swarm_mesh

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Build
import android.os.PowerManager
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "swarm_mesh/storage")
            .setMethodCallHandler { call, result ->
                if (call.method == "getReportDirectory") {
                    result.success(File(noBackupFilesDir, "inventory_reports").absolutePath)
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "swarm_mesh/device_telemetry")
            .setMethodCallHandler { call, result ->
                if (call.method != "getThermalStatus") {
                    result.notImplemented()
                } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    result.success(null)
                } else {
                    try {
                        val powerManager = getSystemService(POWER_SERVICE) as? PowerManager
                        result.success(powerManager?.currentThermalStatus)
                    } catch (error: Exception) {
                        result.error("THERMAL_UNAVAILABLE", error.message, null)
                    }
                }
            }
    }
}
