package com.example.wallet_mobile

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "deeplink"
    private var methodChannel: MethodChannel? = null
    private var initialLink: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "getInitialLink" -> {
                            result.success(initialLink)
                            initialLink = null
                        }
                        else -> result.notImplemented()
                    }
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val link = intent?.dataString ?: return
        if (initialLink == null) {
            initialLink = link
        }
        methodChannel?.invokeMethod("onLink", link)
    }
}
