import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  final Future<bool> Function(SemesterCalibrationDecision decision)?
      confirmSemesterCalibrationOverride;

  final ValueNotifier<bool> isSyncingNotifier = ValueNotifier<bool>(false);
  bool _isSyncInFlight = false;

  DateTime? _lastSyncAttemptTime;
  int? _cachedDetectedWeek;
  String? _cachedDetectedSemester;
  DateTime? _cachedDetectedStart;

  WebViewSyncCoordinator({
    required this.getContext,
    required this.adapter,
    required this.onStateChanged,
    this.confirmSemesterCalibrationOverride,
  });

  bool get isSyncing => isSyncingNotifier.value;

  void dispose() {
    isSyncingNotifier.dispose();
  }

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
      final reqId = adapter.nextRequestId('week_detect');
      final script = await ParserService.buildWeekDetectScript(
        requestId: reqId,
        timeoutMs: 12000,
      );
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

  /// 应用同步时识别到的教学周或开学基准日（带内部冲突与大幅跳变确认保护）
  Future<String?> _applyDetectedWeekCalibration(
    ScheduleProvider scheduleProvider, {
    int? detectedWeek,
    String? detectedSemester,
    DateTime? detectedStart,
  }) async {
    final decision = scheduleProvider.evaluateSemesterCalibration(
      detectedWeek: detectedWeek ?? _cachedDetectedWeek,
      detectedSemester: (detectedSemester != null && detectedSemester.isNotEmpty)
          ? detectedSemester
          : _cachedDetectedSemester,
      detectedStart: detectedStart ?? _cachedDetectedStart,
    );

    if (!decision.hasUpdate) return null;

    if (!decision.requiresConfirmation) {
      if (decision.candidateMonday != null) {
        await scheduleProvider.setSemesterStartDate(
          decision.candidateMonday!,
          semester: decision.candidateSemester.isNotEmpty
              ? decision.candidateSemester
              : null,
        );
      }
      final week = scheduleProvider.actualCurrentWeek;
      final monday = scheduleProvider.semesterStartDate;
      final monStr = monday != null
          ? '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}'
          : '';
      return '已自动对齐第 $week 周${monStr.isNotEmpty ? " (第1周周一: $monStr)" : ""}';
    }

    // 触发了需要确认的冲突或大幅跳变
    bool confirmed = false;
    if (confirmSemesterCalibrationOverride != null) {
      confirmed = await confirmSemesterCalibrationOverride!(decision);
    } else {
      final context = getContext();
      if (context.mounted) {
        confirmed = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                icon: const Icon(Icons.warning_amber_rounded,
                    color: Colors.orange, size: 36),
                title: const Text('检测到学期基准变更或冲突'),
                content: Text(
                  '${decision.conflictReason ?? "教务系统返回的学期或开学周与当前本地设置存在偏差。"}\n\n'
                  '是否确认将学期基准更新为新检测到的配置？',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('保持原设置'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('更新学期基准'),
                  ),
                ],
              ),
            ) ??
            false;
      }
    }

    if (confirmed) {
      if (decision.candidateMonday != null) {
        await scheduleProvider.setSemesterStartDate(
          decision.candidateMonday!,
          semester: decision.candidateSemester.isNotEmpty
              ? decision.candidateSemester
              : null,
        );
      }
      return '已按确认更新学期基准';
    } else {
      return '已保持原学期基准不变';
    }
  }

  /// 执行一键全量同步（同时同步 课表 + 成绩 + 考试 3大模块，消除 UI 冻结）
  Future<void> syncAll() async {
    final context = getContext();
    if (_isSyncInFlight) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('正在同步教务数据，请稍候...'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (isSyncCoolingDown()) return;

    final scheduleProvider = context.read<ScheduleProvider>();
    final gradesProvider = context.read<GradesProvider>();
    final examsProvider = context.read<ExamsProvider>();

    _isSyncInFlight = true;
    isSyncingNotifier.value = true;
    onStateChanged(true, '正在启动全量异步同步...');

    try {
      final requestId = adapter.nextRequestId('sync_all');
      final script = await ParserService.buildSyncAllInjectionScript(
        requestId: requestId,
        timeoutMs: 30000,
      );
      final dynamic rawResult = await adapter.executeBridgeScript(
        script: script,
        expectedType: 'sync_all_result',
        requestId: requestId,
        onProgress: (msg) {
          onStateChanged(true, msg);
        },
      );
      final result = ParserService.parseSyncAllResult(rawResult);

      if (!context.mounted) return;

      // 全部未登录判定
      if (result.statusCourses.isNotLoggedIn &&
          result.statusGrades.isNotLoggedIn &&
          result.statusExams.isNotLoggedIn) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.lock_clock_rounded,
                color: Colors.orange, size: 36),
            title: const Text('未完成统一身份认证登录'),
            content: const Text(
              '未能提取数据：检测到统一身份认证尚未登录（已保留本地历史缓存）。\n\n'
              '操作指引：\n'
              '1. 请在下方网页中输入学号与密码完成登录；\n'
              '2. 登录成功后，再次点击底部【一键同步全部】。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('我知道了'),
              ),
            ],
          ),
        );
        return;
      }

      // 全部空数据判定
      if (result.statusCourses.isEmpty &&
          result.statusGrades.isEmpty &&
          result.statusExams.isEmpty) {
        await scheduleProvider.updateCourses(const []);
        await gradesProvider.updateGrades(const []);
        await examsProvider.updateExams(const []);
        if (!context.mounted) return;

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.info_outline_rounded,
                color: Colors.blue, size: 36),
            title: const Text('暂无已发布的教务数据'),
            content: const Text(
              '已成功连接强智教务系统，但当前学期暂未查询到课表、成绩或考试数据（本地旧列表已同步清空）。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('我知道了'),
              ),
            ],
          ),
        );
        return;
      }

      // 逐模块按四态语义处理缓存更新
      // 1. 课表
      if (result.statusCourses.isOk) {
        await scheduleProvider.updateCourses(result.courses);
      } else if (result.statusCourses.isEmpty) {
        await scheduleProvider.updateCourses(const []);
      }
      // notLoggedIn 或 error 严格保留原有课表缓存

      // 教学周校准
      final weekDetail = await _applyDetectedWeekCalibration(
        scheduleProvider,
        detectedWeek: result.detectedWeek,
        detectedSemester: result.detectedSemester,
        detectedStart: result.detectedSemesterStart,
      );

      // 2. 成绩
      if (result.statusGrades.isOk) {
        await gradesProvider.updateGrades(result.grades);
      } else if (result.statusGrades.isEmpty) {
        await gradesProvider.updateGrades(const []);
      }
      // notLoggedIn 或 error 严格保留原有成绩缓存

      // 3. 考试
      if (result.statusExams.isOk) {
        await examsProvider.updateExams(result.exams);
      } else if (result.statusExams.isEmpty) {
        await examsProvider.updateExams(const []);
      }
      // notLoggedIn 或 error 严格保留原有考试缓存

      if (!context.mounted) return;

      final String coursesDetail;
      switch (result.statusCourses) {
        case SyncModuleStatus.ok:
          coursesDetail = '成功导入 ${result.courses.length} 门课程';
          break;
        case SyncModuleStatus.empty:
          coursesDetail = '当前学期暂无课表数据（已清空旧缓存）';
          break;
        case SyncModuleStatus.notLoggedIn:
          coursesDetail = '未登录统一认证（已保留本地历史缓存）';
          break;
        case SyncModuleStatus.error:
          coursesDetail =
              '课表解析失败${result.errorCourses != null ? " (${result.errorCourses})" : " (页面可能已改版)"}（已保留本地历史缓存）';
          break;
      }

      final String gradesDetail;
      switch (result.statusGrades) {
        case SyncModuleStatus.ok:
          gradesDetail =
              '成功导入 ${result.grades.length} 门成绩 (GPA: ${gradesProvider.overallSummary?.averageGpa ?? "-"})';
          break;
        case SyncModuleStatus.empty:
          gradesDetail = '当前学期暂无成绩发布（已清空旧缓存）';
          break;
        case SyncModuleStatus.notLoggedIn:
          gradesDetail = '未登录统一认证（已保留本地历史缓存）';
          break;
        case SyncModuleStatus.error:
          gradesDetail =
              '成绩解析失败${result.errorGrades != null ? " (${result.errorGrades})" : " (页面可能已改版)"}（已保留本地历史缓存）';
          break;
      }

      final String examsDetail;
      switch (result.statusExams) {
        case SyncModuleStatus.ok:
          examsDetail = '成功导入 ${result.exams.length} 门考试安排';
          break;
        case SyncModuleStatus.empty:
          examsDetail = '当前学期暂无考试安排（已清空旧缓存）';
          break;
        case SyncModuleStatus.notLoggedIn:
          examsDetail = '未登录统一认证（已保留本地历史缓存）';
          break;
        case SyncModuleStatus.error:
          examsDetail =
              '考试解析失败${result.errorExams != null ? " (${result.errorExams})" : " (页面可能已改版)"}（已保留本地历史缓存）';
          break;
      }

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.cloud_done_rounded,
              color: Colors.green, size: 36),
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
                isSuccess: result.statusCourses.isOk,
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
                isSuccess: result.statusGrades.isOk,
              ),
              const SizedBox(height: 10),
              _buildSyncResultRow(
                context: ctx,
                icon: Icons.assignment,
                title: '考试日程',
                detail: examsDetail,
                isSuccess: result.statusExams.isOk,
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
    } catch (e) {
      if (!context.mounted) return;
      final errStr = e.toString();
      final isCancel = errStr.contains('取消') || errStr.contains('跳转');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isCancel ? '同步已取消' : '全量同步异常: $e')),
      );
    } finally {
      _isSyncInFlight = false;
      isSyncingNotifier.value = false;
      onStateChanged(false, null);
    }
  }

  /// 自动识别当前网页并执行对应专项同步
  Future<void> syncCurrentPage() async {
    final context = getContext();
    if (_isSyncInFlight) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('正在同步教务数据，请稍候...'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final dest = NavDestination.fromUrl(adapter.currentUrl);

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
        // 关键修复 (P0-2)：仅弹出智能识别提示，绝不在此分支触发 isSyncCoolingDown() 记录时间戳
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
    if (_isSyncInFlight) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('正在同步教务数据，请稍候...'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (isSyncCoolingDown()) return;

    final scheduleProvider = context.read<ScheduleProvider>();
    _isSyncInFlight = true;
    isSyncingNotifier.value = true;
    onStateChanged(true, '正在提取课表数据...');

    try {
      final requestId = adapter.nextRequestId('sync_course');
      final script = await ParserService.buildCourseInjectionScript(
        requestId: requestId,
        timeoutMs: 30000,
      );
      final dynamic rawResult = await adapter.executeBridgeScript(
        script: script,
        expectedType: 'sync_course_result',
        requestId: requestId,
      );
      final syncRes = ParserService.parseCourseSyncResult(rawResult);

      if (!context.mounted) return;

      if (syncRes.status == SyncModuleStatus.ok || syncRes.courses.isNotEmpty) {
        await scheduleProvider.updateCourses(syncRes.courses);
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
              '成功解析并导入 ${syncRes.courses.length} 门课程！'
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
      } else if (syncRes.status == SyncModuleStatus.empty) {
        await scheduleProvider.updateCourses(const []);
        if (!context.mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue),
                SizedBox(width: 8),
                Text('当前学期暂无课表'),
              ],
            ),
            content: const Text(
              '强智教务系统显示当前学期暂未排课或课表为空（本地旧课表已同步清空）。',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('我知道了'),
              ),
            ],
          ),
        );
      } else if (syncRes.status == SyncModuleStatus.notLoggedIn) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.lock_clock_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text('未登录统一认证'),
              ],
            ),
            content: const Text('检测到统一身份认证尚未登录（已保留本地历史课表缓存），请登录后再试。'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('我知道了'),
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
            content: Text(
              '当前页面未识别到课程表格 (table#timetable 或 table#kbtable)（已保留本地历史课表缓存）。\n\n'
              '操作提示：\n'
              '1. 请先在下方网页中完成统一身份认证登录；\n'
              '2. 登录成功后，点击上方导航条中的【我的课表】按钮；\n'
              '3. 待课表页面完整加载后，再次点击【同步当前课表】！\n'
              '${syncRes.error != null ? "详细原因: ${syncRes.error}" : ""}',
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
      final errStr = e.toString();
      final isCancel = errStr.contains('取消') || errStr.contains('跳转');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isCancel ? '同步已取消' : '课表解析异常: $e')),
      );
    } finally {
      _isSyncInFlight = false;
      isSyncingNotifier.value = false;
      onStateChanged(false, null);
    }
  }

  /// 执行一键解析并同步成绩
  Future<void> syncGrades() async {
    final context = getContext();
    if (_isSyncInFlight) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('正在同步教务数据，请稍候...'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (isSyncCoolingDown()) return;

    final gradesProvider = context.read<GradesProvider>();
    _isSyncInFlight = true;
    isSyncingNotifier.value = true;
    onStateChanged(true, '正在提取成绩数据...');

    try {
      final requestId = adapter.nextRequestId('sync_grades');
      final script = await ParserService.buildGradesInjectionScript(
        requestId: requestId,
        timeoutMs: 30000,
      );
      final dynamic rawResult = await adapter.executeBridgeScript(
        script: script,
        expectedType: 'sync_grades_result',
        requestId: requestId,
      );
      final result = ParserService.parseGradesResult(rawResult);

      if (!context.mounted) return;

      if (result.status == SyncModuleStatus.ok || result.grades.isNotEmpty) {
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
      } else if (result.status == SyncModuleStatus.empty) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue),
                SizedBox(width: 8),
                Text('当前页面暂无成绩'),
              ],
            ),
            content: const Text(
              '当前查询页面暂未显示任何已发布成绩（为防止网页学期筛选误删过往学期记录，已保留本地历史成绩缓存；如需全量校准请点击【一键同步全部】）。',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('我知道了'),
              ),
            ],
          ),
        );
      } else if (result.status == SyncModuleStatus.notLoggedIn) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.lock_clock_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text('未登录统一认证'),
              ],
            ),
            content: const Text('检测到统一身份认证尚未登录（已保留本地历史成绩缓存），请登录后再试。'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('我知道了'),
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
            content: Text(
              '当前页面未识别到成绩表格（已保留本地历史成绩缓存）。\n\n'
              '操作提示：\n'
              '请先点击上方快捷栏中的【成绩查询】按钮，跳转至成绩列表页后再执行同步。\n'
              '${result.error != null ? "详细原因: ${result.error}" : ""}',
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
      final errStr = e.toString();
      final isCancel = errStr.contains('取消') || errStr.contains('跳转');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isCancel ? '同步已取消' : '成绩解析异常: $e')),
      );
    } finally {
      _isSyncInFlight = false;
      isSyncingNotifier.value = false;
      onStateChanged(false, null);
    }
  }

  /// 执行一键解析并同步考试安排
  Future<void> syncExams() async {
    final context = getContext();
    if (_isSyncInFlight) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('正在同步教务数据，请稍候...'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (isSyncCoolingDown()) return;

    final examsProvider = context.read<ExamsProvider>();
    _isSyncInFlight = true;
    isSyncingNotifier.value = true;
    onStateChanged(true, '正在提取考试安排...');

    try {
      final requestId = adapter.nextRequestId('sync_exams');
      final script = await ParserService.buildExamsInjectionScript(
        requestId: requestId,
        timeoutMs: 30000,
      );
      final dynamic rawResult = await adapter.executeBridgeScript(
        script: script,
        expectedType: 'sync_exams_result',
        requestId: requestId,
      );
      final result = ParserService.parseExamsDetailedResult(rawResult);

      if (!context.mounted) return;

      if (result.status == SyncModuleStatus.ok || result.exams.isNotEmpty) {
        await examsProvider.updateExams(result.exams);
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
            content: Text(
                '成功解析导入 ${result.exams.length} 门考试日程！已自动提取考试时间与考场教室。'),
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
      } else if (result.status == SyncModuleStatus.empty) {
        await examsProvider.updateExams(const []);
        if (!context.mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue),
                SizedBox(width: 8),
                Text('当前暂无考试'),
              ],
            ),
            content: const Text(
              '强智教务系统显示当前学期暂未安排期末考试（本地旧考试日程已同步清空）。',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('我知道了'),
              ),
            ],
          ),
        );
      } else if (result.status == SyncModuleStatus.notLoggedIn) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.lock_clock_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text('未登录统一认证'),
              ],
            ),
            content: const Text('检测到统一身份认证尚未登录（已保留本地历史考试缓存），请登录后再试。'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('我知道了'),
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
            content: Text(
              '当前页面未识别到考试安排数据（已保留本地历史考试缓存）。\n\n'
              '操作提示：\n'
              '请先点击上方快捷栏中的【考试安排】按钮，跳转至考试查询页后再执行同步。\n'
              '${result.error != null ? "详细原因: ${result.error}" : ""}',
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
      final errStr = e.toString();
      final isCancel = errStr.contains('取消') || errStr.contains('跳转');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isCancel ? '同步已取消' : '考试解析异常: $e')),
      );
    } finally {
      _isSyncInFlight = false;
      isSyncingNotifier.value = false;
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
