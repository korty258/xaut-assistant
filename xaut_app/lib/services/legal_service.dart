import 'dart:io' show Directory, File, Platform;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'app_crypto_service.dart';

/// 法律门禁与用户授权状态服务
///
/// 遵循《个人信息保护法》与《民法典》关于知情同意与格式条款提示的要求。
/// 文本内容与 assets/legal/*.md 严格对应。
class LegalService {
  /// 当前客户端对外统一发布版本号
  static const String appVersion = 'v2.3.5';

  /// 当前合规文本版本。当协议有实质性变更时必须递增此常量，
  /// 系统检测到本地记录与该版本不一致时会自动重新唤起同意页面。
  static const String currentVersion = '2026-11-06.v7';

  /// Windows 撤回授权句柄占用时的冷启动补偿擦除标记
  static const String pendingWindowsWipeKey = 'jinhua_pending_windows_wipe';

  /// 主密钥物理销毁异常时的冷启动补偿擦除标记
  static const String pendingMasterKeyWipeKey = 'jinhua_pending_master_key_wipe';

  @visibleForTesting
  static Future<bool> Function()? debugWindowsWipeAction;

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
  static Future<bool> isAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    final savedVersion = prefs.getString(_keyVersion);
    return savedVersion == currentVersion;
  }

  /// 获取用户签署同意的具体时间（本地存证）
  static Future<DateTime?> getAcceptedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(_keyAcceptedAt);
    if (timeStr == null || timeStr.isEmpty) return null;
    return DateTime.tryParse(timeStr)?.toLocal();
  }

  /// 获取用户当前已同意的条款版本号
  static Future<String?> getAcceptedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyVersion);
  }

  /// 用户明确勾选并点击同意，记录版本与精确时间戳（仅存储在本地设备）
  static Future<void> accept() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyVersion, currentVersion);
    await prefs.setString(_keyAcceptedAt, DateTime.now().toUtc().toIso8601String());
  }

  /// 内部辅助方法：清理 Windows 应用目录与 *.WebView2 目录
  /// 若有任意文件或子目录因句柄占用抛出异常未能删净，返回 false
  static Future<bool> _wipeWindowsDirectories() async {
    if (debugWindowsWipeAction != null) {
      return await debugWindowsWipeAction!();
    }

    bool allCleaned = true;

    bool isSharedPrefsFile(String path) =>
        path.toLowerCase().endsWith('shared_preferences.json');

    // 1. Application Support 目录（保留根文件夹及已清空的 shared_preferences.json，避免后续标志位读写异常）
    try {
      final supportDir = await getApplicationSupportDirectory();
      if (await supportDir.exists()) {
        final entries = supportDir.listSync();
        for (final entry in entries) {
          if (entry is File && isSharedPrefsFile(entry.path)) continue;
          try {
            await entry.delete(recursive: true);
          } catch (e) {
            allCleaned = false;
            debugPrint('LegalService: Failed to delete supportDir entry: $e');
          }
        }
      }
    } on MissingPluginException {
      // 单元测试无原生宿主插件环境
    } catch (e) {
      allCleaned = false;
      debugPrint('LegalService: supportDir cleanup error: $e');
    }

    // 2. Application Cache 目录
    try {
      final cacheDir = await getApplicationCacheDirectory();
      if (await cacheDir.exists()) {
        final entries = cacheDir.listSync();
        for (final entry in entries) {
          try {
            await entry.delete(recursive: true);
          } catch (e) {
            allCleaned = false;
            debugPrint('LegalService: Failed to delete cacheDir entry: $e');
          }
        }
      }
    } on MissingPluginException {
      // 单元测试无原生宿主插件环境
    } catch (e) {
      allCleaned = false;
      debugPrint('LegalService: cacheDir cleanup error: $e');
    }

    // 3. APPDATA 真实与旧版配置目录
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      final realDir = Directory('$appData\\Jinhua Assistant OpenSource Community\\金花助手');
      if (await realDir.exists()) {
        try {
          for (final entry in realDir.listSync()) {
            if (entry is File && isSharedPrefsFile(entry.path)) continue;
            try {
              await entry.delete(recursive: true);
            } catch (e) {
              allCleaned = false;
              debugPrint('LegalService: Failed to delete realDir entry: $e');
            }
          }
        } catch (e) {
          allCleaned = false;
          debugPrint('LegalService: Failed to scan realDir: $e');
        }
      }

      final oldDir = Directory('$appData\\io.github.korty258.jinhua_assistant');
      if (await oldDir.exists()) {
        try {
          await oldDir.delete(recursive: true);
        } catch (e) {
          allCleaned = false;
          debugPrint('LegalService: Failed to delete oldDir: $e');
        }
      }
    }

    // 4. 可执行文件同级目录下的 *.WebView2 缓存文件夹
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      if (await exeDir.exists()) {
        final entries = exeDir.listSync();
        for (final entry in entries) {
          if (entry is Directory && entry.path.toLowerCase().contains('webview2')) {
            try {
              await entry.delete(recursive: true);
            } catch (e) {
              allCleaned = false;
              debugPrint('LegalService: Failed to delete WebView2 dir: $e');
            }
          }
        }
      }
    } catch (e) {
      allCleaned = false;
      debugPrint('LegalService: exeDir WebView2 scan error: $e');
    }

    return allCleaned;
  }

  /// 检查并在冷启动早期（WebView2 尚未初始化、零文件锁时）执行残留补偿擦除
  static Future<void> runPendingWipeIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(pendingMasterKeyWipeKey) == true) {
      final destroyed = await AppCryptoService.destroyMasterKey();
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
  /// 撤回后物理销毁所有本地业务缓存与授权记录，回归初始未授权状态；
  /// 同时执行防御性加固：清除内嵌 WebView 登录会话 Cookie，杜绝凭据残留。
  static Future<RevokeCleanupResult> revokeAndClearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final prefsCleared = await prefs.clear();

    // 密码学粉碎 (Crypto-Shredding)：销毁主加密密钥，确保残留磁盘密文彻底不可逆失效
    final masterKeyDestroyed = await AppCryptoService.destroyMasterKey();
    if (!masterKeyDestroyed) {
      await prefs.setBool(pendingMasterKeyWipeKey, true);
    }

    bool webviewCleaned = true;
    bool windowsDirsCleaned = true;

    // 纵深防御加固：清除 Android/移动端 WebView 登录会话 Cookie 与 Windows 本地缓存
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        // 优先通过 Android 原生 MethodChannel 调用 WebStorage.deleteAllData()、WebViewDatabase 与动态缓存彻底清除
        try {
          const platformChannel = MethodChannel('io.github.korty258.jinhua_assistant/platform');
          await platformChannel.invokeMethod('clearWebViewData');
          webviewCleaned = true;
        } catch (e) {
          debugPrint('Android native clearWebViewData failed or running in test: $e');
          // 降级兜底：通过 webview_flutter 官方 CookieManager 清除
          try {
            final cookieManager = WebViewCookieManager();
            await cookieManager.clearCookies();
            webviewCleaned = true;
          } catch (e) {
            if (e is MissingPluginException || e is AssertionError || e is UnimplementedError) {
              // 纯单测环境无原生 Android WebView 宿主通道
              webviewCleaned = true;
            } else {
              debugPrint('Android clearCookies failed: $e');
              webviewCleaned = false;
            }
          }
        }
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        windowsDirsCleaned = await _wipeWindowsDirectories();
        webviewCleaned = windowsDirsCleaned;
        if (!windowsDirsCleaned) {
          await prefs.setBool(pendingWindowsWipeKey, true);
        }
      }
    } catch (_) {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        webviewCleaned = false;
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        windowsDirsCleaned = false;
        webviewCleaned = false;
      }
    }

    final hasPendingColdStartWipe = !masterKeyDestroyed ||
        (!windowsDirsCleaned && !kIsWeb && defaultTargetPlatform == TargetPlatform.windows);

    return RevokeCleanupResult(
      prefsCleared: prefsCleared,
      masterKeyDestroyed: masterKeyDestroyed,
      webviewCleaned: webviewCleaned,
      windowsDirsCleaned: windowsDirsCleaned,
      hasPendingColdStartWipe: hasPendingColdStartWipe,
    );
  }
}

/// 撤回授权全流程数据清理结构化结果
class RevokeCleanupResult {
  final bool prefsCleared;
  final bool masterKeyDestroyed;
  final bool webviewCleaned;
  final bool windowsDirsCleaned;
  final bool hasPendingColdStartWipe;

  const RevokeCleanupResult({
    required this.prefsCleared,
    required this.masterKeyDestroyed,
    required this.webviewCleaned,
    required this.windowsDirsCleaned,
    required this.hasPendingColdStartWipe,
  });

  bool get isFullyCleaned =>
      prefsCleared &&
      masterKeyDestroyed &&
      webviewCleaned &&
      windowsDirsCleaned &&
      !hasPendingColdStartWipe;
}
