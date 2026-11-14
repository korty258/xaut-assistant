import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart' as af;
import 'package:webview_windows/webview_windows.dart' as win;
import 'webview_constants.dart';

class _PendingBridgeRequest {
  final String requestId;
  final String expectedType;
  final Completer<dynamic> completer;
  final void Function(String message)? onProgress;

  _PendingBridgeRequest({
    required this.requestId,
    required this.expectedType,
    required this.completer,
    this.onProgress,
  });
}

/// 跨端 (Android / Windows) WebView 原生适配器与消息桥接通道
class WebViewPlatformAdapter {
  final bool isWindows;
  final ValueNotifier<bool> isInitializedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isLoadingNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<String> currentUrlNotifier = ValueNotifier<String>(WebViewConstants.defaultUrl);
  final ValueNotifier<String?> initErrorNotifier = ValueNotifier<String?>(null);
  bool isWebView2Missing = false;

  final void Function(String blockedUrl)? onBlockedUrl;
  final void Function()? onPageLoadFinished;

  final win.WebviewController winController = win.WebviewController();
  late final af.WebViewController mobileController;

  // 跨端消息桥接异步 Completer 调度表 (以 requestId 为主键严格隔离)
  final Map<String, _PendingBridgeRequest> _pendingBridgeRequests = {};
  int _requestSeq = 0;

  StreamSubscription<String>? _winUrlSub;
  StreamSubscription<win.LoadingState>? _winLoadingSub;
  StreamSubscription<dynamic>? _winMessageSub;

  @visibleForTesting
  Future<void> Function(String script)? debugRawJsExecutor;

  WebViewPlatformAdapter({
    this.onBlockedUrl,
    this.onPageLoadFinished,
  }) : isWindows = !kIsWeb && Platform.isWindows;

  bool get isInitialized => isInitializedNotifier.value;
  bool get isLoading => isLoadingNotifier.value;
  String get currentUrl => currentUrlNotifier.value;

  /// 生成全局递增唯一的同步请求 ID
  String nextRequestId([String prefix = 'sync']) {
    final nowMicros = DateTime.now().microsecondsSinceEpoch;
    return '${prefix}_${nowMicros}_${++_requestSeq}';
  }

  /// 去除 URL 中的 hash 锚点片段并规范化
  static String _stripUrlFragment(String url) {
    final hashIndex = url.indexOf('#');
    final clean = hashIndex != -1 ? url.substring(0, hashIndex) : url;
    return clean.trim();
  }

