import 'dart:convert';
import '../../models/course.dart';
import '../../models/grade.dart';
import '../../models/exam.dart';
import 'sync_models.dart';

/// 强智教务 WebView 执行结果反序列化与实体组装引擎
///
/// 职责单一：负责将 WebView Bridge 返回的动态 JSON 或字符串安全反序列化为 Dart 强类型实体，
/// 并对错误诊断、未登录拦截与空列表状态进行严谨判定。
class SyncResultParser {
  static dynamic unwrapJson(dynamic rawResult) {
    if (rawResult == null) return null;
    dynamic data = rawResult;
    if (data is String) {
      data = jsonDecode(data);
      if (data is String) {
        data = jsonDecode(data);
      }
    }
    return data;
  }

  /// 解析当前教学周识别结果
  static ({int? currentWeek, String? semester, DateTime? semesterStartDate}) parseWeekInfoResult(dynamic rawResult) {
    if (rawResult == null) {
      return (currentWeek: null, semester: null, semesterStartDate: null);
    }

    dynamic data = rawResult;
    try {
      data = unwrapJson(rawResult);
    } on Object catch (_) {
      return (currentWeek: null, semester: null, semesterStartDate: null);
    }

    if (data is Map) {
      int? week;
      final rawWeek = data['currentWeek'];
      if (rawWeek is int) {
        week = rawWeek;
      } else if (rawWeek is num) {
        week = rawWeek.toInt();
      } else if (rawWeek is String) {
        week = int.tryParse(rawWeek.trim());
      }
      if (week != null && (week < 1 || week > 30)) {
        week = null;
      }

      String? semester;
      final rawSem = data['semester'];
      if (rawSem is String && rawSem.trim().isNotEmpty) {
        semester = rawSem.trim();
      }

      DateTime? startDate;
      final rawStart = data['semesterStartDate'];
      if (rawStart is String && rawStart.trim().isNotEmpty) {
        final parsed = DateTime.tryParse(rawStart.trim());
        if (parsed != null) {
          startDate = DateTime(parsed.year, parsed.month, parsed.day);
        }
      }

      return (currentWeek: week, semester: semester, semesterStartDate: startDate);
    }

    return (currentWeek: null, semester: null, semesterStartDate: null);
  }

  /// 统一处理 WebView 返回的全量同步结果 (已彻底移除 dead field gradeSummary)
  static SyncAllResult parseSyncAllResult(dynamic rawResult) {
    if (rawResult == null) {
      return const SyncAllResult(
        courses: [],
        grades: [],
        exams: [],
        statusCourses: SyncModuleStatus.error,
        statusGrades: SyncModuleStatus.error,
        statusExams: SyncModuleStatus.error,
        error: '执行结果为空',
      );
    }

    dynamic data;
    try {
      data = unwrapJson(rawResult);
    } on Object catch (e) {
      return SyncAllResult(
        courses: const [],
        grades: const [],
        exams: const [],
        statusCourses: SyncModuleStatus.error,
        statusGrades: SyncModuleStatus.error,
        statusExams: SyncModuleStatus.error,
        error: 'JSON反序列化失败: $e',
      );
    }

    if (data is Map) {
      if (data['success'] == false || (data['error'] != null && data['status'] == null)) {
        final errText = data['error']?.toString() ?? '同步脚本执行异常';
        return SyncAllResult(
          courses: const [],
          grades: const [],
          exams: const [],
          statusCourses: SyncModuleStatus.error,
          statusGrades: SyncModuleStatus.error,
          statusExams: SyncModuleStatus.error,
          errorCourses: errText,
          errorGrades: errText,
          errorExams: errText,
          error: errText,
        );
      }

      final courses = parseCoursesResult(data['courses']);
      final gradesResult = parseGradesResult(data['gradesData']);
      final exams = parseExamsResult(data['exams']);
      final weekInfo = parseWeekInfoResult(data['weekInfo']);

      final statusMap = data['status'] is Map ? data['status'] as Map : const {};
      final errorsMap = data['errors'] is Map ? data['errors'] as Map : const {};

      final statusCourses = SyncModuleStatus.fromString(
        statusMap['courses']?.toString(),
        fallbackOk: courses.isNotEmpty,
        defaultStatus: SyncModuleStatus.error,
      );
      final statusGrades = SyncModuleStatus.fromString(
        statusMap['grades']?.toString(),
        fallbackOk: gradesResult.grades.isNotEmpty,
        defaultStatus: SyncModuleStatus.error,
      );
      final statusExams = SyncModuleStatus.fromString(
        statusMap['exams']?.toString(),
        fallbackOk: exams.isNotEmpty,
        defaultStatus: SyncModuleStatus.error,
      );

      return SyncAllResult(
        courses: courses,
        grades: gradesResult.grades,
        exams: exams,
        statusCourses: statusCourses,
        statusGrades: statusGrades,
        statusExams: statusExams,
        errorCourses: errorsMap['courses']?.toString(),
        errorGrades: errorsMap['grades']?.toString(),
        errorExams: errorsMap['exams']?.toString(),
        detectedWeek: weekInfo.currentWeek,
        detectedSemester: weekInfo.semester,
        detectedSemesterStart: weekInfo.semesterStartDate,
        error: data['error'] as String?,
      );
    }

    return const SyncAllResult(
      courses: [],
      grades: [],
      exams: [],
      statusCourses: SyncModuleStatus.error,
      statusGrades: SyncModuleStatus.error,
      statusExams: SyncModuleStatus.error,
      error: '数据格式异常',
    );
  }

