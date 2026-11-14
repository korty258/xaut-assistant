import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        unawaited(_coordinator.tryCaptureWeekInfoSilently());
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

    unawaited(_initAdapter());
  }

  Future<void> _initAdapter() async {
    try {
      await _adapter.initialize();
      if (mounted) setState(() {});
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('WebView 初始化失败: $e')),
        );
      }
    }
  }

  void _showBlockedUrlDialog(String url) {
    if (!mounted) return;
    unawaited(
      showDialog<void>(
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
        if (_adapter.isInitialized) {
          await _adapter.navigateTo(WebViewConstants.defaultUrl);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已清除浏览器登录会话 Cookie，已重置至统一认证页面')),
          );
        }
      } on Object catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('清理 Cookie 失败: $e')),
          );
        }
      }
    }
  }

  Future<void> _handleReload() async {
    if (!_adapter.isInitialized) return;
    try {
      await _adapter.reload();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('刷新页面失败: $e')),
        );
      }
    }
  }

  Future<void> _handleNavigate(String url) async {
    if (!_adapter.isInitialized) return;
    try {
      await _adapter.navigateTo(url);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('页面跳转失败: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _adapter.dispose();
    _coordinator.dispose();
    super.dispose();
  }

  static const String _webView2DownloadUrl =
      'https://developer.microsoft.com/zh-cn/microsoft-edge/webview2/';
  static const String _vcRedistDownloadUrl =
      'https://aka.ms/vs/17/release/vc_redist.x64.exe';

  Widget _buildInitErrorView(String errorMsg) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            elevation: 0,
            color: colorScheme.errorContainer.withValues(alpha: 0.25),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colorScheme.error.withValues(alpha: 0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.extension_off_rounded,
                    size: 52,
                    color: colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _adapter.isWebView2Missing
                        ? '缺少 Microsoft Edge WebView2 运行时'
                        : '内置浏览器组件初始化失败',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    errorMsg,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Windows 桌面端运行环境说明：',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '1. Microsoft Edge WebView2 Runtime（常青版）：Windows 11 默认自带，若精简版或旧版 Windows 10 缺失，请下载并安装官方常青引导程序。\n'
                          '2. Microsoft Visual C++ 2015–2022 Redistributable (x64)：C++ 原生宿主运行库（绿色版已随包附带核心 DLL）。',
                          style: TextStyle(fontSize: 13, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('复制 WebView2 官方下载链接'),
                        onPressed: () async {
                          await Clipboard.setData(
                            const ClipboardData(text: _webView2DownloadUrl),
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  '已复制 WebView2 官方下载链接，请粘贴到系统浏览器中下载安装',
                                ),
                              ),
                            );
                          }
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('复制 VC++ 运行库链接'),
                        onPressed: () async {
                          await Clipboard.setData(
                            const ClipboardData(text: _vcRedistDownloadUrl),
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  '已复制 VC++ x64 运行库官方下载链接，请粘贴到浏览器下载安装',
                                ),
                              ),
                            );
                          }
                        },
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('重新检测并加载'),
                        onPressed: _initAdapter,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _adapter.isInitializedNotifier,
        _adapter.isLoadingNotifier,
        _adapter.initErrorNotifier,
        _coordinator.isSyncingNotifier,
      ]),
      builder: (context, _) {
        final isBusy = _adapter.isLoading || _coordinator.isSyncing;
        final initError = _adapter.initErrorNotifier.value;
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
                    onPressed: _adapter.isInitialized
                        ? () => unawaited(_handleReload())
                        : null,
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: '更多安全操作',
                    onSelected: (val) {
                      if (val == 'clear_cookies') {
                        unawaited(_handleClearCookies());
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
                    isInitialized: _adapter.isInitialized,
                    onNavigate: (url) => unawaited(_handleNavigate(url)),
                  ),

                  // 2. 双端 WebView 渲染容器
                  Expanded(
                    child: initError != null
                        ? _buildInitErrorView(initError)
                        : !_adapter.isInitialized
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
