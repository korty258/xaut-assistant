package io.github.korty258.jinhua_assistant

import android.webkit.CookieManager
import android.webkit.WebStorage
import android.webkit.WebViewDatabase
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "io.github.korty258.jinhua_assistant/platform"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "clearWebViewData") {
                try {
                    // 1. 系统级清除 WebStorage (LocalStorage, SessionStorage, IndexedDB, Web SQL, AppCache)
                    WebStorage.getInstance().deleteAllData()

                    // 2. 清除 WebView 数据库凭据与表单
                    val webViewDb = WebViewDatabase.getInstance(context)
                    webViewDb.clearHttpAuthUsernamePassword()
                    webViewDb.clearFormData()

                    // 3. 清除所有 Cookies 并立即刷盘
                    val cookieManager = CookieManager.getInstance()
                    cookieManager.removeAllCookies(null)
                    cookieManager.flush()

                    // 4. 动态清理应用私有目录中的 cache、code_cache 及 app_webview 目录
                    // 动态自适应路径，彻底消除包名硬编码，全面支持多用户与分身空间
                    // 只清空内容，保留目录本身（底层引擎假定该目录在运行期始终存在）
                    context.cacheDir?.listFiles()?.forEach { it.deleteRecursively() }
                    context.codeCacheDir?.listFiles()?.forEach { it.deleteRecursively() }
                    val dataDir = context.applicationInfo.dataDir
                    if (dataDir != null) {
                        val appWebviewDir = File(dataDir, "app_webview")
                        if (appWebviewDir.exists()) {
                            appWebviewDir.deleteRecursively()
                        }
                    }

                    result.success(true)
                } catch (e: Exception) {
                    result.error("CLEAN_FAILED", e.localizedMessage, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
