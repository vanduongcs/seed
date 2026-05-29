package vn.mekonglab.seedvision

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "vn.mekonglab.seedvision/app_update",
        ).setMethodCallHandler { call, result ->
            if (call.method != "openStore") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val playStoreUrl = call.argument<String>("playStoreUrl")
                ?: "https://play.google.com/store/apps/details?id=vn.mekonglab.seedvision"
            openStore(playStoreUrl)
            result.success(null)
        }
    }

    private fun openStore(playStoreUrl: String) {
        try {
            startActivity(
                Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse("market://details?id=vn.mekonglab.seedvision"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: ActivityNotFoundException) {
            startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse(playStoreUrl))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }
}
