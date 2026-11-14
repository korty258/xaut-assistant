import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:webview_windows/webview_windows.dart' as win;
import '../utils/date_time_utils.dart';
import 'app_crypto_service.dart';
import 'legal_service.dart';
import 'parser_service.dart';
import 'storage_service.dart';

/// 脱敏同步遥测与运行环境诊断数据快照
class DiagnosticSnapshot {
  final String appVersion;
  final String legalVersion;
  final String platform;
  final String webView2Info;
  final DateTime? coursesSyncTime;
  final DateTime? gradesSyncTime;
  final DateTime? examsSyncTime;
  final DateTime? lastSyncTimestamp;
  final String? triggerMode;
  final int? durationMs;
  final SyncModuleStatus? coursesStatus;
  final SyncModuleStatus? gradesStatus;
  final SyncModuleStatus? examsStatus;
  final String coursesErrorCategory;
  final String gradesErrorCategory;
  final String examsErrorCategory;
  final int pendingMigrationCount;
  final bool hasKeyBlockedMigration;

  const DiagnosticSnapshot({
    required this.appVersion,
    required this.legalVersion,
    required this.platform,
    required this.webView2Info,
    this.coursesSyncTime,
    this.gradesSyncTime,
    this.examsSyncTime,
    this.lastSyncTimestamp,
    this.triggerMode,
    this.durationMs,
    this.coursesStatus,
    this.gradesStatus,
    this.examsStatus,
    this.coursesErrorCategory = 'none',
    this.gradesErrorCategory = 'none',
    this.examsErrorCategory = 'none',
    this.pendingMigrationCount = 0,
    this.hasKeyBlockedMigration = false,
  });

  /// 导出适用于 GitHub Issue 反馈的纯文本/Markdown 脱敏报告
  String toMarkdownReport() {
    final buffer = StringBuffer();
    buffer.writeln('### 金花助手客户端诊断摘要 (完全脱敏)');
    buffer.writeln('- **应用版本 (App Version)**: $appVersion');
    buffer.writeln('- **合规条款版本 (Legal Version)**: $legalVersion');
    buffer.writeln('- **运行平台 (Platform)**: $platform');
    buffer.writeln('- **WebView2 运行时 (Windows)**: $webView2Info');
    buffer.writeln(
      '- **本地密文升级状态**: ${pendingMigrationCount == 0 ? "已完成或无需升级" : "待重试 $pendingMigrationCount 项${hasKeyBlockedMigration ? "（受密钥访问异常阻塞）" : ""}"}',
    );
    buffer.writeln();
    buffer.writeln('#### 模块本地同步时间');
    buffer.writeln('- 课表模块: ${DiagnosticsService.formatDateTime(coursesSyncTime)}');
    buffer.writeln('- 成绩模块: ${DiagnosticsService.formatDateTime(gradesSyncTime)}');
    buffer.writeln('- 考试模块: ${DiagnosticsService.formatDateTime(examsSyncTime)}');
    buffer.writeln();
    buffer.writeln('#### 最近一次教务同步遥测');
    if (lastSyncTimestamp == null) {
      buffer.writeln('- 状态: 本次启动后尚未执行任何同步操作');
    } else {
      buffer.writeln('- 触发时间: ${DiagnosticsService.formatDateTime(lastSyncTimestamp)}');
      buffer.writeln('- 触发模式: ${triggerMode ?? "未知"}');
      buffer.writeln('- 总耗时: ${durationMs ?? 0} ms');
      buffer.writeln('- 课表模块: ${coursesStatus?.name ?? "未触发"} (错误类别: $coursesErrorCategory)');
      buffer.writeln('- 成绩模块: ${gradesStatus?.name ?? "未触发"} (错误类别: $gradesErrorCategory)');
      buffer.writeln('- 考试模块: ${examsStatus?.name ?? "未触发"} (错误类别: $examsErrorCategory)');
    }
    buffer.writeln();
    buffer.writeln('> 注：本诊断摘要严格不含任何学号、密码、Cookie、课表、成绩或考试等个人隐私数据。');

    return buffer.toString().trim();
  }
}

/// 脱敏同步遥测与运行环境诊断服务
///
/// 同时支持实例注入（[DiagnosticsService.new]）与默认单例静态门面，兼顾调用简洁与单元测试隔离性。
class DiagnosticsService {
  static DiagnosticsService _instance = DiagnosticsService();

  static DiagnosticsService get instance => _instance;

  @visibleForTesting
  static set instance(DiagnosticsService custom) => _instance = custom;

  DiagnosticsService({
    this._storage,
    this._crypto,
    Future<String?> Function()? webViewVersionProvider,
  }) : _debugWebViewVersionProvider = webViewVersionProvider;

  final StorageService? _storage;
  final AppCryptoService? _crypto;
  StorageService get _effectiveStorage => _storage ?? StorageService.instance;
  AppCryptoService get _effectiveCrypto => _crypto ?? AppCryptoService.instance;

  DateTime? _lastSyncTimestamp;
  String? _triggerMode;
  int? _durationMs;
  SyncModuleStatus? _coursesStatus;
  SyncModuleStatus? _gradesStatus;
  SyncModuleStatus? _examsStatus;
  String? _coursesErrorCategory;
  String? _gradesErrorCategory;
  String? _examsErrorCategory;

  Future<String?> Function()? _debugWebViewVersionProvider;

  @visibleForTesting
  static Future<String?> Function()? get debugWebViewVersionProvider =>
      _instance._debugWebViewVersionProvider;
  @visibleForTesting
  static set debugWebViewVersionProvider(Future<String?> Function()? fn) =>
      _instance._debugWebViewVersionProvider = fn;