  /// 校验目标域名是否属于西安理工大学校内合法域名且强制全链路 HTTPS 加密（防钓鱼、防窃听与防明文降级）
  static bool isAllowedUrl(String url) {
    final trimmed = url.trim();
    if (trimmed == 'about:blank') return true;
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;
    // 强制 HTTPS 传输：Windows 桌面端无 usesCleartextTraffic 等价隔离，需在应用层严格拦截明文 HTTP
    if (uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host == 'xaut.edu.cn' || host.endsWith('.xaut.edu.cn');
  }

  /// 处理 Windows WebView 加载状态变更：同地址刷新开始新一轮文档加载时主动取消旧 Bridge 任务
  @visibleForTesting
  void handleWindowsLoadingStateChange(bool nowLoading) {
    final wasLoading = isLoadingNotifier.value;
    isLoadingNotifier.value = nowLoading;
    if (!wasLoading && nowLoading && isInitializedNotifier.value) {
      cancelActiveBridgeTasks('页面开始重新加载，已取消正在进行的同步任务');
    }
    if (!nowLoading) {
      onPageLoadFinished?.call();
    }
  }

  /// 初始化双端控制器
  Future<void> initialize() async {
    initErrorNotifier.value = null;
    isWebView2Missing = false;
    isLoadingNotifier.value = true;
    if (isWindows) {
      await _initWindows();
    } else {
      _initMobile();
    }
  }

  Future<void> _initWindows() async {
    try {
      final webViewVersion = await win.WebviewController.getWebViewVersion();
      if (webViewVersion == null || webViewVersion.trim().isEmpty) {
        isWebView2Missing = true;
        isLoadingNotifier.value = false;
        const msg =
            '未检测到 Microsoft Edge WebView2 Runtime（常青版运行时）。Windows 桌面端需要该系统级组件才能加载教务登录页面。';
        initErrorNotifier.value = msg;
        throw StateError(msg);
      }

      if (!winController.value.isInitialized) {
        await winController.initialize();
      }
    } catch (e) {
      isLoadingNotifier.value = false;
      final errText = e.toString();
      if (errText.contains('environment_creation_failed') ||
          errText.toLowerCase().contains('webview2')) {
        isWebView2Missing = true;
      }
      initErrorNotifier.value ??= '初始化内置浏览器组件失败：$e';
      rethrow;
    }

    await _winUrlSub?.cancel();
    _winUrlSub = winController.url.listen((url) {
      if (!isAllowedUrl(url)) {
        cancelActiveBridgeTasks('检测到非校内链接，已取消正在进行的同步任务');
        unawaited(winController.stop());
        onBlockedUrl?.call(url);
        unawaited(winController.loadUrl(WebViewConstants.defaultUrl));
        return;
      }
      final prevUrl = currentUrlNotifier.value;
      currentUrlNotifier.value = url;
      if (isInitializedNotifier.value && _stripUrlFragment(prevUrl) != _stripUrlFragment(url)) {
        cancelActiveBridgeTasks('页面已跳转至新地址，已取消正在进行的同步任务');
      }
    });

    await _winLoadingSub?.cancel();
    _winLoadingSub = winController.loadingState.listen((state) {
      handleWindowsLoadingStateChange(state == win.LoadingState.loading);
    });

    // Windows WebView2 原生消息监听
    await _winMessageSub?.cancel();
    _winMessageSub = winController.webMessage.listen((dynamic rawMsg) {
      _handleIncomingBridgeMessage(rawMsg);
    });

    await winController.loadUrl(WebViewConstants.defaultUrl);
    isInitializedNotifier.value = true;
  }

  void _initMobile() {
    final ctrl = af.WebViewController();
    unawaited(ctrl.setJavaScriptMode(af.JavaScriptMode.unrestricted));
    unawaited(
      ctrl.addJavaScriptChannel(
        'JinhuaBridge',
        onMessageReceived: (af.JavaScriptMessage msg) {
          _handleIncomingBridgeMessage(msg.message);
        },
      ),
    );
    unawaited(
      ctrl.setNavigationDelegate(
        af.NavigationDelegate(
          onNavigationRequest: (request) {
            if (isAllowedUrl(request.url)) {
              return af.NavigationDecision.navigate;
            }
            cancelActiveBridgeTasks('检测到非校内链接，已取消正在进行的同步任务');
            onBlockedUrl?.call(request.url);
            return af.NavigationDecision.prevent;
          },
          onPageStarted: (url) {
            cancelActiveBridgeTasks('页面开始加载新地址，已取消正在进行的同步任务');
            isLoadingNotifier.value = true;
            currentUrlNotifier.value = url;
          },
          onPageFinished: (url) {
            isLoadingNotifier.value = false;
            currentUrlNotifier.value = url;
            onPageLoadFinished?.call();
          },
          onWebResourceError: (err) {
            isLoadingNotifier.value = false;
          },
        ),
      ),
    );
    unawaited(ctrl.loadRequest(Uri.parse(WebViewConstants.defaultUrl)));
    mobileController = ctrl;

    isInitializedNotifier.value = true;
  }

  /// 统一处理来自 JS Bridge 的消息分发（基于 requestId 精准路由与迟到响应彻底丢弃）
  void _handleIncomingBridgeMessage(dynamic rawMsg) {
    if (rawMsg == null) return;

    dynamic parsed = rawMsg;
    if (parsed is String) {
      try {
        parsed = jsonDecode(parsed);
      } on Object catch (_) {
        return;
      }
    }

    if (parsed is Map) {
      final requestId = parsed['requestId']?.toString();
      if (requestId == null || !_pendingBridgeRequests.containsKey(requestId)) {
        // 请求 ID 为空或请求已被超时/取消移除：直接忽略迟到响应，彻底阻断污染
        return;
      }

      final pending = _pendingBridgeRequests[requestId]!;
      final type = parsed['type']?.toString();
      if (type == null) return;

      if (type == 'progress') {
        final message = parsed['message']?.toString() ?? '';
        pending.onProgress?.call(message);
        return;
      }

      if (type == 'error' || parsed['success'] == false) {
        _pendingBridgeRequests.remove(requestId);
        final error = parsed['error']?.toString() ?? '同步脚本执行失败';
        if (!pending.completer.isCompleted) {
          pending.completer.completeError(StateError(error));
        }
        return;
      }

      if (type == pending.expectedType) {
        _pendingBridgeRequests.remove(requestId);
        final dataPayload = parsed['data'] ?? parsed;
        final payloadStr = dataPayload is String ? dataPayload : jsonEncode(dataPayload);
        if (!pending.completer.isCompleted) {
          pending.completer.complete(payloadStr);
        }
      }
    }
  }

  @visibleForTesting
  void handleIncomingBridgeMessageForTest(String rawMessage) {
    _handleIncomingBridgeMessage(rawMessage);
  }

  @visibleForTesting
  void markInitializedForTest([String testUrl = 'https://jwgl.xaut.edu.cn/jsxsd/']) {
    isInitializedNotifier.value = true;
    currentUrlNotifier.value = testUrl;
    isLoadingNotifier.value = false;
  }

  @visibleForTesting
  void simulateUrlNavigationForTest(String newUrl) {
    if (!isAllowedUrl(newUrl)) {
      cancelActiveBridgeTasks('检测到非校内链接，已取消正在进行的同步任务');
      onBlockedUrl?.call(newUrl);
      currentUrlNotifier.value = WebViewConstants.defaultUrl;
      return;
    }
    final prevUrl = currentUrlNotifier.value;
    currentUrlNotifier.value = newUrl;
    if (isInitializedNotifier.value && _stripUrlFragment(prevUrl) != _stripUrlFragment(newUrl)) {
      cancelActiveBridgeTasks('页面已跳转至新地址，已取消正在进行的同步任务');
    }
  }

  @visibleForTesting
  List<String> get pendingRequestIdsForTest => _pendingBridgeRequests.keys.toList();

  /// 执行底层原始 JavaScript 代码注入
  Future<void> _evaluateRawJs(String script) async {
    if (debugRawJsExecutor != null) {
      await debugRawJsExecutor!(script);
      return;
    }
    if (isWindows) {
      await winController.executeScript(script);
    } else {
      await mobileController.runJavaScript(script);
    }
  }

  /// 尽力而为通知 JS 运行时中止指定 requestId 任务（吞掉异常不阻塞流程）
  void _abortJsTaskBestEffort(String requestId) {
    try {
      final escapedId = jsonEncode(requestId);
      final abortScript = '(function(){ try { if (window.__jinhuaAbortTask) window.__jinhuaAbortTask($escapedId); } catch(e){} })();';
      unawaited(_evaluateRawJs(abortScript).catchError((_) {}));
    } on Object catch (_) {}
  }

  /// 取消当前所有正在等待的 Bridge 异步任务（页面跳转、刷新、拦截或 dispose 时触发）
  void cancelActiveBridgeTasks([String reason = '页面跳转或重新加载，已取消正在进行的同步任务']) {
    if (_pendingBridgeRequests.isEmpty) return;
    final requests = Map<String, _PendingBridgeRequest>.from(_pendingBridgeRequests);
    _pendingBridgeRequests.clear();
    for (final req in requests.values) {
      if (!req.completer.isCompleted) {
        req.completer.completeError(StateError(reason));
      }
    }
    try {
      const abortAllScript = '(function(){ try { if (window.__jinhuaAbortAllTasks) window.__jinhuaAbortAllTasks(); } catch(e){} })();';
      unawaited(_evaluateRawJs(abortAllScript).catchError((_) {}));
    } on Object catch (_) {}
  }

  /// 导航至指定 URL（内置安全拦截与同步任务取消）
  Future<void> navigateTo(String url) async {
    cancelActiveBridgeTasks('页面正在跳转至新地址，已取消正在进行的同步任务');
    if (!isAllowedUrl(url)) {
      onBlockedUrl?.call(url);
      return;
    }
    if (isWindows) {
      await winController.loadUrl(url);
    } else {
      await mobileController.loadRequest(Uri.parse(url));
    }
  }

  /// 重新加载当前页面（内置同步任务取消）
  Future<void> reload() async {
    cancelActiveBridgeTasks('页面正在重新加载，已取消正在进行的同步任务');
    if (isWindows) {
      await winController.reload();
    } else {
      await mobileController.reload();
    }
  }

  /// 清除浏览器会话 Cookie 与本地缓存
  Future<void> clearCookiesAndCache() async {
    cancelActiveBridgeTasks('正在清除登录会话，已取消正在进行的同步任务');
    if (isWindows) {
      if (winController.value.isInitialized) {
        await winController.clearCookies();
        await winController.clearCache();
      }
    } else {
      await af.WebViewCookieManager().clearCookies();
    }
  }

  /// 安全执行同步 JS 表达式（用于轻量级无副作用的 DOM 读取，30秒超时）
  Future<dynamic> executeScript(String script) async {
    if (!isAllowedUrl(currentUrl) || currentUrl == 'about:blank') {
      throw StateError('当前处于非校内受信任页面 ($currentUrl)，已拒绝执行脚本');
    }
    if (debugRawJsExecutor != null) {
      return await debugRawJsExecutor!(script);
    }
    final future = isWindows
        ? winController.executeScript(script)
        : mobileController.runJavaScriptReturningResult(script);
    return await future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException('教务系统响应超时 (30秒)，请检查校园网连接或强智系统运行状态'),
    );
  }

