import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/course.dart';
import '../../models/exam.dart';
import '../../providers/schedule_provider.dart';
import '../../providers/grades_provider.dart';
import '../../providers/exams_provider.dart';
import '../../services/parser_service.dart';
import 'webview_constants.dart';
import 'webview_platform_adapter.dart';

/// 负责调度强智教务系统跨模块同步业务流与结果弹窗
class WebViewSyncCoordinator {
  final BuildContext Function() getContext;
  final WebViewPlatformAdapter adapter;
  final void Function(bool isLoading, String? statusMessage) onStateChanged;

  DateTime? _lastSyncAttemptTime;
  int? _cachedDetectedWeek;
  String? _cachedDetectedSemester;
  DateTime? _cachedDetectedStart;

  WebViewSyncCoordinator({
    required this.getContext,
    required this.adapter,
    required this.onStateChanged,
  });

  /// 同步防连击保护：限制 3 秒冷却，避免被教务系统识别为高频异常脚本
  bool isSyncCoolingDown() {
    final now = DateTime.now();
    if (_lastSyncAttemptTime != null &&
        now.difference(_lastSyncAttemptTime!) < const Duration(seconds: 3)) {
      final context = getContext();
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('同步请求过于频繁，请稍候 3 秒后再试'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return true;
    }
    _lastSyncAttemptTime = now;
    return false;
  }

  /// 当教务页面加载完成时，静默嗅探右上角「2026-2027-1 第X周」标识并缓存
  Future<void> tryCaptureWeekInfoSilently() async {
    final context = getContext();
    if (!context.mounted ||
        !adapter.currentUrl.toLowerCase().contains('jwgl.xaut.edu.cn')) {
      return;
    }
    try {
      final script = await ParserService.buildWeekDetectScript();
      final raw = await adapter.executeScript(script);
      final info = ParserService.parseWeekInfoResult(raw);
      if (info.currentWeek != null) {
        _cachedDetectedWeek = info.currentWeek;
      }
      if (info.semester != null && info.semester!.isNotEmpty) {
        _cachedDetectedSemester = info.semester;
      }
      if (info.semesterStartDate != null) {
        _cachedDetectedStart = info.semesterStartDate;
      }
    } catch (_) {}
  }

  /// 应用同步时识别到的教学周或开学基准日
  Future<String?> _applyDetectedWeekCalibration(
    ScheduleProvider scheduleProvider, {
    int? detectedWeek,
    String? detectedSemester,
    DateTime? detectedStart,
  }) async {
    final week = detectedWeek ?? _cachedDetectedWeek;
    final semester = (detectedSemester != null && detectedSemester.isNotEmpty)
        ? detectedSemester
        : _cachedDetectedSemester;
    final start = detectedStart ?? _cachedDetectedStart;

    if (week != null) {
      await scheduleProvider.calibrateFromCurrentWeek(week, semester: semester);
      final monday = scheduleProvider.semesterStartDate;
      final monStr = monday != null
          ? '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}'
          : '';
      return '已自动对齐第 $week 周${monStr.isNotEmpty ? " (第1周周一: $monStr)" : ""}';
    } else if (start != null) {
      await scheduleProvider.calibrateFromStartDate(start, semester: semester);
      final w = scheduleProvider.actualCurrentWeek;
      final monStr =
          '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
      return '已按校历对齐第 $w 周 (第1周周一: $monStr)';
    }
    return null;
  }

  /// 执行一键全量同步（同时同步 课表 + 成绩 + 考试 3大模块，消除 UI 冻结）
  Future<void> syncAll() async {
    if (isSyncCoolingDown()) return;

    final context = getContext();
    final scheduleProvider = context.read<ScheduleProvider>();
    final gradesProvider = context.read<GradesProvider>();
    final examsProvider = context.read<ExamsProvider>();

    onStateChanged(true, '正在启动全量异步同步...');

    try {
      final script = await ParserService.buildSyncAllInjectionScript();
      final dynamic rawResult = await adapter.executeBridgeScript(
        script: script,
        expectedType: 'sync_all_result',
        onProgress: (msg) {
          onStateChanged(true, msg);
        },
      );
      final result = ParserService.parseSyncAllResult(rawResult);

      if (!context.mounted) return;

      if (result.hasAnyData) {
        if (result.hasCourses) {
          await scheduleProvider.updateCourses(result.courses);
        }
        final weekDetail = await _applyDetectedWeekCalibration(
          scheduleProvider,
          detectedWeek: result.detectedWeek,
          detectedSemester: result.detectedSemester,
          detectedStart: result.detectedSemesterStart,
        );
        if (result.hasGrades) {
          await gradesProvider.updateGrades(result.grades);
        }
        if (result.hasExams) {
          await examsProvider.updateExams(result.exams);
        }

        if (!context.mounted) return;

        final String coursesDetail;
        switch (result.statusCourses) {
          case SyncModuleStatus.ok:
            coursesDetail = '成功导入 ${result.courses.length} 门课程';
            break;
          case SyncModuleStatus.empty:
            coursesDetail = '当前学期暂无课表数据';
            break;
          case SyncModuleStatus.notLoggedIn:
            coursesDetail = '未登录统一身份认证';
            break;
          case SyncModuleStatus.error:
            coursesDetail =
                '课表解析失败${result.errorCourses != null ? " (${result.errorCourses})" : " (页面可能已改版)"}';
            break;
        }

        final String gradesDetail;
        switch (result.statusGrades) {
          case SyncModuleStatus.ok:
            gradesDetail =
                '成功导入 ${result.grades.length} 门成绩 (GPA: ${gradesProvider.overallSummary?.averageGpa ?? "-"})';
            break;
          case SyncModuleStatus.empty:
            gradesDetail = '当前学期暂无成绩发布';
            break;
          case SyncModuleStatus.notLoggedIn:
            gradesDetail = '未登录统一身份认证';
            break;
          case SyncModuleStatus.error:
            gradesDetail =
                '成绩解析失败${result.errorGrades != null ? " (${result.errorGrades})" : " (页面可能已改版)"}';
            break;
        }

        final String examsDetail;
        switch (result.statusExams) {
          case SyncModuleStatus.ok:
            examsDetail = '成功导入 ${result.exams.length} 门考试安排';
            break;
          case SyncModuleStatus.empty:
            examsDetail = '暂无已发布的考试安排';
            break;
          case SyncModuleStatus.notLoggedIn:
            examsDetail = '未登录统一身份认证';
            break;
          case SyncModuleStatus.error:
            examsDetail =
                '考试解析失败${result.errorExams != null ? " (${result.errorExams})" : " (页面可能已改版)"}';
            break;
        }

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.cloud_done_rounded, color: Colors.green, size: 36),
            title: const Text('全量教务同步完成'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSyncResultRow(
                  context: ctx,
                  icon: Icons.calendar_month,
                  title: '课表数据',
                  detail: coursesDetail,
                  isSuccess: result.hasCourses,
                ),
                const SizedBox(height: 10),
                _buildSyncResultRow(
                  context: ctx,
                  icon: Icons.today_rounded,
                  title: '教学周校准',
                  detail: weekDetail ?? '未识别到顶栏周次，可在课表页手动校准开学日',
                  isSuccess: weekDetail != null,
                ),
                const SizedBox(height: 10),
                _buildSyncResultRow(
                  context: ctx,
                  icon: Icons.grade,
                  title: '学业成绩',
                  detail: gradesDetail,
                  isSuccess: result.hasGrades,
                ),
                const SizedBox(height: 10),
                _buildSyncResultRow(
                  context: ctx,
                  icon: Icons.assignment,
                  title: '考试日程',
                  detail: examsDetail,
                  isSuccess: result.hasExams,
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                },
                child: const Text('返回主页查看'),
              ),
            ],
          ),
        );
      } else {
        final String title;
        final String message;
        final IconData icon;
        final Color iconColor;

        if (result.isAnyNotLoggedIn) {
          title = '未完成统一身份认证登录';
          icon = Icons.lock_clock_rounded;
          iconColor = Colors.orange;
          message = '未能提取数据：检测到统一身份认证尚未登录。\n\n'
              '操作指引：\n'
              '1. 请在下方网页中输入学号与密码完成登录；\n'
              '2. 登录成功后，再次点击底部【一键同步全部】。';
        } else if (result.isAnyError) {
          title = '教务同步遇到异常';
          icon = Icons.error_outline_rounded;
          iconColor = Colors.red;
          final errorList = [
            if (result.errorCourses != null) '• 课表: ${result.errorCourses}',
            if (result.errorGrades != null) '• 成绩: ${result.errorGrades}',
            if (result.errorExams != null) '• 考试: ${result.errorExams}',
            if (result.error != null) '• 全局: ${result.error}',
          ];
          message = '强智教务页面结构可能已改版或服务暂时不可用：\n\n'
              '${errorList.join('\n')}\n\n'
              '若持续出现此提示，请向开发者反馈。';
        } else {
          title = '暂无已发布的教务数据';
          icon = Icons.info_outline_rounded;
          iconColor = Colors.blue;
          message = '已成功连接强智教务系统，但当前学期暂未查询到课表、成绩或考试数据。';
        }

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(icon, color: iconColor, size: 36),
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('我知道了'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('全量同步异常: $e')),
      );
    } finally {
      onStateChanged(false, null);
    }
  }

  /// 自动识别当前网页并执行对应专项同步
  Future<void> syncCurrentPage() async {
    if (isSyncCoolingDown()) return;

    final dest = NavDestination.fromUrl(adapter.currentUrl);
    final context = getContext();

    switch (dest) {
      case NavDestination.timetable:
        await syncSchedule();
        break;
      case NavDestination.grades:
        await syncGrades();
        break;
      case NavDestination.exams:
        await syncExams();
        break;
      case NavDestination.home:
      case NavDestination.other:
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.blue),
                SizedBox(width: 8),
                Text('智能识别提示'),
              ],
            ),
            content: Text(
              '当前浏览页面为：${dest.label}\n\n'
              '当前未处于课表、成绩或考试的特定功能页。\n\n'
              '建议：\n'
              '• 直接点击左侧【一键同步全部】在后台一次性全部提取；\n'
              '• 或点击上方快捷跳转进入对应页面后再单独同步。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  syncAll();
                },
                child: const Text('一键同步全部'),
              ),
            ],
          ),
        );
        break;
    }
  }

  /// 执行一键解析并同步课表
  Future<void> syncSchedule() async {
    final context = getContext();
    final scheduleProvider = context.read<ScheduleProvider>();
    onStateChanged(true, '正在提取课表数据...');

    try {
      final script = await ParserService.buildCourseInjectionScript();
      final dynamic rawResult = await adapter.executeBridgeScript(
        script: script,
        expectedType: 'sync_course_result',
      );
      final syncRes = ParserService.parseCourseSyncResult(rawResult);
      final List<Course> parsed = syncRes.courses;

      if (!context.mounted) return;

      if (parsed.isNotEmpty) {
        await scheduleProvider.updateCourses(parsed);
        final weekDetail = await _applyDetectedWeekCalibration(
          scheduleProvider,
          detectedWeek: syncRes.detectedWeek,
          detectedSemester: syncRes.detectedSemester,
          detectedStart: syncRes.detectedSemesterStart,
        );
        if (!context.mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('课表同步成功'),
              ],
            ),
            content: Text(
              '成功解析并导入 ${parsed.length} 门课程！'
              '${weekDetail != null ? "\n$weekDetail" : ""}',
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                },
                child: const Text('返回课表查看'),
              ),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange),
                SizedBox(width: 8),
                Text('未检测到课表'),
              ],
            ),
            content: const Text(
              '当前页面未识别到课程表格 (table#timetable 或 table#kbtable)。\n\n'
              '操作提示：\n'
              '1. 请先在下方网页中完成统一身份认证登录；\n'
              '2. 登录成功后，点击上方导航条中的【我的课表】按钮；\n'
              '3. 待课表页面完整加载后，再次点击【同步当前课表】！',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('我知道了'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  adapter.navigateTo(WebViewConstants.timetableUrl);
                },
                child: const Text('前往我的课表'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('课表解析异常: $e')),
      );
    } finally {
      onStateChanged(false, null);
    }
  }

  /// 执行一键解析并同步成绩
  Future<void> syncGrades() async {
    final context = getContext();
    final gradesProvider = context.read<GradesProvider>();
    onStateChanged(true, '正在提取成绩数据...');

    try {
      final script = await ParserService.buildGradesInjectionScript();
      final dynamic rawResult = await adapter.executeBridgeScript(
        script: script,
        expectedType: 'sync_grades_result',
      );
      final result = ParserService.parseGradesResult(rawResult);

      if (!context.mounted) return;

      if (result.grades.isNotEmpty) {
        await gradesProvider.updateGrades(result.grades);
        if (!context.mounted) return;
        final summary = gradesProvider.overallSummary;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('成绩同步成功'),
              ],
            ),
            content: Text(
              '成功导入 ${result.grades.length} 门课程成绩！\n'
              '平均 GPA: ${summary?.averageGpa ?? '-'}\n'
              '总修学分: ${summary?.totalCredits ?? '-'}',
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                },
                child: const Text('返回查看成绩'),
              ),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange),
                SizedBox(width: 8),
                Text('未检测到成绩表格'),
              ],
            ),
            content: const Text(
              '当前页面未识别到成绩表格。\n\n'
              '操作提示：\n'
              '请先点击上方快捷栏中的【成绩查询】按钮，跳转至成绩列表页后再执行同步。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('我知道了'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  adapter.navigateTo(WebViewConstants.gradesUrl);
                },
                child: const Text('前往成绩查询'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成绩解析异常: $e')),
      );
    } finally {
      onStateChanged(false, null);
    }
  }

  /// 执行一键解析并同步考试安排
  Future<void> syncExams() async {
    final context = getContext();
    final examsProvider = context.read<ExamsProvider>();
    onStateChanged(true, '正在提取考试安排...');

    try {
      final script = await ParserService.buildExamsInjectionScript();
      final dynamic rawResult = await adapter.executeBridgeScript(
        script: script,
        expectedType: 'sync_exams_result',
      );
      final List<ExamItem> parsed = ParserService.parseExamsResult(rawResult);

      if (!context.mounted) return;

      if (parsed.isNotEmpty) {
        await examsProvider.updateExams(parsed);
        if (!context.mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('考试日程同步成功'),
              ],
            ),
            content: Text('成功解析导入 ${parsed.length} 门考试日程！已自动提取考试时间与考场教室。'),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                },
                child: const Text('返回查看考试'),
              ),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange),
                SizedBox(width: 8),
                Text('未检测到考试表格'),
              ],
            ),
            content: const Text(
              '当前页面未识别到考试安排数据。\n\n'
              '操作提示：\n'
              '请先点击上方快捷栏中的【考试安排】按钮，跳转至考试查询页后再执行同步。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('我知道了'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  adapter.navigateTo(WebViewConstants.examsUrl);
                },
                child: const Text('前往考试安排'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('考试解析异常: $e')),
      );
    } finally {
      onStateChanged(false, null);
    }
  }

  Widget _buildSyncResultRow({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String detail,
    required bool isSuccess,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isSuccess ? Icons.check_circle : Icons.remove_circle_outline,
          color: isSuccess ? Colors.green : theme.colorScheme.onSurfaceVariant,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: TextStyle(
                  fontSize: 12,
                  color: isSuccess
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
