import 'dart:io' show Directory, File, Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'app_crypto_service.dart';

/// 法律门禁与用户授权状态服务
///
/// 遵循《个人信息保护法》与《民法典》关于知情同意与格式条款提示的要求。
/// 文本内容与 assets/legal/*.md 严格对应。
///
/// 同时支持实例注入（[LegalService.new]）与默认单例静态门面，兼顾业务调用与单测隔离。
class LegalService {
  /// 当前客户端对外统一发布版本号
  static const String appVersion = 'v2.4.0-pre3';

  /// 当前合规文本版本。当协议有实质性变更时必须递增此常量，
  /// 系统检测到本地记录与该版本不一致时会自动重新唤起同意页面。
  static const String currentVersion = '2026-11-06.v7';

  /// Windows 撤回授权句柄占用时的冷启动补偿擦除标记
  static const String pendingWindowsWipeKey = 'jinhua_pending_windows_wipe';

  /// 主密钥物理销毁异常时的冷启动补偿擦除标记
  static const String pendingMasterKeyWipeKey = 'jinhua_pending_master_key_wipe';

  static LegalService _instance = LegalService();

  static LegalService get instance => _instance;

  @visibleForTesting
  static set instance(LegalService custom) => _instance = custom;

  LegalService({
    this._crypto,
    Future<bool> Function()? windowsWipeAction,
    Future<bool> Function()? androidWebViewClearAction,
    Future<void> Function()? androidNativeWebViewClearAction,
    Future<bool> Function()? androidNativeWebViewClearBoolAction,
    Future<bool> Function()? androidCookieClearAction,
    Future<bool> Function(SharedPreferences prefs)? prefsClearAction,
    Future<bool> Function(SharedPreferences prefs, String key, bool value)?
        prefsBoolWriter,
  })  : _debugWindowsWipeAction = windowsWipeAction,
        _debugAndroidWebViewClearAction = androidWebViewClearAction,
        _debugAndroidNativeWebViewClearAction = androidNativeWebViewClearAction,
        _debugAndroidNativeWebViewClearBoolAction =
            androidNativeWebViewClearBoolAction,
        _debugAndroidCookieClearAction = androidCookieClearAction,
        _debugPrefsClearAction = prefsClearAction,
        _debugPrefsBoolWriter = prefsBoolWriter;

  final AppCryptoService? _crypto;
  AppCryptoService get _effectiveCrypto => _crypto ?? AppCryptoService.instance;

  Future<bool> Function()? _debugWindowsWipeAction;
  Future<bool> Function()? _debugAndroidWebViewClearAction;
  Future<void> Function()? _debugAndroidNativeWebViewClearAction;
  Future<bool> Function()? _debugAndroidNativeWebViewClearBoolAction;
  Future<bool> Function()? _debugAndroidCookieClearAction;
  Future<bool> Function(SharedPreferences prefs)? _debugPrefsClearAction;
  Future<bool> Function(SharedPreferences prefs, String key, bool value)?
      _debugPrefsBoolWriter;

  @visibleForTesting
  static Future<bool> Function()? get debugWindowsWipeAction =>
      _instance._debugWindowsWipeAction;
  @visibleForTesting
  static set debugWindowsWipeAction(Future<bool> Function()? fn) =>
      _instance._debugWindowsWipeAction = fn;

  @visibleForTesting
  static Future<bool> Function()? get debugAndroidWebViewClearAction =>
      _instance._debugAndroidWebViewClearAction;
  @visibleForTesting
  static set debugAndroidWebViewClearAction(Future<bool> Function()? fn) =>
      _instance._debugAndroidWebViewClearAction = fn;

  @visibleForTesting
  static Future<void> Function()? get debugAndroidNativeWebViewClearAction =>
      _instance._debugAndroidNativeWebViewClearAction;
  @visibleForTesting
  static set debugAndroidNativeWebViewClearAction(Future<void> Function()? fn) =>
      _instance._debugAndroidNativeWebViewClearAction = fn;