  /// 统一处理单页课表同步结果（同时包含课程列表与自动识别的周次）
  static ({
    List<Course> courses,
    int? detectedWeek,
    String? detectedSemester,
    DateTime? detectedSemesterStart,
    SyncModuleStatus status,
    String? error,
  }) parseCourseSyncResult(dynamic rawResult) {
    if (rawResult == null) {
      return (
        courses: <Course>[],
        detectedWeek: null,
        detectedSemester: null,
        detectedSemesterStart: null,
        status: SyncModuleStatus.error,
        error: '执行结果为空',
      );
    }

    dynamic data;
    try {
      data = unwrapJson(rawResult);
    } on Object catch (_) {
      return (
        courses: <Course>[],
        detectedWeek: null,
        detectedSemester: null,
        detectedSemesterStart: null,
        status: SyncModuleStatus.error,
        error: 'JSON反序列化失败',
      );
    }

    if (data is Map) {
      if (data['success'] == false || (data['error'] != null && data['status'] == null)) {
        final error = data['error']?.toString() ?? '同步脚本执行异常';
        return (
          courses: <Course>[],
          detectedWeek: null,
          detectedSemester: null,
          detectedSemesterStart: null,
          status: SyncModuleStatus.error,
          error: error,
        );
      }

      final courses = parseCoursesResult(data['courses']);
      final weekInfo = parseWeekInfoResult(data['weekInfo']);
      final statusStr = data['status']?.toString();
      final bool hasCoursesKey = data.containsKey('courses') && data['courses'] is List;
      final status = SyncModuleStatus.fromString(
        statusStr,
        fallbackOk: courses.isNotEmpty,
        defaultStatus: (hasCoursesKey && data['error'] == null)
            ? SyncModuleStatus.empty
            : SyncModuleStatus.error,
      );
      final error = data['error']?.toString();
      return (
        courses: courses,
        detectedWeek: weekInfo.currentWeek,
        detectedSemester: weekInfo.semester,
        detectedSemesterStart: weekInfo.semesterStartDate,
        status: status,
        error: error,
      );
    }

    if (data is List) {
      final courses = parseCoursesResult(data);
      return (
        courses: courses,
        detectedWeek: null,
        detectedSemester: null,
        detectedSemesterStart: null,
        status: courses.isNotEmpty ? SyncModuleStatus.ok : SyncModuleStatus.empty,
        error: null,
      );
    }

    return (
      courses: <Course>[],
      detectedWeek: null,
      detectedSemester: null,
      detectedSemesterStart: null,
      status: SyncModuleStatus.error,
      error: '数据格式异常',
    );
  }

  /// 统一处理 WebView 返回的执行结果为 Course 列表
  static List<Course> parseCoursesResult(dynamic rawResult) {
    if (rawResult == null) return [];

    dynamic data;
    try {
      data = unwrapJson(rawResult);
    } on Object catch (_) {
      return [];
    }

    if (data is Map && data['courses'] is List) {
      data = data['courses'];
    }

    if (data is List) {
      return data.map((item) {
        if (item is Map<String, dynamic>) {
          return Course.fromJson(item);
        } else if (item is Map) {
          return Course.fromJson(Map<String, dynamic>.from(item));
        }
        return null;
      }).whereType<Course>().toList();
    }

    return [];
  }

