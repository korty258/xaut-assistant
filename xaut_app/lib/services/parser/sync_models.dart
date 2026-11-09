import '../../models/course.dart';
import '../../models/grade.dart';
import '../../models/exam.dart';

/// 课表解析结构体
class CourseParsingResult {
  final List<Course> courses;
  final int? currentWeek;
  final String? semester;
  final DateTime? semesterStartDate;
  final SyncModuleStatus status;
  final String? error;

  const CourseParsingResult({
    required this.courses,
    this.currentWeek,
    this.semester,
    this.semesterStartDate,
    this.status = SyncModuleStatus.empty,
    this.error,
  });
}

/// 成绩解析结构体
class GradesParsingResult {
  final List<GradeItem> grades;
  final GradeSummary? summary;
  final SyncModuleStatus status;
  final String? error;

  const GradesParsingResult({
    required this.grades,
    this.summary,
    this.status = SyncModuleStatus.empty,
    this.error,
  });
}

/// 考试安排解析结构体
class ExamsParsingResult {
  final List<ExamItem> exams;
  final SyncModuleStatus status;
  final String? error;

  const ExamsParsingResult({
    required this.exams,
    this.status = SyncModuleStatus.empty,
    this.error,
  });
}

/// 模块同步状态枚举 (细化四态：成功 ok、无数据 empty、未登录 notLoggedIn、异常改版 error)
enum SyncModuleStatus {
  ok,
  empty,
  notLoggedIn,
  error;

  static SyncModuleStatus fromString(
    String? val, {
    bool fallbackOk = false,
    SyncModuleStatus defaultStatus = SyncModuleStatus.error,
  }) {
    switch (val?.toLowerCase()) {
      case 'ok':
        return SyncModuleStatus.ok;
      case 'empty':
        return SyncModuleStatus.empty;
      case 'not_logged_in':
        return SyncModuleStatus.notLoggedIn;
      case 'error':
        return SyncModuleStatus.error;
      default:
        return fallbackOk ? SyncModuleStatus.ok : defaultStatus;
    }
  }

  bool get isOk => this == SyncModuleStatus.ok;
  bool get isEmpty => this == SyncModuleStatus.empty;
  bool get isNotLoggedIn => this == SyncModuleStatus.notLoggedIn;
  bool get isError => this == SyncModuleStatus.error;
}

/// 全量跨模块一键同步汇总结果 (已移除未使用的 dead field gradesSummary)
class SyncAllResult {
  final List<Course> courses;
  final List<GradeItem> grades;
  final List<ExamItem> exams;
  final SyncModuleStatus statusCourses;
  final SyncModuleStatus statusGrades;
  final SyncModuleStatus statusExams;
  final String? errorCourses;
  final String? errorGrades;
  final String? errorExams;
  final int? detectedWeek;
  final String? detectedSemester;
  final DateTime? detectedSemesterStart;
  final String? error;

  const SyncAllResult({
    required this.courses,
    required this.grades,
    required this.exams,
    this.statusCourses = SyncModuleStatus.empty,
    this.statusGrades = SyncModuleStatus.empty,
    this.statusExams = SyncModuleStatus.empty,
    this.errorCourses,
    this.errorGrades,
    this.errorExams,
    this.detectedWeek,
    this.detectedSemester,
    this.detectedSemesterStart,
    this.error,
  });

  bool get hasCourses => courses.isNotEmpty;
  bool get hasGrades => grades.isNotEmpty;
  bool get hasExams => exams.isNotEmpty;
  bool get hasAnyData => hasCourses || hasGrades || hasExams;

  bool get isAnyNotLoggedIn =>
      statusCourses == SyncModuleStatus.notLoggedIn ||
      statusGrades == SyncModuleStatus.notLoggedIn ||
      statusExams == SyncModuleStatus.notLoggedIn;

  bool get isAnyError =>
      statusCourses == SyncModuleStatus.error ||
      statusGrades == SyncModuleStatus.error ||
      statusExams == SyncModuleStatus.error;
}