  @visibleForTesting
  static Future<bool> Function()? get debugAndroidNativeWebViewClearBoolAction =>
      _instance._debugAndroidNativeWebViewClearBoolAction;
  @visibleForTesting
  static set debugAndroidNativeWebViewClearBoolAction(
          Future<bool> Function()? fn) =>
      _instance._debugAndroidNativeWebViewClearBoolAction = fn;

  @visibleForTesting
  static Future<bool> Function()? get debugAndroidCookieClearAction =>
      _instance._debugAndroidCookieClearAction;
  @visibleForTesting
  static set debugAndroidCookieClearAction(Future<bool> Function()? fn) =>
      _instance._debugAndroidCookieClearAction = fn;

  @visibleForTesting
  static Future<bool> Function(SharedPreferences prefs)?
      get debugPrefsClearAction => _instance._debugPrefsClearAction;
  @visibleForTesting
  static set debugPrefsClearAction(
          Future<bool> Function(SharedPreferences prefs)? fn) =>
      _instance._debugPrefsClearAction = fn;

  @visibleForTesting
  static Future<bool> Function(
    SharedPreferences prefs,
    String key,
    bool value,
  )? get debugPrefsBoolWriter => _instance._debugPrefsBoolWriter;
  @visibleForTesting
  static set debugPrefsBoolWriter(
          Future<bool> Function(SharedPreferences, String, bool)? fn) =>
      _instance._debugPrefsBoolWriter = fn;

  @visibleForTesting
  static void resetForTesting() {
    _instance = LegalService();
  }

  /// 注册第三方开源许可证，使 Flutter showLicensePage 能完整展示 Dawn-Course、NJUST-JWC-Enhance 等致谢
  static void registerCustomLicenses() {
    LicenseRegistry.addLicense(() async* {
      yield const LicenseEntryWithLineBreaks(
        ['Dawn-Course'],
        'Copyright (C) 2021-2026 HF-CYGG & Dawn-Course Contributors\n\n'
        'Licensed under the GNU General Public License v3.0 (GPL-3.0).\n'
        'Repository: https://github.com/HF-CYGG/Dawn-Course\n\n'
        'Reference: Modern mobile course timetable scheduling layout, multi-week layering algorithms, and course card interaction patterns.',
      );
      yield const LicenseEntryWithLineBreaks(
        ['NJUST-JWC-Enhance'],
        'Copyright (c) 2021-2026 NJUST-OpenLib & NJUST-JWC-Enhance Contributors\n\n'
        'Licensed under the MIT License.\n'
        'Repository: https://github.com/NJUST-OpenLib/NJUST-JWC-Enhance\n\n'
        'Reference: QiangZhi Educational Administration System DOM structure parsing, cell text extraction strategies, and teaching week inference algorithms.',
      );
      yield const LicenseEntryWithLineBreaks(
        ['jinhua_assistant'],
        'Copyright (C) 2026 Jinhua Assistant Contributors\n\n'
        'Licensed under the GNU General Public License v3.0 (GPL-3.0).\n\n'
        'Source repository: https://github.com/korty258/xaut-assistant',
      );
    });
  }

  static const String _keyVersion = 'jinhua_legal_terms_version';
  static const String _keyAcceptedAt = 'jinhua_legal_terms_accepted_at';

  /// 检查当前用户是否已同意最新版本的法律与合规条款
  static Future<bool> isAccepted() => _instance.isAcceptedInstance();

  Future<bool> isAcceptedInstance() async {
    final prefs = await SharedPreferences.getInstance();
    final savedVersion = prefs.getString(_keyVersion);
    return savedVersion == currentVersion;
  }

  /// 获取用户签署同意的具体时间（本地存证）
  static Future<DateTime?> getAcceptedAt() => _instance.getAcceptedAtInstance();

