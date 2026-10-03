package com.example.lol

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.MotionEvent
import android.view.Surface
import android.view.SurfaceControl
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.lol/intent"
    private val CLICK_CHANNEL = "tv_webview/click"
    private val DISPLAY_CHANNEL = "app/display_refresh"
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Activar el máximo Hz de la pantalla al abrir la Activity
        requestHighestRefreshRate()
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        // ── Click nativo de la mira (WebView TV) ─────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CLICK_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "injectClick") {
                    val x = (call.argument<Double>("x") ?: 0.0).toFloat()
                    val y = (call.argument<Double>("y") ?: 0.0).toFloat()
                    injectNativeClick(x, y)
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }

        // ── Tasa de refresco (Hz) de la pantalla ─────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DISPLAY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestHighestRefreshRate" -> {
                        result.success(requestHighestRefreshRate())
                    }
                    "getRefreshRate" -> {
                        result.success(currentRefreshRate())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // REFRESCO MÁXIMO DE PANTALLA (60 / 90 / 120 / 144 Hz)
    // ═══════════════════════════════════════════════════════════════════════

    private fun requestHighestRefreshRate(): Double {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return currentRefreshRate()
        }
        val display = windowManager.defaultDisplay
        val modes = display.supportedModes
        val best = modes.maxByOrNull { it.refreshRate } ?: return currentRefreshRate()

        val params = window.attributes
        params.preferredDisplayModeId = best.modeId
        window.attributes = params

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.decorView.post {
                try {
                    window.decorView.let { decor ->
                        try {
                            val method = decor.javaClass.getMethod("getSurfaceControl")
                            val surfaceControl = method.invoke(decor) as? SurfaceControl
                            if (surfaceControl != null) {
                                SurfaceControl.Transaction()
                                    .setFrameRate(
                                        surfaceControl,
                                        best.refreshRate,
                                        Surface.FRAME_RATE_COMPATIBILITY_DEFAULT
                                    )
                                    .apply()
                            }
                        } catch (_: Throwable) { }
                    }
                } catch (_: Throwable) { }
            }
        }

        return best.refreshRate.toDouble()
    }

    private fun currentRefreshRate(): Double {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                windowManager.defaultDisplay.mode.refreshRate.toDouble()
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay.refreshRate.toDouble()
            }
        } catch (_: Throwable) {
            60.0
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CLICK NATIVO WEBVIEW (mira TV)
    // ═══════════════════════════════════════════════════════════════════════

    private fun injectNativeClick(flutterX: Float, flutterY: Float) {
        val root = window?.decorView ?: return
        val webView = findWebView(root) ?: return
        val density = resources.displayMetrics.density
        val localX = flutterX * density
        val localY = flutterY * density
        Handler(Looper.getMainLooper()).post {
            val downTime = SystemClock.uptimeMillis()
            val down = MotionEvent.obtain(
                downTime, downTime,
                MotionEvent.ACTION_DOWN,
                localX, localY, 0
            )
            val up = MotionEvent.obtain(
                downTime, downTime + 60,
                MotionEvent.ACTION_UP,
                localX, localY, 0
            )
            webView.dispatchTouchEvent(down)
            webView.dispatchTouchEvent(up)
            down.recycle()
            up.recycle()
        }
    }

    private fun findWebView(view: View): WebView? {
        if (view is WebView) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                findWebView(view.getChildAt(i))?.let { return it }
            }
        }
        return null
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DEEP LINKS (lol://user | lol://content | lol://list)
    // ═══════════════════════════════════════════════════════════════════════

    private fun handleIntent(intent: Intent) {
        val data = intent.data
        data?.let { uri ->
            when {
                uri.scheme == "lol" && uri.host == "user" -> {
                    val userId = uri.path?.replaceFirst("/", "") ?: ""
                    if (userId.isNotEmpty()) {
                        sendToFlutter("user", userId)
                    }
                }
                uri.scheme == "lol" && uri.host == "content" -> {
                    val idcontenido = uri.path?.replaceFirst("/", "") ?: ""
                    if (idcontenido.isNotEmpty() && idcontenido.all { it.isDigit() }) {
                        sendToFlutter("content", idcontenido)
                    } else {
                        println("❌ ID de contenido inválido: $idcontenido")
                    }
                }
                uri.scheme == "lol" && uri.host == "list" -> {
                    val filter = uri.path?.replaceFirst("/", "") ?: ""
                    if (filter.isNotEmpty()) {
                        sendToFlutter("list", filter)
                    }
                }
                else -> {
                    val url = uri.toString()
                    if (url.isNotEmpty()) {
                        sendToFlutter("url", url)
                    }
                }
            }
        }
    }

    private fun sendToFlutter(type: String, value: String) {
        try {
            val data = mapOf(
                "type" to type,
                "value" to value
            )
            methodChannel?.invokeMethod("openDeepLink", data)
            println("📱 Enviando a Flutter: type=$type, value=$value")
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}