  Future<dynamic> _dispatchAndAwaitBridge(
    String script,
    Future<dynamic> responseFuture,
  ) async {
    await _evaluateRawJs(script);
    return await responseFuture;
  }

  /// 基于跨端 Bridge 通道执行全异步任务（消除 UI 冻结，支持阶段进度通知与 requestId 精确隔离）
  Future<dynamic> executeBridgeScript({
    required String script,
    required String expectedType,
    required String requestId,
    void Function(String message)? onProgress,
    Duration timeout = const Duration(seconds: 35),
  }) async {
    if (!isAllowedUrl(currentUrl) || currentUrl == 'about:blank') {
      throw StateError('当前处于非校内受信任页面 ($currentUrl)，已拒绝执行同步脚本');
    }

    final completer = Completer<dynamic>();
    // 预先挂载静默错误兜底，防止在 _evaluateRawJs 尚未完成时提前触发取消导致 Zone 未捕获错误
    completer.future.ignore();
    _pendingBridgeRequests[requestId] = _PendingBridgeRequest(
      requestId: requestId,
      expectedType: expectedType,
      completer: completer,
      onProgress: onProgress,
    );

    try {
      final result = await _dispatchAndAwaitBridge(script, completer.future).timeout(
        timeout,
        onTimeout: () {
          _pendingBridgeRequests.remove(requestId);
          _abortJsTaskBestEffort(requestId);
          throw TimeoutException('教务系统响应超时，本次同步已停止等待（迟到响应将被忽略），请检查校园网或 VPN 后重试');
        },
      );
      return result;
    } catch (e) {
      _pendingBridgeRequests.remove(requestId);
      rethrow;
    }
  }

  void dispose() {
    cancelActiveBridgeTasks('WebView 已关闭');
    unawaited(_winUrlSub?.cancel());
    unawaited(_winLoadingSub?.cancel());
    unawaited(_winMessageSub?.cancel());
    if (isWindows && winController.value.isInitialized) {
      try {
        unawaited(winController.dispose().catchError((_) {}));
      } on Object catch (_) {}
    }
    isInitializedNotifier.dispose();
    isLoadingNotifier.dispose();
    currentUrlNotifier.dispose();
    initErrorNotifier.dispose();
  }
}
