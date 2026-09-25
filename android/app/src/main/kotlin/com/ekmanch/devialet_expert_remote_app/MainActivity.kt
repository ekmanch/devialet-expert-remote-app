package com.ekmanch.devialet_expert_remote_app

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the one platform channel the app needs on Android (Task 3.9.5): a
 * `WifiManager.MulticastLock` held while the Dart mDNS browse session runs,
 * so multicast reaches the app on Wi-Fi radios that filter it (Samsung).
 * Not reference-counted, so repeated acquire/release calls are harmless;
 * released on destroy as a backstop.
 */
class MainActivity : FlutterActivity() {
    private var lock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquire" -> {
                    val held = lock ?: (applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager)
                        .createMulticastLock("devialet-mdns")
                        .also {
                            it.setReferenceCounted(false)
                            lock = it
                        }
                    held.acquire()
                    result.success(null)
                }
                "release" -> {
                    lock?.takeIf { it.isHeld }?.release()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        lock?.takeIf { it.isHeld }?.release()
        super.onDestroy()
    }

    private companion object {
        const val CHANNEL = "com.ekmanch.devialet_expert_remote_app/multicast_lock"
    }
}
