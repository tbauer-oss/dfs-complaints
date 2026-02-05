package de.dfs_diamon.dfs_complaints

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "dfs/notification_permissions"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "getAndroidSdkInfo") {
                    val sdkInt = android.os.Build.VERSION.SDK_INT
                    val targetSdk = BuildConfig.TARGET_SDK
                    val compileSdk = BuildConfig.COMPILE_SDK
                    val payload = mapOf(
                        "sdkInt" to sdkInt,
                        "targetSdk" to targetSdk,
                        "compileSdk" to compileSdk,
                    )
                    result.success(payload)
                } else {
                    result.notImplemented()
                }
            }
    }
}

