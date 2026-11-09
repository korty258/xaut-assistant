import 'package:flutter/foundation.dart';
import '../models/course.dart';
import '../models/grade.dart';
import '../models/exam.dart';
import 'parser/sync_models.dart';
import 'parser/sync_script_builder.dart';
import 'parser/sync_result_parser.dart';

export 'parser/sync_models.dart';
export 'parser/sync_script_builder.dart';
export 'parser/sync_result_parser.dart';

/// 强智教务解析服务统一门面 (Facade)
///
/// 架构演进：
/// - 注入脚本构建已收拢至 [SyncScriptBuilder]（消除冗余 checkAuth 与 Bridge 模板）
/// - 返回结果解析与状态判定已收拢至 [SyncResultParser]（移除未使用的死字段 gradeSummary）
/// - GPA 与加权平均分统一由 [GradeCalculator] 计算（彻底消除 JS/Dart 双端规则漂移）
///
/// 本类作为向后兼容的外观入口，全面代理上述单一职责引擎。
class ParserService {
  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  static void setMockJsCode(String? js) => SyncScriptBuilder.setMockJsCode(js);

  /// 加载内置 assets 中的 qiangzhi_parser.js
  static Future<String> loadParserJs() => SyncScriptBuilder.loadParserJs();

  /// 构建轻量级当前教学周被动嗅探脚本
  static Future<String> buildWeekDetectScript({
    String requestId = '',
    int timeoutMs = 12000,
  }) =>
      SyncScriptBuilder.buildWeekDetectScript(
        requestId: requestId,
        timeoutMs: timeoutMs,
      );

  /// 构建课表解析注入代码
  static Future<String> buildCourseInjectionScript({
    String requestId = '',
    int timeoutMs = 30000,
  }) =>
      SyncScriptBuilder.buildCourseInjectionScript(
        requestId: requestId,
        timeoutMs: timeoutMs,
      );

  /// 构建成绩解析注入代码
  static Future<String> buildGradesInjectionScript({
    String requestId = '',
    int timeoutMs = 30000,
  }) =>
      SyncScriptBuilder.buildGradesInjectionScript(
        requestId: requestId,
        timeoutMs: timeoutMs,
      );

  /// 构建考试安排解析注入代码
  static Future<String> buildExamsInjectionScript({
    String requestId = '',
    int timeoutMs = 30000,
  }) =>
      SyncScriptBuilder.buildExamsInjectionScript(
        requestId: requestId,
        timeoutMs: timeoutMs,
      );

  /// 构建全量一键同步脚本 (课表 + 成绩 + 考试 + 当前教学周 跨模块一次性同步)
  static Future<String> buildSyncAllInjectionScript({
    String requestId = '',
    int timeoutMs = 30000,
  }) =>
      SyncScriptBuilder.buildSyncAllInjectionScript(
        requestId: requestId,
        timeoutMs: timeoutMs,
      );

  /// 解析当前教学周识别结果
  static ({int? currentWeek, String? semester, DateTime? semesterStartDate}) parseWeekInfoResult(dynamic rawResult) =>
      SyncResultParser.parseWeekInfoResult(rawResult);

  /// 统一处理 WebView 返回的全量同步结果
  static SyncAllResult parseSyncAllResult(dynamic rawResult) =>
      SyncResultParser.parseSyncAllResult(rawResult);

  /// 统一处理单页课表同步结果（同时包含课程列表与自动识别的周次）
  static ({
    List<Course> courses,
    int? detectedWeek,
    String? detectedSemester,
    DateTime? detectedSemesterStart,
    SyncModuleStatus status,
    String? error,
  }) parseCourseSyncResult(dynamic rawResult) =>
      SyncResultParser.parseCourseSyncResult(rawResult);

  /// 统一处理 WebView 返回的执行结果为 Course 列表
  static List<Course> parseCoursesResult(dynamic rawResult) =>
      SyncResultParser.parseCoursesResult(rawResult);

  /// 统一处理 WebView 返回的成绩执行结果
  static ({
    List<GradeItem> grades,
    GradeSummary? summary,
    SyncModuleStatus status,
    String? error,
  }) parseGradesResult(dynamic rawResult) =>
      SyncResultParser.parseGradesResult(rawResult);

  /// 统一处理 WebView 返回的考试安排执行结果（带状态与错误诊断）
  static ({
    List<ExamItem> exams,
    SyncModuleStatus status,
    String? error,
  }) parseExamsDetailedResult(dynamic rawResult) =>
      SyncResultParser.parseExamsDetailedResult(rawResult);

  /// 统一处理 WebView 返回的考试安排执行结果为 `List<ExamItem>`
  static List<ExamItem> parseExamsResult(dynamic rawResult) =>
      SyncResultParser.parseExamsResult(rawResult);
}