  Future<DateTime?> getAcceptedAtInstance() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(_keyAcceptedAt);
    if (timeStr == null || timeStr.isEmpty) return null;
    return DateTime.tryParse(timeStr)?.toLocal();
  }

  /// 获取用户当前已同意的条款版本号
  static Future<String?> getAcceptedVersion() =>
      _instance.getAcceptedVersionInstance();

  Future<String?> getAcceptedVersionInstance() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyVersion);
  }

  /// 用户明确勾选并点击同意，记录版本与精确时间戳（仅存储在本地设备）
  static Future<void> accept() => _instance.acceptInstance();

  Future<void> acceptInstance() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyVersion, currentVersion);
    await prefs.setString(_keyAcceptedAt, DateTime.now().toUtc().toIso8601String());
  }

  Future<bool> _wipeWindowsDirectories() async {
    if (_debugWindowsWipeAction != null) {
      return await _debugWindowsWipeAction!();
    }

    bool allCleaned = true;

    bool isSharedPrefsFile(String path) =>
        path.toLowerCase().endsWith('shared_preferences.json');

    try {
      final supportDir = await getApplicationSupportDirectory();
      if (await supportDir.exists()) {
        final entries = supportDir.listSync();
        for (final entry in entries) {
          if (entry is File && isSharedPrefsFile(entry.path)) continue;
          try {
            await entry.delete(recursive: true);
          } on Object catch (e) {
            allCleaned = false;
            debugPrint('LegalService: Failed to delete supportDir entry: $e');
          }
        }
      }
    } on MissingPluginException {
      // 单元测试无原生宿主插件环境
    } on Object catch (e) {
      allCleaned = false;
      debugPrint('LegalService: supportDir cleanup error: $e');
    }

    try {
      final cacheDir = await getApplicationCacheDirectory();
      if (await cacheDir.exists()) {
        final entries = cacheDir.listSync();
        for (final entry in entries) {
          try {
            await entry.delete(recursive: true);
          } on Object catch (e) {
            allCleaned = false;
            debugPrint('LegalService: Failed to delete cacheDir entry: $e');
          }
        }
      }
    } on MissingPluginException {
      // 单元测试无原生宿主插件环境
    } on Object catch (e) {
      allCleaned = false;
      debugPrint('LegalService: cacheDir cleanup error: $e');
    }

    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      try {
        final realDir =
            Directory('$appData\\Jinhua Assistant OpenSource Community\\金花助手');
        if (await realDir.exists()) {
          for (final entry in realDir.listSync()) {
            if (entry is File && isSharedPrefsFile(entry.path)) continue;
            try {
              await entry.delete(recursive: true);
            } on Object catch (e) {
              allCleaned = false;
              debugPrint('LegalService: Failed to delete realDir entry: $e');
            }
          }
        }
      } on Object catch (e) {
        allCleaned = false;
        debugPrint('LegalService: Failed to scan realDir: $e');
      }

      try {
        final oldDir = Directory('$appData\\io.github.korty258.jinhua_assistant');
        if (await oldDir.exists()) {
          await oldDir.delete(recursive: true);
        }
      } on Object catch (e) {
        allCleaned = false;
        debugPrint('LegalService: Failed to delete oldDir: $e');
      }
    }

    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      if (await exeDir.exists()) {
        final entries = exeDir.listSync();
        for (final entry in entries) {
          if (entry is Directory && entry.path.toLowerCase().contains('webview2')) {
            try {
              await entry.delete(recursive: true);
            } on Object catch (e) {
              allCleaned = false;
              debugPrint('LegalService: Failed to delete WebView2 dir: $e');
            }
          }
        }
      }
    } on Object catch (e) {
      allCleaned = false;
      debugPrint('LegalService: exeDir WebView2 scan error: $e');
    }

    return allCleaned;
  }

  /// 检查并在冷启动早期（WebView2 尚未初始化、零文件锁时）执行残留补偿擦除
  static Future<void> runPendingWipeIfNeeded() =>
      _instance.runPendingWipeIfNeededInstance();

  Future<void> runPendingWipeIfNeededInstance() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(pendingMasterKeyWipeKey) == true) {
      final destroyed = await _effectiveCrypto.destroyMasterKeyInstance();
      if (destroyed) {
        await prefs.remove(pendingMasterKeyWipeKey);
      }
    }
    if (prefs.getBool(pendingWindowsWipeKey) == true) {
      final allCleaned = await _wipeWindowsDirectories();
      if (allCleaned) {
        await prefs.remove(pendingWindowsWipeKey);
      }
    }
  }

  /// 撤回同意（依据《个人信息保护法》第 15 条赋予的撤回权）
  static Future<RevokeCleanupResult> revokeAndClearAll() =>
      _instance.revokeAndClearAllInstance();

  Future<RevokeCleanupResult> revokeAndClearAllInstance() async {
    final prefs = await SharedPreferences.getInstance();
    bool prefsCleared = false;
    try {
      prefsCleared = _debugPrefsClearAction != null
          ? await _debugPrefsClearAction!(prefs)
          : await prefs.clear();
    } on Object catch (_) {
      prefsCleared = false;
    }

    final masterKeyDestroyed = await _effectiveCrypto.destroyMasterKeyInstance();
    bool masterKeyPendingQueued = false;
    if (!masterKeyDestroyed) {
      try {
        masterKeyPendingQueued = _debugPrefsBoolWriter != null
            ? await _debugPrefsBoolWriter!(prefs, pendingMasterKeyWipeKey, true)
            : await prefs.setBool(pendingMasterKeyWipeKey, true);
      } on Object catch (_) {
        masterKeyPendingQueued = false;
      }
    }

    bool webviewCleaned = true;
    bool webviewCookiesClearedOnly = false;
    bool windowsDirsCleaned = true;
    bool windowsPendingQueued = false;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (_debugAndroidWebViewClearAction != null) {
        try {
          webviewCleaned = await _debugAndroidWebViewClearAction!();
        } on Object catch (_) {
          webviewCleaned = false;
        }
      } else {
        try {
          if (_debugAndroidNativeWebViewClearBoolAction != null) {
            webviewCleaned = await _debugAndroidNativeWebViewClearBoolAction!();
          } else if (_debugAndroidNativeWebViewClearAction != null) {
            await _debugAndroidNativeWebViewClearAction!();
            webviewCleaned = true;
          } else {
            const platformChannel =
                MethodChannel('io.github.korty258.jinhua_assistant/platform');
            final nativeResult =
                await platformChannel.invokeMethod<bool>('clearWebViewData');
            webviewCleaned = nativeResult == true;
          }
        } on Object catch (e) {
          debugPrint('Android native clearWebViewData failed: $e');
          webviewCleaned = false;
        }
        if (!webviewCleaned) {
          // 降级兜底：尝试清除 Cookie，严禁将仅清 Cookie 误报为彻底清除全部 WebView 数据
          // 注：WebViewCookieManager.clearCookies() 返回 false 仅代表“清理前本无 Cookie”，真正失败会抛出异常
          try {
            if (_debugAndroidCookieClearAction != null) {
              webviewCookiesClearedOnly = await _debugAndroidCookieClearAction!();
            } else {
              final cookieManager = WebViewCookieManager();
              await cookieManager.clearCookies();
              webviewCookiesClearedOnly = true;
            }
          } on Object catch (cookieErr) {
            debugPrint('Android clearCookies fallback failed: $cookieErr');
            webviewCookiesClearedOnly = false;
          }
        }
      }
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      try {
        windowsDirsCleaned = await _wipeWindowsDirectories();
      } on Object catch (e) {
        debugPrint('LegalService: Windows wipe threw error: $e');
        windowsDirsCleaned = false;
      }
      webviewCleaned = windowsDirsCleaned;
      if (!windowsDirsCleaned) {
        try {
          windowsPendingQueued = _debugPrefsBoolWriter != null
              ? await _debugPrefsBoolWriter!(prefs, pendingWindowsWipeKey, true)
              : await prefs.setBool(pendingWindowsWipeKey, true);
        } on Object catch (_) {
          windowsPendingQueued = false;
        }
      }
    }

    return RevokeCleanupResult(
      prefsCleared: prefsCleared,
      masterKeyDestroyed: masterKeyDestroyed,
      webviewCleaned: webviewCleaned,
      webviewCookiesClearedOnly: webviewCookiesClearedOnly,
      windowsDirsCleaned: windowsDirsCleaned,
      masterKeyPendingQueued: masterKeyPendingQueued,
      windowsPendingQueued: windowsPendingQueued,
    );
  }
}

