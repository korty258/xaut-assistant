import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xaut_app/screens/webview/webview_constants.dart';
import 'package:xaut_app/screens/webview/webview_platform_adapter.dart';
import 'package:xaut_app/screens/webview/webview_sync_coordinator.dart';
import 'package:xaut_app/screens/webview_login_screen.dart';

class _FakeWebViewPlatformAdapter extends WebViewPlatformAdapter {
  Future<void> Function(_FakeWebViewPlatformAdapter self)? onInitialize;
  Future<void> Function()? onReload;
  Future<void> Function(String url)? onNavigate;
  Future<void> Function()? onClearCookies;

  int initializeCalls = 0;
  int reloadCalls = 0;
  int clearCookiesCalls = 0;
  final List<String> navigatedUrls = [];

  _FakeWebViewPlatformAdapter({
    super.onBlockedUrl,
    super.onPageLoadFinished,
    this.onInitialize,
    this.onReload,
    this.onNavigate,
    this.onClearCookies,
  });

  @override
  Future<void> initialize() async {
    initializeCalls++;
    if (onInitialize != null) {
      await onInitialize!(this);
      return;
    }
    initErrorNotifier.value = null;
    isWebView2Missing = false;
    markInitializedForTest(WebViewConstants.timetableUrl);
  }

  @override
  Future<void> reload() async {
    reloadCalls++;
    if (onReload != null) {
      await onReload!();
    }
  }

  @override
  Future<void> navigateTo(String url) async {
    navigatedUrls.add(url);
    if (onNavigate != null) {
      await onNavigate!(url);
      return;
    }
    currentUrlNotifier.value = url;
  }

  @override
  Future<void> clearCookiesAndCache() async {
    clearCookiesCalls++;
    if (onClearCookies != null) {
      await onClearCookies!();
    }
  }
}

class _FakeWebViewSyncCoordinator extends WebViewSyncCoordinator {
  int syncAllCalls = 0;
  int syncCurrentPageCalls = 0;
  int captureWeekCalls = 0;

  _FakeWebViewSyncCoordinator({
    required super.getContext,
    required super.adapter,
    required super.onStateChanged,
  });

  @override
  Future<void> tryCaptureWeekInfoSilently() async {
    captureWeekCalls++;
  }

  @override
  Future<void> syncAll() async {
    syncAllCalls++;
    isSyncingNotifier.value = true;
    onStateChanged(true, '正在一键同步课表与成绩...');
  }