  /// 记录最近一次教务同步的脱敏遥测数据
  static void recordSyncEvent({
    required String triggerMode,
    required int durationMs,
    SyncModuleStatus? coursesStatus,
    SyncModuleStatus? gradesStatus,
    SyncModuleStatus? examsStatus,
    Object? coursesError,
    Object? gradesError,
    Object? examsError,
  }) =>
      _instance.recordSyncEventInstance(
        triggerMode: triggerMode,
        durationMs: durationMs,
        coursesStatus: coursesStatus,
        gradesStatus: gradesStatus,
        examsStatus: examsStatus,
        coursesError: coursesError,
        gradesError: gradesError,
        examsError: examsError,
      );

  void recordSyncEventInstance({
    required String triggerMode,
    required int durationMs,
    SyncModuleStatus? coursesStatus,
    SyncModuleStatus? gradesStatus,
    SyncModuleStatus? examsStatus,
    Object? coursesError,
    Object? gradesError,
    Object? examsError,
  }) {
    _lastSyncTimestamp = DateTime.now();
    _triggerMode = triggerMode;
    _durationMs = durationMs;
    _coursesStatus = coursesStatus;
    _gradesStatus = gradesStatus;
    _examsStatus = examsStatus;
    _coursesErrorCategory = sanitizeErrorCategory(coursesError);
    _gradesErrorCategory = sanitizeErrorCategory(gradesError);
    _examsErrorCategory = sanitizeErrorCategory(examsError);
  }

  /// 将任意异常脱敏为标准枚举/类别名称，杜绝敏感内容与本地绝对路径外泄
  static String sanitizeErrorCategory(Object? error) {
    if (error == null) return 'none';
    if (error is TimeoutException) return 'TimeoutException';
    if (error is FormatException) return 'FormatException';

    final text = error.toString();
    if (text.contains('CryptoKeyException')) return 'CryptoKeyException';
    if (text.contains('CryptoException')) return 'CryptoException';
    if (text.contains('StorageFormatException')) return 'StorageFormatException';
    if (text.contains('BridgeException') || text.contains('bridge')) {
      return 'BridgeException';
    }
    if (text.contains('Timeout') || text.contains('timed out')) {
      return 'TimeoutException';
    }
    if (text.contains('MissingPluginException')) return 'MissingPluginException';
    if (text.contains('DomParse') || text.contains('HTML') || text.contains('DOM')) {
      return 'DomParseError';
    }
    if (text.contains('StateError')) return 'StateError';
    if (text.contains('ArgumentError')) return 'ArgumentError';

    return error.runtimeType.toString();
  }

  /// 格式化时间戳
  static String formatDateTime(DateTime? dt) {
    if (dt == null) return '无 (未同步)';
    return DateTimeUtils.formatFullDateTime(dt);
  }

  /// 采集当前脱敏诊断数据快照，供界面结构化展示与 Markdown 导出复用
  static Future<DiagnosticSnapshot> collectSnapshot() =>
      _instance.collectSnapshotInstance();

  Future<DiagnosticSnapshot> collectSnapshotInstance() async {
    final coursesSyncTime = await _effectiveStorage.loadLastSyncTimeInstance();
    final gradesSyncTime = await _effectiveStorage.loadGradesSyncTimeInstance();
    final examsSyncTime = await _effectiveStorage.loadExamsSyncTimeInstance();

    String webView2Info = '不适用 (${defaultTargetPlatform.name})';
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      if (_debugWebViewVersionProvider != null) {
        final v = await _debugWebViewVersionProvider!();
        webView2Info = v != null && v.isNotEmpty ? '已安装 ($v)' : '未检测到运行时 (缺失)';
      } else {
        try {
          final v = await win.WebviewController.getWebViewVersion();
          webView2Info = v != null && v.isNotEmpty ? '已安装 ($v)' : '未检测到运行时 (缺失)';
        } on Object catch (e) {
          webView2Info = '检测异常: ${sanitizeErrorCategory(e)}';
        }
      }
    }

    return DiagnosticSnapshot(
      appVersion: LegalService.appVersion,
      legalVersion: LegalService.currentVersion,
      platform: defaultTargetPlatform.name,
      webView2Info: webView2Info,
      coursesSyncTime: coursesSyncTime,
      gradesSyncTime: gradesSyncTime,
      examsSyncTime: examsSyncTime,
      lastSyncTimestamp: _lastSyncTimestamp,
      triggerMode: _triggerMode,
      durationMs: _durationMs,
      coursesStatus: _coursesStatus,
      gradesStatus: _gradesStatus,
      examsStatus: _examsStatus,
      coursesErrorCategory: _coursesErrorCategory ?? 'none',
      gradesErrorCategory: _gradesErrorCategory ?? 'none',
      examsErrorCategory: _examsErrorCategory ?? 'none',
      pendingMigrationCount: _effectiveCrypto.instancePendingMigrationKeys.length,
      hasKeyBlockedMigration: _effectiveCrypto.instanceHasKeyBlockedMigrationFailure,
    );
  }

  /// 生成纯文本/Markdown 格式的脱敏诊断摘要报告
  static Future<String> buildDiagnosticReport() =>
      _instance.buildDiagnosticReportInstance();

  Future<String> buildDiagnosticReportInstance() async {
    final snapshot = await collectSnapshotInstance();
    return snapshot.toMarkdownReport();
  }

  @visibleForTesting
  static void resetForTesting() {
    _instance = DiagnosticsService();
  }
}