/// 撤回授权全流程数据清理结构化结果
class RevokeCleanupResult {
  final bool prefsCleared;
  final bool masterKeyDestroyed;
  final bool webviewCleaned;
  final bool webviewCookiesClearedOnly;
  final bool windowsDirsCleaned;
  final bool masterKeyPendingQueued;
  final bool windowsPendingQueued;

  const RevokeCleanupResult({
    required this.prefsCleared,
    required this.masterKeyDestroyed,
    required this.webviewCleaned,
    this.webviewCookiesClearedOnly = false,
    required this.windowsDirsCleaned,
    this.masterKeyPendingQueued = false,
    this.windowsPendingQueued = false,
  });

  bool get hasPendingColdStartWipe =>
      masterKeyPendingQueued || windowsPendingQueued;

  bool get hasUnqueuedFailures =>
      !prefsCleared ||
      (!masterKeyDestroyed && !masterKeyPendingQueued) ||
      (!windowsDirsCleaned && !windowsPendingQueued) ||
      (!webviewCleaned && !windowsPendingQueued);

  bool get isFullyCleaned =>
      prefsCleared &&
      masterKeyDestroyed &&
      webviewCleaned &&
      windowsDirsCleaned &&
      !hasPendingColdStartWipe;

  List<({String label, String status, bool isFailedUnqueued, bool isQueued})>
      describeItems({required bool isWindows}) {
    return [
      (
        label: '主加密密钥',
        status: masterKeyDestroyed
            ? '已销毁'
            : (masterKeyPendingQueued
                ? '已加入待清理队列（下次启动补偿擦除）'
                : '销毁失败（未加入待清理队列）'),
        isFailedUnqueued: !masterKeyDestroyed && !masterKeyPendingQueued,
        isQueued: !masterKeyDestroyed && masterKeyPendingQueued,
      ),
      (
        label: '本地偏好设置 (Preferences)',
        status: prefsCleared ? '已清空' : '清理失败（未加入待清理队列）',
        isFailedUnqueued: !prefsCleared,
        isQueued: false,
      ),
      (
        label: 'WebView 会话与缓存',
        status: isWindows
            ? (windowsDirsCleaned
                ? '已随 Windows 目录清除'
                : (windowsPendingQueued
                    ? '已加入待清理队列（随 Windows 目录于下次启动补偿）'
                    : '清除失败（未加入待清理队列）'))
            : (webviewCleaned
                ? '已清除'
                : (webviewCookiesClearedOnly
                    ? '仅清除了 Cookie，原生 WebStorage 与缓存清理失败（未加入待清理队列）'
                    : '清除失败（未加入待清理队列）')),
        isFailedUnqueued: isWindows
            ? (!windowsDirsCleaned && !windowsPendingQueued)
            : !webviewCleaned,
        isQueued: isWindows && !windowsDirsCleaned && windowsPendingQueued,
      ),
      (
        label: 'Windows 本地缓存目录',
        status: isWindows
            ? (windowsDirsCleaned
                ? '已清除'
                : (windowsPendingQueued
                    ? '已加入待清理队列（下次启动补偿擦除）'
                    : '清除失败（未加入待清理队列）'))
            : '不适用当前平台',
        isFailedUnqueued: isWindows && !windowsDirsCleaned && !windowsPendingQueued,
        isQueued: isWindows && !windowsDirsCleaned && windowsPendingQueued,
      ),
    ];
  }
}