  @override
  Future<void> syncCurrentPage() async {
    syncCurrentPageCalls++;
    isSyncingNotifier.value = false;
    onStateChanged(false, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<String> copiedClipboardTexts = [];

  setUp(() {
    copiedClipboardTexts.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        final text = args?['text']?.toString();
        if (text != null) copiedClipboardTexts.add(text);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('WebViewLoginScreen Widget Tests', () {
    testWidgets('renders initialized WebView, handles nav/reload/sync callbacks, progress status, and close',
        (tester) async {
      late _FakeWebViewPlatformAdapter adapter;
      late _FakeWebViewSyncCoordinator coordinator;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => WebViewLoginScreen(
                        adapterBuilder: ({required onBlockedUrl, required onPageLoadFinished}) {
                          adapter = _FakeWebViewPlatformAdapter(
                            onBlockedUrl: onBlockedUrl,
                            onPageLoadFinished: onPageLoadFinished,
                          );
                          return adapter;
                        },
                        coordinatorBuilder: ({
                          required getContext,
                          required adapter,
                          required onStateChanged,
                        }) {
                          coordinator = _FakeWebViewSyncCoordinator(
                            getContext: getContext,
                            adapter: adapter,
                            onStateChanged: onStateChanged,
                          );
                          return coordinator;
                        },
                        webViewBodyBuilder: (_, _) => const Center(child: Text('MOCK_WEBVIEW_BODY')),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('OPEN_WEBVIEW'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OPEN_WEBVIEW'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );

      expect(find.text('强智教务登录与同步'), findsOneWidget);
      expect(find.text('MOCK_WEBVIEW_BODY'), findsOneWidget);

      // 页面加载完成回调应触发教学周静默嗅探
      adapter.onPageLoadFinished?.call();
      expect(coordinator.captureWeekCalls, 1);

      // 顶部刷新按钮
      await tester.tap(find.byTooltip('刷新页面'));
      await tester.pump();
      expect(adapter.reloadCalls, 1);

      // 导航栏快捷跳转至成绩查询
      await tester.tap(find.text('成绩查询'));
      await tester.pump();
      expect(adapter.navigatedUrls, contains(WebViewConstants.gradesUrl));
      expect(find.text('同步当前成绩'), findsOneWidget);

      // 点击「同步当前成绩」与「一键同步全部」
      await tester.tap(find.text('同步当前成绩'));
      await tester.pump();
      expect(coordinator.syncCurrentPageCalls, 1);

      await tester.tap(find.text('一键同步全部'));
      await tester.pump();
      expect(coordinator.syncAllCalls, 1);
      expect(find.text('正在一键同步课表与成绩...'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // 点击关闭按钮正常退栈并释放资源
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(find.text('OPEN_WEBVIEW'), findsOneWidget);
      expect(adapter.isDisposed, isTrue);
      expect(coordinator.isDisposed, isTrue);
    });

    testWidgets('shows loading indicator while uninitialized and renders init error view with copy & retry',
        (tester) async {
      late _FakeWebViewPlatformAdapter adapter;
      final initCompleter = Completer<void>();
      bool shouldFail = true;

      await tester.pumpWidget(
        MaterialApp(
          home: WebViewLoginScreen(
            adapterBuilder: ({required onBlockedUrl, required onPageLoadFinished}) {
              adapter = _FakeWebViewPlatformAdapter(
                onBlockedUrl: onBlockedUrl,
                onPageLoadFinished: onPageLoadFinished,
                onInitialize: (self) async {
                  if (shouldFail) {
                    await initCompleter.future;
                    self.isWebView2Missing = true;
                    self.isLoadingNotifier.value = false;
                    self.initErrorNotifier.value = '未检测到 Microsoft Edge WebView2 Runtime';
                    throw StateError('WebView2 missing');
                  } else {
                    self.initErrorNotifier.value = null;
                    self.isWebView2Missing = false;
                    self.markInitializedForTest(WebViewConstants.defaultUrl);
                  }
                },
              );
              return adapter;
            },
            coordinatorBuilder: ({
              required getContext,
              required adapter,
              required onStateChanged,
            }) =>
                _FakeWebViewSyncCoordinator(
              getContext: getContext,
              adapter: adapter,
              onStateChanged: onStateChanged,
            ),
            webViewBodyBuilder: (_, _) => const Text('RECOVERED_BODY'),
          ),
        ),
      );

      // 未完成初始化时显示加载圆圈且刷新按钮禁用
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byTooltip('刷新页面'));
      await tester.pump();
      expect(adapter.reloadCalls, 0);

      // 触发初始化失败 -> 展示 WebView2 缺失错误卡片与 SnackBar
      initCompleter.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('缺少 Microsoft Edge WebView2 运行时'), findsOneWidget);
      expect(find.text('未检测到 Microsoft Edge WebView2 Runtime'), findsOneWidget);
      expect(find.textContaining('WebView 初始化失败'), findsOneWidget);

      // 测试复制两个官方下载链接按钮（先滚动至可见区域）
      await tester.ensureVisible(find.text('复制 WebView2 官方下载链接'));
      await tester.pump();
      await tester.tap(find.text('复制 WebView2 官方下载链接'));
      await tester.pump();
      await tester.ensureVisible(find.text('复制 VC++ 运行库链接'));
      await tester.pump();
      await tester.tap(find.text('复制 VC++ 运行库链接'));
      await tester.pump();
      expect(
        copiedClipboardTexts,
        containsAll([
          'https://developer.microsoft.com/zh-cn/microsoft-edge/webview2/',
          'https://aka.ms/vs/17/release/vc_redist.x64.exe',
        ]),
      );

      // 点击「重新检测并加载」恢复成功
      shouldFail = false;
      await tester.ensureVisible(find.text('重新检测并加载'));
      await tester.pump();
      await tester.tap(find.text('重新检测并加载'));
      await tester.pump();
      expect(find.text('RECOVERED_BODY'), findsOneWidget);
      expect(adapter.initializeCalls, 2);
    });

    testWidgets('displays security dialog on blocked URL and surfaces reload/navigation errors via SnackBar',
        (tester) async {
      late _FakeWebViewPlatformAdapter adapter;

      await tester.pumpWidget(
        MaterialApp(
          home: WebViewLoginScreen(
            adapterBuilder: ({required onBlockedUrl, required onPageLoadFinished}) {
              adapter = _FakeWebViewPlatformAdapter(
                onBlockedUrl: onBlockedUrl,
                onPageLoadFinished: onPageLoadFinished,
                onReload: () async => throw StateError('reload boom'),
                onNavigate: (_) async => throw StateError('nav boom'),
              );
              return adapter;
            },
            coordinatorBuilder: ({
              required getContext,
              required adapter,
              required onStateChanged,
            }) =>
                _FakeWebViewSyncCoordinator(
              getContext: getContext,
              adapter: adapter,
              onStateChanged: onStateChanged,
            ),
            webViewBodyBuilder: (_, _) => const Text('WEBVIEW_READY'),
          ),
        ),
      );
      await tester.pump();

      // 触发非校内域名拦截弹窗
      adapter.onBlockedUrl?.call('http://phishing.example.com/login');
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(find.text('非校内域名或非 HTTPS 请求已拦截'), findsOneWidget);
      expect(find.textContaining('http://phishing.example.com/login'), findsOneWidget);

      await tester.tap(find.text('我知道了'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(find.text('非校内域名或非 HTTPS 请求已拦截'), findsNothing);

      // 触发刷新失败提示
      await tester.tap(find.byTooltip('刷新页面'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(find.textContaining('刷新页面失败'), findsOneWidget);

      // 显式清空前一条 SnackBar 后触发快捷导航失败提示
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold))).clearSnackBars();
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );

      await tester.tap(find.text('考试安排'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(find.textContaining('页面跳转失败'), findsOneWidget);
    });

    testWidgets('handles clear cookies menu cancel, success, failure, and safe dispose guard', (tester) async {
      late _FakeWebViewPlatformAdapter adapter;
      bool failClear = false;

      await tester.pumpWidget(
        MaterialApp(
          home: WebViewLoginScreen(
            adapterBuilder: ({required onBlockedUrl, required onPageLoadFinished}) {
              adapter = _FakeWebViewPlatformAdapter(
                onBlockedUrl: onBlockedUrl,
                onPageLoadFinished: onPageLoadFinished,
                onClearCookies: () async {
                  if (failClear) throw StateError('cookie wipe error');
                },
              );
              return adapter;
            },
            coordinatorBuilder: ({
              required getContext,
              required adapter,
              required onStateChanged,
            }) =>
                _FakeWebViewSyncCoordinator(
              getContext: getContext,
              adapter: adapter,
              onStateChanged: onStateChanged,
            ),
            webViewBodyBuilder: (_, _) => const Text('WEBVIEW_READY'),
          ),
        ),
      );
      await tester.pump();

      // 1. 打开更多菜单 -> 取消清理
      await tester.tap(find.byTooltip('更多安全操作'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      await tester.tap(find.text('清除登录会话 Cookie'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(find.text('清理登录 Cookie'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(adapter.clearCookiesCalls, 0);

      // 2. 确认清理成功 -> 重置至默认认证页并弹出 SnackBar
      await tester.tap(find.byTooltip('更多安全操作'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      await tester.tap(find.text('清除登录会话 Cookie'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      await tester.tap(find.text('确定清理'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(adapter.clearCookiesCalls, 1);
      expect(adapter.navigatedUrls.last, WebViewConstants.defaultUrl);
      expect(find.textContaining('已清除浏览器登录会话 Cookie'), findsOneWidget);

      // 推进虚拟时钟清理上一条 SnackBar
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );

      // 3. 清理失败 -> 弹出失败 SnackBar
      failClear = true;
      await tester.tap(find.byTooltip('更多安全操作'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      await tester.tap(find.text('清除登录会话 Cookie'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      await tester.tap(find.text('确定清理'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(adapter.clearCookiesCalls, 2);
      expect(find.textContaining('清理 Cookie 失败'), findsOneWidget);
    });
  });
}
