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
                var replied = false
                fun replySuccess(ok: Boolean) {
                    if (!replied) {
                        replied = true
                        result.success(ok)
                    }
                }
                fun replyError(code: String, message: String?) {
                    if (!replied) {
                        replied = true
                        result.error(code, message, null)
                    }
                }

                try {
                    // 1. 系统级清除 WebStorage (LocalStorage, SessionStorage, IndexedDB, Web SQL, AppCache)
                    WebStorage.getInstance().deleteAllData()

                    // 2. 清除 WebView 数据库凭据与表单
                    val webViewDb = WebViewDatabase.getInstance(context)
                    webViewDb.clearHttpAuthUsernamePassword()
                    webViewDb.clearFormData()

                    // 3. 异步清除 Cookies，严格等待 removeAllCookies 完成回调并刷盘后再删除目录与返回状态
                    // 注意：Android SDK 文档规定 removeAllCookies 回调参数仅表示“清理前是否存在 Cookie”，
                    // 无 Cookie 时返回 false 属于正常情况，不能将该参数当作删除失败。
                    val cookieManager = CookieManager.getInstance()
                    cookieManager.removeAllCookies { _ ->
                        try {
                            cookieManager.flush()

                            // 4. 动态清理应用私有目录中的 cache、code_cache 及 app_webview 目录，
                            // 并严格检查每一步 deleteRecursively() 返回值
                            var allDirsCleaned = true
                            context.cacheDir?.listFiles()?.forEach { child ->
                                if (!child.deleteRecursively()) {
                                    allDirsCleaned = false
                                }
                            }
                            context.codeCacheDir?.listFiles()?.forEach { child ->
                                if (!child.deleteRecursively()) {
                                    allDirsCleaned = false
                                }
                            }
                            val dataDir = context.applicationInfo.dataDir
                            if (dataDir != null) {
                                val appWebviewDir = File(dataDir, "app_webview")
                                if (appWebviewDir.exists() && !appWebviewDir.deleteRecursively()) {
                                    allDirsCleaned = false
                                }
                            }

                            replySuccess(allDirsCleaned)
                        } catch (e: Exception) {
                            replyError("CLEAN_FAILED", e.localizedMessage)
                        }
                    }
                } catch (e: Exception) {
                    replyError("CLEAN_FAILED", e.localizedMessage)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
