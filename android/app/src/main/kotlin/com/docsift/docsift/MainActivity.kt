package com.docsift.docsift

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import android.view.autofill.AutofillManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val AUTOFILL_CHANNEL = "com.docsift.docsift/autofill"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Security: Block screenshots, screen recordings, and background previews
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
    }

    override fun onResume() {
        super.onResume()
        // Re-apply security flag in case system cleared it
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AUTOFILL_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAutofillServiceEnabled" -> {
                    val afm = getSystemService(AutofillManager::class.java)
                    val enabled = afm != null &&
                        afm.isAutofillSupported &&
                        afm.hasEnabledAutofillServices()
                    result.success(enabled)
                }

                "openAutofillSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE).apply {
                            data = Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (_: Exception) {
                        try {
                            startActivity(Intent(Settings.ACTION_SETTINGS))
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                }

                "syncCredentials" -> {
                    val rawList = call.arguments as? List<*>
                    val entries = ArrayList<AutofillEntry>()
                    if (rawList != null) {
                        for (item in rawList) {
                            val map = item as? Map<*, *> ?: continue
                            val id = map["id"]?.toString().orEmpty()
                            val title = map["title"]?.toString().orEmpty()
                            val username = map["username"]?.toString().orEmpty()
                            val password = map["password"]?.toString().orEmpty()
                            if (id.isEmpty() || password.isEmpty()) continue
                            val domains = (map["domains"] as? List<*>)
                                ?.mapNotNull { it?.toString() }
                                ?: emptyList()
                            val packages = (map["packages"] as? List<*>)
                                ?.mapNotNull { it?.toString() }
                                ?: emptyList()
                            val updatedAt = (map["updatedAt"] as? Number)?.toLong()
                                ?: System.currentTimeMillis()
                            entries.add(
                                AutofillEntry(
                                    id = id,
                                    title = title,
                                    username = username,
                                    password = password,
                                    domains = domains,
                                    packages = packages,
                                    updatedAt = updatedAt,
                                )
                            )
                        }
                    }
                    AutofillCredentialStore.saveAllCredentials(applicationContext, entries)
                    result.success(null)
                }

                "consumePendingSaves" -> {
                    val pending = AutofillCredentialStore.consumePendingSaves(applicationContext)
                    val mapped = pending.map { item ->
                        mapOf(
                            "title" to item.title,
                            "username" to item.username,
                            "password" to item.password,
                            "domain" to item.domain,
                            "packageName" to item.packageName,
                            "capturedAt" to item.capturedAt,
                        )
                    }
                    result.success(mapped)
                }

                "clearAllAutofillData" -> {
                    AutofillCredentialStore.clearAll(applicationContext)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }
}