  /// 统一处理 WebView 返回的成绩执行结果
  static ({
    List<GradeItem> grades,
    GradeSummary? summary,
    SyncModuleStatus status,
    String? error,
  }) parseGradesResult(dynamic rawResult) {
    if (rawResult == null) {
      return (
        grades: <GradeItem>[],
        summary: null,
        status: SyncModuleStatus.error,
        error: '执行结果为空',
      );
    }

    dynamic data;
    try {
      data = unwrapJson(rawResult);
    } on Object catch (_) {
      return (
        grades: <GradeItem>[],
        summary: null,
        status: SyncModuleStatus.error,
        error: 'JSON反序列化失败',
      );
    }

    if (data is Map) {
      if (data['success'] == false || (data['error'] != null && data['status'] == null)) {
        final error = data['error']?.toString() ?? '同步脚本执行异常';
        return (
          grades: <GradeItem>[],
          summary: null,
          status: SyncModuleStatus.error,
          error: error,
        );
      }

      List<GradeItem> grades = [];
      GradeSummary? summary;

      if (data['grades'] is List) {
        grades = (data['grades'] as List).map((item) {
          if (item is Map<String, dynamic>) {
            return GradeItem.fromJson(item);
          } else if (item is Map) {
            return GradeItem.fromJson(Map<String, dynamic>.from(item));
          }
          return null;
        }).whereType<GradeItem>().toList();
      }

      if (data['summary'] is Map) {
        final sumMap = data['summary'];
        summary = GradeSummary.fromJson(
          sumMap is Map<String, dynamic> ? sumMap : Map<String, dynamic>.from(sumMap),
        );
      }

      final statusStr = data['status']?.toString();
      final bool hasGradesKey = data.containsKey('grades') && data['grades'] is List;
      final status = SyncModuleStatus.fromString(
        statusStr,
        fallbackOk: grades.isNotEmpty,
        defaultStatus: (hasGradesKey && data['error'] == null)
            ? SyncModuleStatus.empty
            : SyncModuleStatus.error,
      );
      final error = data['error']?.toString();
      return (grades: grades, summary: summary, status: status, error: error);
    }

    if (data is List) {
      final grades = data.map((item) {
        if (item is Map<String, dynamic>) {
          return GradeItem.fromJson(item);
        } else if (item is Map) {
          return GradeItem.fromJson(Map<String, dynamic>.from(item));
        }
        return null;
      }).whereType<GradeItem>().toList();
      return (
        grades: grades,
        summary: null,
        status: grades.isNotEmpty ? SyncModuleStatus.ok : SyncModuleStatus.empty,
        error: null,
      );
    }

    return (
      grades: <GradeItem>[],
      summary: null,
      status: SyncModuleStatus.error,
      error: '数据格式异常',
    );
  }

  /// 统一处理 WebView 返回的考试安排执行结果（带状态与错误诊断）
  static ({
    List<ExamItem> exams,
    SyncModuleStatus status,
    String? error,
  }) parseExamsDetailedResult(dynamic rawResult) {
    if (rawResult == null) {
      return (
        exams: <ExamItem>[],
        status: SyncModuleStatus.error,
        error: '执行结果为空',
      );
    }

    dynamic data;
    try {
      data = unwrapJson(rawResult);
    } on Object catch (_) {
      return (
        exams: <ExamItem>[],
        status: SyncModuleStatus.error,
        error: 'JSON反序列化失败',
      );
    }

    if (data is Map) {
      if (data['success'] == false || (data['error'] != null && data['status'] == null)) {
        final error = data['error']?.toString() ?? '同步脚本执行异常';
        return (
          exams: <ExamItem>[],
          status: SyncModuleStatus.error,
          error: error,
        );
      }

      final exams = parseExamsResult(data['exams'] ?? data);
      final statusStr = data['status']?.toString();
      final bool hasExamsKey = data.containsKey('exams') && data['exams'] is List;
      final status = SyncModuleStatus.fromString(
        statusStr,
        fallbackOk: exams.isNotEmpty,
        defaultStatus: (hasExamsKey && data['error'] == null)
            ? SyncModuleStatus.empty
            : SyncModuleStatus.error,
      );
      final error = data['error']?.toString();

      return (exams: exams, status: status, error: error);
    }

    if (data is List) {
      final exams = parseExamsResult(data);
      return (
        exams: exams,
        status: exams.isNotEmpty ? SyncModuleStatus.ok : SyncModuleStatus.empty,
        error: null,
      );
    }

    return (
      exams: <ExamItem>[],
      status: SyncModuleStatus.error,
      error: '数据格式异常',
    );
  }

  /// 统一处理 WebView 返回的考试安排执行结果为 `List<ExamItem>`
  static List<ExamItem> parseExamsResult(dynamic rawResult) {
    if (rawResult == null) return [];

    dynamic data;
    try {
      data = unwrapJson(rawResult);
    } on Object catch (_) {
      return [];
    }

    if (data is List) {
      return data.map((item) {
        if (item is Map<String, dynamic>) {
          return ExamItem.fromJson(item);
        } else if (item is Map) {
          return ExamItem.fromJson(Map<String, dynamic>.from(item));
        }
        return null;
      }).whereType<ExamItem>().toList();
    }

    return [];
  }
}
