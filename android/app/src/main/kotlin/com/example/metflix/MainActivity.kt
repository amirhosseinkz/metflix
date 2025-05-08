package com.example.metflix

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.metflix.player/drm"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
                call, result ->
            if (call.method == "playDRMVideo") {
                val url = call.argument<String>("url")
                val licenseUrl = call.argument<String>("licenseUrl")
                val intent = Intent(this, DrmPlayerActivity::class.java)
                intent.putExtra("url", url)
                intent.putExtra("licenseUrl", licenseUrl)
                startActivity(intent)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
