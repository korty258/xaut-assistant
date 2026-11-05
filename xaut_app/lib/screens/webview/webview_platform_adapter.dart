import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart' as af;
import 'package:webview_windows/webview_windows.dart' as win;
import 'webview_constants.dart';

/// 跨端 (Android / Windows) WebView 原生适配器与消息桥接通道
class WebViewPlatformAdapter {
  final bool isWindows;
  final ValueNotifier<bool> isInitializedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isLoadingNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<String> currentUrlNotifier = ValueNotifier<String>(WebViewConstants.defaultUrl);

  final void Function(String blockedUrl)? onBlockedUrl;
  final void Function()? onPageLoadFinished;

  final win.WebviewController winController = win.WebviewController();
  late final af.WebViewController mobileController;

  // 跨端消息桥接异步 Completer 调度表
  final Map<String, Completer<dynamic>> _pendingBridgeRequests = {};
  void Function(String message)? _currentProgressHandler;

  StreamSubscription<String>? _winUrlSub;
  StreamSubscription<win.LoadingState>? _winLoadingSub;
  StreamSubscription<dynamic>? _winMessageSub;

  WebViewPlatformAdapter({
    this.onBlockedUrl,
    this.onPageLoadFinished,
  }) : isWindows = !kIsWeb && Platform.isWindows;

  bool get isInitialized => isInitializedNotifier.value;
  bool get isLoading => isLoadingNotifier.value;
  String get currentUrl => currentUrlNotifier.value;

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

  /// 初始化双端控制器
  Future<void> initialize() async {
    if (isWindows) {
      await _initWindows();
    } else {
      _initMobile();
    }
  }

  Future<void> _initWindows() async {
    await winController.initialize();

    _winUrlSub = winController.url.listen((url) {
      if (!isAllowedUrl(url)) {
        winController.stop();
        onBlockedUrl?.call(url);
        winController.loadUrl(WebViewConstants.defaultUrl);
        return;
      }
      currentUrlNotifier.value = url;
    });

    _winLoadingSub = winController.loadingState.listen((state) {
      final nowLoading = state == win.LoadingState.loading;
      isLoadingNotifier.value = nowLoading;
      if (!nowLoading) {
        onPageLoadFinished?.call();
      }
    });

    // Windows WebView2 原生消息监听
    _winMessageSub = winController.webMessage.listen((dynamic rawMsg) {
      _handleIncomingBridgeMessage(rawMsg);
    });

    await winController.loadUrl(WebViewConstants.defaultUrl);
    isInitializedNotifier.value = true;
  }

  void _initMobile() {
    mobileController = af.WebViewController()
      ..setJavaScriptMode(af.JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'JinhuaBridge',
        onMessageReceived: (af.JavaScriptMessage msg) {
          _handleIncomingBridgeMessage(msg.message);
        },
      )
      ..setNavigationDelegate(
        af.NavigationDelegate(
          onNavigationRequest: (request) {
            if (isAllowedUrl(request.url)) {
              return af.NavigationDecision.navigate;
            }
            onBlockedUrl?.call(request.url);
            return af.NavigationDecision.prevent;
          },
          onPageStarted: (url) {
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
      )
      ..loadRequest(Uri.parse(WebViewConstants.defaultUrl));

    isInitializedNotifier.value = true;
  }

  /// 统一处理来自 JS Bridge 的消息分发
  void _handleIncomingBridgeMessage(dynamic rawMsg) {
    if (rawMsg == null) return;

    dynamic parsed = rawMsg;
    if (parsed is String) {
      try {
        parsed = jsonDecode(parsed);
      } catch (_) {
        // 如果是纯文本消息，直接忽略或交由上层
        return;
      }
    }

    if (parsed is Map) {
      final type = parsed['type']?.toString();
      if (type == null) return;

      if (type == 'progress') {
        final message = parsed['message']?.toString() ?? '';
        _currentProgressHandler?.call(message);
        return;
      }

      final completer = _pendingBridgeRequests[type];
      if (completer != null && !completer.isCompleted) {
        final success = parsed['success'] != false;
        if (success) {
          completer.complete(parsed['data'] ?? parsed);
        } else {
          final error = parsed['error']?.toString() ?? '同步脚本执行失败';
          completer.completeError(StateError(error));
        }
        _pendingBridgeRequests.remove(type);
      }
    }
  }

  /// 导航至指定 URL（内置安全拦截）
  Future<void> navigateTo(String url) async {
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

  /// 重新加载当前页面
  Future<void> reload() async {
    if (isWindows) {
      await winController.reload();
    } else {
      await mobileController.reload();
    }
  }

  /// 清除浏览器会话 Cookie 与本地缓存
  Future<void> clearCookiesAndCache() async {
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
    final future = isWindows
        ? winController.executeScript(script)
        : mobileController.runJavaScriptReturningResult(script);
    return await future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException('教务系统响应超时 (30秒)，请检查校园网连接或强智系统运行状态'),
    );
  }

  /// 基于跨端 Bridge 通道执行全异步任务（消除 UI 冻结，支持阶段进度通知）
  Future<dynamic> executeBridgeScript({
    required String script,
    required String expectedType,
    void Function(String message)? onProgress,
    Duration timeout = const Duration(seconds: 35),
  }) async {
    if (!isAllowedUrl(currentUrl) || currentUrl == 'about:blank') {
      throw StateError('当前处于非校内受信任页面 ($currentUrl)，已拒绝执行同步脚本');
    }

    final completer = Completer<dynamic>();
    _pendingBridgeRequests[expectedType] = completer;
    _currentProgressHandler = onProgress;

    try {
      if (isWindows) {
        await winController.executeScript(script);
      } else {
        await mobileController.runJavaScript(script);
      }

      final result = await completer.future.timeout(
        timeout,
        onTimeout: () {
          _pendingBridgeRequests.remove(expectedType);
          throw TimeoutException('教务系统响应超时 (${timeout.inSeconds}秒)，请检查校园网连接或强智系统运行状态');
        },
      );
      return result;
    } catch (e) {
      _pendingBridgeRequests.remove(expectedType);
      rethrow;
    } finally {
      _currentProgressHandler = null;
    }
  }

  void dispose() {
    _winUrlSub?.cancel();
    _winLoadingSub?.cancel();
    _winMessageSub?.cancel();
    for (final completer in _pendingBridgeRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('WebView 已关闭'));
      }
    }
    _pendingBridgeRequests.clear();
    if (isWindows) {
      winController.dispose();
    }
    isInitializedNotifier.dispose();
    isLoadingNotifier.dispose();
    currentUrlNotifier.dispose();
  }
}
