package com.example.wallet_mobile

import android.content.Intent
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "deeplink"
    private val logTag = "MainActivity"
    private var methodChannel: MethodChannel? = null
    private var initialLink: String? = null
    private val linkQueue: ArrayDeque<String> = ArrayDeque()
    private val queuedLinks: MutableSet<String> = mutableSetOf()
    private val dispatchedLinks: MutableSet<String> = mutableSetOf()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(logTag, "Configuring Flutter engine and initializing method channel")
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

        flushPendingLinks()
        initialLink?.let {
            Log.d(logTag, "Dispatching known initial link after channel initialization: $it")
            sendLink(it)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val link = intent?.dataString ?: return
        Log.d(logTag, "Received intent with link: $link")

        if (initialLink == null) {
            initialLink = link
        }

        if (dispatchedLinks.contains(link)) {
            Log.d(logTag, "Ignoring duplicate link that was already dispatched: $link")
            return
        }

        if (methodChannel == null) {
            enqueueLink(link)
        } else {
            sendLink(link)
        }
    }

    private fun enqueueLink(link: String) {
        if (queuedLinks.contains(link)) {
            Log.d(logTag, "Link is already queued, skipping enqueue: $link")
            return
        }
        Log.d(logTag, "Method channel not ready; queuing link: $link")
        queuedLinks.add(link)
        linkQueue.add(link)
    }

    private fun flushPendingLinks() {
        if (linkQueue.isEmpty()) {
            Log.d(logTag, "No pending links to flush")
            return
        }
        Log.d(logTag, "Flushing ${linkQueue.size} pending links after channel initialization")
        while (linkQueue.isNotEmpty()) {
            val link = linkQueue.removeFirst()
            queuedLinks.remove(link)
            sendLink(link)
        }
    }

    private fun sendLink(link: String) {
        if (methodChannel == null) {
            Log.d(logTag, "Method channel not available, re-queueing link: $link")
            enqueueLink(link)
            return
        }
        if (dispatchedLinks.contains(link)) {
            Log.d(logTag, "Skipping duplicate dispatch of link: $link")
            return
        }
        Log.d(logTag, "Dispatching link to Dart via method channel: $link")
        methodChannel?.invokeMethod("onLink", link)
        dispatchedLinks.add(link)
    }
}
