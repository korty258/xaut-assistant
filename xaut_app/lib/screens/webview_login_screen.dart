import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart' as af;
import 'package:webview_windows/webview_windows.dart' as win;
import 'webview/webview_constants.dart';
import 'webview/webview_platform_adapter.dart';
import 'webview/webview_sync_coordinator.dart';
import 'webview/webview_nav_bar.dart';
import 'webview/webview_bottom_bar.dart';

/// 强智教务系统 WebView 认证与跨模块同步页面
class WebViewLoginScreen extends StatefulWidget {
  const WebViewLoginScreen({super.key});

  /// 校验目标域名是否属于西安理工大学校内合法域名且强制全链路 HTTPS 加密（防钓鱼、防窃听与防明文降级）
  static bool isAllowedUrl(String url) => WebViewPlatformAdapter.isAllowedUrl(url);

  @override
  State<WebViewLoginScreen> createState() => _WebViewLoginScreenState();
}

class _WebViewLoginScreenState extends State<WebViewLoginScreen> {
  late final WebViewPlatformAdapter _adapter;
  late final WebViewSyncCoordinator _coordinator;

  String? _syncStatusMessage;

  @override
  void initState() {
    super.initState();
    _adapter = WebViewPlatformAdapter(
      onBlockedUrl: _showBlockedUrlDialog,
      onPageLoadFinished: () {
        _coordinator.tryCaptureWeekInfoSilently();
      },
    );

    _coordinator = WebViewSyncCoordinator(
      getContext: () => context,
      adapter: _adapter,
      onStateChanged: (syncing, message) {
        if (mounted) {
          setState(() {
            _syncStatusMessage = message;
          });
        }
      },
    );

    _initAdapter();
  }

  Future<void> _initAdapter() async {
    try {
      await _adapter.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('WebView 初始化失败: $e')),
        );
      }
    }
  }

  void _showBlockedUrlDialog(String url) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.security_rounded, color: Colors.red, size: 36),
        title: const Text('非校内域名或非 HTTPS 请求已拦截'),
        content: Text(
          '金花助手已阻止非安全或非校内请求：\n\n$url\n\n'
          '为了保障您的学号、密码与隐私安全，本软件强制要求全链路 HTTPS 加密通信并内置防钓鱼白名单，严格禁止在内嵌浏览器中跳转至非 HTTPS 协议或西安理工大学以外的校外网站。',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleClearCookies() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.cleaning_services_rounded, color: Colors.orange, size: 36),
        title: const Text('清理登录 Cookie'),
        content: const Text(
          '这将清除内嵌浏览器中缓存的教务系统登录会话（Cookie），重置回未登录状态。适用于在公共设备上使用完毕后安全注销。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('确定清理')),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _adapter.clearCookiesAndCache();
        await _adapter.navigateTo(WebViewConstants.defaultUrl);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已清除浏览器登录会话 Cookie，已重置至统一认证页面')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('清理 Cookie 失败: $e')),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _coordinator.dispose();
    _adapter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _adapter.isInitializedNotifier,
        _adapter.isLoadingNotifier,
        _coordinator.isSyncingNotifier,
      ]),
      builder: (context, _) {
        final isBusy = _adapter.isLoading || _coordinator.isSyncing;
        return ValueListenableBuilder<String>(
          valueListenable: _adapter.currentUrlNotifier,
          builder: (context, currentUrl, _) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('强智教务登录与同步', style: TextStyle(fontSize: 16)),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(4.0),
                  child: isBusy
                      ? const LinearProgressIndicator()
                      : const SizedBox(height: 4.0),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: '刷新页面',
                    onPressed: () => _adapter.reload(),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: '更多安全操作',
                    onSelected: (val) {
                      if (val == 'clear_cookies') {
                        _handleClearCookies();
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'clear_cookies',
                        child: Row(
                          children: [
                            Icon(Icons.cleaning_services_rounded, size: 18),
                            SizedBox(width: 8),
                            Text('清除登录会话 Cookie'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              body: Column(
                children: [
                  // 1. 顶部快捷跳转与地址栏
                  WebViewNavBar(
                    currentUrl: currentUrl,
                    onNavigate: (url) => _adapter.navigateTo(url),
                  ),

                  // 2. 双端 WebView 渲染容器
                  Expanded(
                    child: !_adapter.isInitialized
                        ? const Center(child: CircularProgressIndicator())
                        : _adapter.isWindows
                            ? win.Webview(_adapter.winController)
                            : af.WebViewWidget(controller: _adapter.mobileController),
                  ),

                  // 3. 底部全异步同步操作条 (状态独立解耦)
                  WebViewBottomBar(
                    currentUrl: currentUrl,
                    isInitialized: _adapter.isInitialized,
                    isSyncing: _coordinator.isSyncing,
                    statusMessage: _syncStatusMessage,
                    onSyncAll: () => _coordinator.syncAll(),
                    onSyncCurrentPage: () => _coordinator.syncCurrentPage(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
