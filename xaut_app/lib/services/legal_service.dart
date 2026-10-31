import 'dart:io' show Directory, Platform;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 法律门禁与用户授权状态服务
///
/// 遵循《个人信息保护法》与《民法典》关于知情同意与格式条款提示的要求。
/// 文本内容与 assets/legal/*.md 严格对应。
class LegalService {
  /// 当前合规文本版本。当协议有实质性变更时必须递增此常量，
  /// 系统检测到本地记录与该版本不一致时会自动重新唤起同意页面。
  static const String currentVersion = '2026-10-31.v2';

  /// 注册第三方开源许可证，使 Flutter showLicensePage 能完整展示 Dawn-Course、NJUST-JWC-Enhance 等致谢
  static void registerCustomLicenses() {
    LicenseRegistry.addLicense(() async* {
      yield const LicenseEntryWithLineBreaks(
        ['Dawn-Course'],
        'Copyright (C) Dawn-Course Contributors\n\n'
        'Licensed under the GNU General Public License v3.0 (GPL-3.0).\n\n'
        'Reference: Modern mobile course timetable scheduling layout, multi-week layering algorithms, and course card interaction patterns.',
      );
      yield const LicenseEntryWithLineBreaks(
        ['NJUST-JWC-Enhance'],
        'Copyright (c) NJUST-JWC-Enhance Contributors\n\n'
        'Licensed under the MIT License.\n\n'
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

  /// 撤回同意（依据《个人信息保护法》第 15 条赋予的撤回权）
  /// 撤回后物理销毁所有本地业务缓存与授权记录，回归初始未授权状态；
  /// 同时执行防御性加固：清除内嵌 WebView 登录会话 Cookie，杜绝凭据残留。
  static Future<void> revokeAndClearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    // 纵深防御加固：清除 Android/移动端 WebView 登录会话 Cookie 与 Windows 本地缓存
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final cookieManager = WebViewCookieManager();
        await cookieManager.clearCookies();
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        // Windows 桌面端防御：尝试清理本地 AppData 目录下的持久化缓存
        final appData = Platform.environment['APPDATA'];
        if (appData != null && appData.isNotEmpty) {
          final dir = Directory('$appData\\io.github.korty258.jinhua_assistant');
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        }
      }
    } catch (_) {}
  }
}
