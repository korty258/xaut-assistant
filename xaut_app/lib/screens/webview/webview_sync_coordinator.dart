import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/exams_provider.dart';
import '../../providers/grades_provider.dart';
import '../../providers/schedule_provider.dart';
import '../../services/diagnostics_service.dart';
import '../../services/parser_service.dart';
import '../../services/storage_service.dart';
import 'webview_constants.dart';
import 'webview_platform_adapter.dart';
import 'webview_sync_calibration.dart';
import 'webview_sync_dialogs.dart';

/// 负责调度强智教务系统跨模块同步业务流（并发防抖、脚本触发、持久化事务与诊断记账）
class WebViewSyncCoordinator {
  final BuildContext Function() getContext;
  final WebViewPlatformAdapter adapter;
  final void Function(bool isLoading, String? statusMessage) onStateChanged;
  final Future<bool> Function(SemesterCalibrationDecision decision)?
      confirmSemesterCalibrationOverride;

  final ValueNotifier<bool> isSyncingNotifier = ValueNotifier<bool>(false);
  bool _isSyncInFlight = false;
  bool _isDisposed = false;

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
  bool get isDisposed => _isDisposed;

  void dispose() {
    _isDisposed = true;
    isSyncingNotifier.dispose();
  }

  @visibleForTesting
  void resetCooldownForTest() {
    _lastSyncAttemptTime = null;
  }

  Future<SyncPersistOutcome> _persistSafely(
    Future<void> Function() action,
  ) async {
    try {
      await action();
      return const SyncPersistOutcome.success();
    } on StorageWriteException catch (e) {
      final category = DiagnosticsService.sanitizeErrorCategory(e);
      if (e.dataSaved) {
        return SyncPersistOutcome.partialSyncTime(
          errorCategory: category,
          pendingSyncTime: e.pendingSyncTime,
        );
      }
      return SyncPersistOutcome.failed(category);
    } on Object catch (e) {
      return SyncPersistOutcome.failed(
        DiagnosticsService.sanitizeErrorCategory(e),
      );
    }
  }

  void _setSyncingState(bool syncing, String? message) {
    _isSyncInFlight = syncing;
    if (_isDisposed) return;
    isSyncingNotifier.value = syncing;
    onStateChanged(syncing, message);
  }

  /// 并发同步在途提示（返回 true 表示已有任务正在执行、调用方应中止）
  bool _rejectIfSyncInFlight(BuildContext context) {
    if (!_isSyncInFlight) return false;
    if (!_isDisposed && context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在同步教务数据，请稍候...'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return true;
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

  /// 统一同步准入守卫（先验在途并发，再验 3 秒防连击冷却）
  bool _canStartSync(BuildContext context) =>
      !_rejectIfSyncInFlight(context) && !isSyncCoolingDown();

  void _handleSyncFailure(BuildContext context, String prefix, Object error) {
    if (_isDisposed || !context.mounted) return;
    final errStr = error.toString();
    final isCancel = errStr.contains('取消') || errStr.contains('跳转');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(isCancel ? '同步已取消' : '$prefix: $error')),
    );
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
    } on Object catch (_) {}
  }

  Future<PreparedCalibration> _prepareWeek(
    ScheduleProvider scheduleProvider, {
    int? detectedWeek,
    String? detectedSemester,
    DateTime? detectedStart,
  }) =>
      WebViewSyncCalibrationHelper.prepareWeekCalibration(
        scheduleProvider,
        getContext: getContext,
        isDisposed: () => _isDisposed,
        confirmOverride: confirmSemesterCalibrationOverride,
        detectedWeek: detectedWeek ?? _cachedDetectedWeek,
        detectedSemester:
            (detectedSemester != null && detectedSemester.isNotEmpty)
                ? detectedSemester
                : _cachedDetectedSemester,
        detectedStart: detectedStart ?? _cachedDetectedStart,
      );

  /// 执行一键全量同步（依次抓取 课表 + 成绩 + 考试 3 大模块，消除 UI 冻结）
  Future<void> syncAll() async {
    final context = getContext();
    if (!_canStartSync(context)) return;

    final scheduleProvider = context.read<ScheduleProvider>();
    final gradesProvider = context.read<GradesProvider>();
    final examsProvider = context.read<ExamsProvider>();

    _setSyncingState(true, '正在启动全量异步同步...');
    final stopwatch = Stopwatch()..start();

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
        onProgress: (msg) => _setSyncingState(true, msg),
      );
      final result = ParserService.parseSyncAllResult(rawResult);

      DiagnosticsService.recordSyncEvent(
        triggerMode: 'syncAll',
        durationMs: stopwatch.elapsedMilliseconds,
        coursesStatus: result.statusCourses,
        gradesStatus: result.statusGrades,
        examsStatus: result.statusExams,
        coursesError: result.errorCourses,
        gradesError: result.errorGrades,
        examsError: result.errorExams,
      );

      if (_isDisposed || !context.mounted) return;

      if (result.statusCourses.isNotLoggedIn &&
          result.statusGrades.isNotLoggedIn &&
          result.statusExams.isNotLoggedIn) {
        WebViewSyncDialogs.showSyncAllNotLoggedInDialog(context);
        return;
      }

      PreparedCalibration prepCalib = (
        pendingDecision: null,
        detailMessage: null,
        rejectedByUser: false,
        isSuccess: false,
      );
      if (result.statusCourses.isOk || result.statusCourses.isEmpty) {
        prepCalib = await _prepareWeek(
          scheduleProvider,
          detectedWeek: result.detectedWeek,
          detectedSemester: result.detectedSemester,
          detectedStart: result.detectedSemesterStart,
        );
        if (_isDisposed || !context.mounted) return;
      }
      final bool rejectedByUser = prepCalib.rejectedByUser;

      var coursesOutcome = const SyncPersistOutcome.success();
      CalibrationCommitResult calibRes = (
        detailMessage: rejectedByUser ? '已保持原学期基准不变' : prepCalib.detailMessage,
        isSuccess: !rejectedByUser && prepCalib.isSuccess,
        saveFailed: false,
        calibrationRollbackFailed: false,
      );
      if (!rejectedByUser &&
          (result.statusCourses.isOk || result.statusCourses.isEmpty)) {
        final atomic =
            await WebViewSyncCalibrationHelper.persistCoursesAndCalibrationAtomic(
          scheduleProvider,
          persistSafely: _persistSafely,
          writeCourses: () => scheduleProvider.updateCourses(
            result.statusCourses.isOk ? result.courses : const [],
          ),
          pendingDecision: prepCalib.pendingDecision,
          preparedDetail: prepCalib.detailMessage,
          preparedSuccess: prepCalib.isSuccess,
          rejectedByUser: false,
          isDisposed: () => _isDisposed,
        );
        if (_isDisposed) return;
        coursesOutcome = atomic.coursesOutcome;
        calibRes = atomic.calibRes;
      } else if (!rejectedByUser) {
        calibRes =
            await WebViewSyncCalibrationHelper.commitPendingWeekCalibration(
          scheduleProvider,
          pendingDecision: prepCalib.pendingDecision,
          preparedDetail: prepCalib.detailMessage,
          preparedSuccess: prepCalib.isSuccess,
          rejectedByUser: false,
          coursesPersisted: true,
        );
      }
      if (_isDisposed || !context.mounted) return;

      var gradesOutcome = const SyncPersistOutcome.success();
      if (result.statusGrades.isOk) {
        gradesOutcome =
            await _persistSafely(() => gradesProvider.updateGrades(result.grades));
      } else if (result.statusGrades.isEmpty) {
        gradesOutcome =
            await _persistSafely(() => gradesProvider.updateGrades(const []));
      }

      var examsOutcome = const SyncPersistOutcome.success();
      if (result.statusExams.isOk) {
        examsOutcome =
            await _persistSafely(() => examsProvider.updateExams(result.exams));
      } else if (result.statusExams.isEmpty) {
        examsOutcome =
            await _persistSafely(() => examsProvider.updateExams(const []));
      }

      if (_isDisposed || !context.mounted) return;

      if (!rejectedByUser &&
          result.statusCourses.isEmpty &&
          result.statusGrades.isEmpty &&
          result.statusExams.isEmpty &&
          coursesOutcome.isOk &&
          gradesOutcome.isOk &&
          examsOutcome.isOk) {
        WebViewSyncDialogs.showSimpleNoticeDialog(
          context,
          icon: Icons.info_outline_rounded,
          iconColor: Colors.blue,
          title: '暂无已发布的教务数据',
          content: '已成功连接强智教务系统，但当前学期暂未查询到课表、成绩或考试数据（本地旧列表已同步清空）。',
          useTextButton: true,
        );
        return;
      }

      WebViewSyncDialogs.showSyncAllSummaryDialog(
        context: context,
        result: result,
        rejectedByUser: rejectedByUser,
        calibrationDetailMessage: calibRes.detailMessage,
        calibrationSuccess: calibRes.isSuccess,
        calibrationSaveFailed: calibRes.saveFailed,
        initialCoursesOutcome: coursesOutcome,
        initialGradesOutcome: gradesOutcome,
        initialExamsOutcome: examsOutcome,
        scheduleProvider: scheduleProvider,
        gradesProvider: gradesProvider,
        examsProvider: examsProvider,
      );
    } on Object catch (e) {
      DiagnosticsService.recordSyncEvent(
        triggerMode: 'syncAll',
        durationMs: stopwatch.elapsedMilliseconds,
        coursesStatus: SyncModuleStatus.error,
        gradesStatus: SyncModuleStatus.error,
        examsStatus: SyncModuleStatus.error,
        coursesError: e,
        gradesError: e,
        examsError: e,
      );
      _handleSyncFailure(context, '全量同步异常', e);
    } finally {
      _setSyncingState(false, null);
    }
  }

  /// 自动识别当前网页并执行对应专项同步
  Future<void> syncCurrentPage() async {
    final context = getContext();
    if (_rejectIfSyncInFlight(context)) return;

    final dest = NavDestination.fromUrl(adapter.currentUrl);
    switch (dest) {
      case NavDestination.timetable:
        await syncSchedule();
      case NavDestination.grades:
        await syncGrades();
      case NavDestination.exams:
        await syncExams();
      case NavDestination.home:
      case NavDestination.other:
        WebViewSyncDialogs.showSmartRouteHintDialog(
          context,
          dest: dest,
          onTriggerSyncAll: () => unawaited(syncAll()),
        );
    }
  }

  /// 执行一键解析并同步课表
  Future<void> syncSchedule() async {
    final context = getContext();
    if (!_canStartSync(context)) return;

    final scheduleProvider = context.read<ScheduleProvider>();
    _setSyncingState(true, '正在提取课表数据...');
    final stopwatch = Stopwatch()..start();

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

      DiagnosticsService.recordSyncEvent(
        triggerMode: 'courses',
        durationMs: stopwatch.elapsedMilliseconds,
        coursesStatus: syncRes.status,
        coursesError: syncRes.error,
      );

      if (_isDisposed || !context.mounted) return;

      if (syncRes.status == SyncModuleStatus.ok || syncRes.courses.isNotEmpty ||
          syncRes.status == SyncModuleStatus.empty) {
        final bool isOkCourses =
            syncRes.status == SyncModuleStatus.ok || syncRes.courses.isNotEmpty;
        final prepCalib = await _prepareWeek(
          scheduleProvider,
          detectedWeek: syncRes.detectedWeek,
          detectedSemester: syncRes.detectedSemester,
          detectedStart: syncRes.detectedSemesterStart,
        );
        if (_isDisposed || !context.mounted) return;

        if (prepCalib.rejectedByUser) {
          WebViewSyncDialogs.showSimpleNoticeDialog(
            context,
            icon: Icons.info_outline,
            iconColor: Colors.orange,
            title: '已取消课表更新',
            content: '已取消更新：已保持原课表与原学期基准不变',
          );
          return;
        }

        final atomic =
            await WebViewSyncCalibrationHelper.persistCoursesAndCalibrationAtomic(
          scheduleProvider,
          persistSafely: _persistSafely,
          writeCourses: () => scheduleProvider.updateCourses(
            isOkCourses ? syncRes.courses : const [],
          ),
          pendingDecision: prepCalib.pendingDecision,
          preparedDetail: prepCalib.detailMessage,
          preparedSuccess: prepCalib.isSuccess,
          rejectedByUser: false,
          isDisposed: () => _isDisposed,
        );
        if (_isDisposed || !context.mounted) return;

        if (!atomic.coursesOutcome.isOk) {
          WebViewSyncDialogs.showPersistErrorDialog(
            context,
            '课表',
            atomic.coursesOutcome,
            onRetrySyncTime: () => scheduleProvider
                .retrySaveSyncTime(atomic.coursesOutcome.pendingSyncTime),
          );
          return;
        }
        if (isOkCourses) {
          WebViewSyncDialogs.showModuleSuccessDialog(
            context,
            title: '课表同步成功',
            content: '成功解析并导入 ${syncRes.courses.length} 门课程！'
                '${atomic.calibRes.detailMessage != null ? "\n${atomic.calibRes.detailMessage}" : ""}',
            returnLabel: '返回课表查看',
          );
        } else {
          WebViewSyncDialogs.showSimpleNoticeDialog(
            context,
            icon: Icons.info_outline,
            iconColor: Colors.blue,
            title: '当前学期暂无课表',
            content: '强智教务系统显示当前学期暂未排课或课表为空（本地旧课表已同步清空）。',
          );
        }
      } else if (syncRes.status == SyncModuleStatus.notLoggedIn) {
        WebViewSyncDialogs.showSimpleNoticeDialog(
          context,
          icon: Icons.lock_clock_rounded,
          iconColor: Colors.orange,
          title: '未登录统一认证',
          content: '检测到统一身份认证尚未登录（已保留本地历史课表缓存），请登录后再试。',
        );
      } else {
        WebViewSyncDialogs.showMissingTableDialog(
          context,
          title: '未检测到课表',
          content:
              '当前页面未识别到课程表格 (table#timetable 或 table#kbtable)（已保留本地历史课表缓存）。\n\n'
              '操作提示：\n'
              '1. 请先在下方网页中完成统一身份认证登录；\n'
              '2. 登录成功后，点击上方导航条中的【我的课表】按钮；\n'
              '3. 待课表页面完整加载后，再次点击【同步当前课表】！\n'
              '${syncRes.error != null ? "详细原因: ${syncRes.error}" : ""}',
          navigateLabel: '前往我的课表',
          onNavigate: () =>
              unawaited(adapter.navigateTo(WebViewConstants.timetableUrl)),
        );
      }
    } on Object catch (e) {
      DiagnosticsService.recordSyncEvent(
        triggerMode: 'courses',
        durationMs: stopwatch.elapsedMilliseconds,
        coursesStatus: SyncModuleStatus.error,
        coursesError: e,
      );
      _handleSyncFailure(context, '课表解析异常', e);
    } finally {
      _setSyncingState(false, null);
    }
  }

  /// 执行一键解析并同步成绩
  Future<void> syncGrades() async {
    final context = getContext();
    if (!_canStartSync(context)) return;

    final gradesProvider = context.read<GradesProvider>();
    _setSyncingState(true, '正在提取成绩数据...');
    final stopwatch = Stopwatch()..start();

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

      DiagnosticsService.recordSyncEvent(
        triggerMode: 'grades',
        durationMs: stopwatch.elapsedMilliseconds,
        gradesStatus: result.status,
        gradesError: result.error,
      );

      if (_isDisposed || !context.mounted) return;

      if (result.status == SyncModuleStatus.ok || result.grades.isNotEmpty) {
        final persistOutcome =
            await _persistSafely(() => gradesProvider.updateGrades(result.grades));
        if (_isDisposed || !context.mounted) return;
        if (!persistOutcome.isOk) {
          WebViewSyncDialogs.showPersistErrorDialog(
            context,
            '学业成绩',
            persistOutcome,
            onRetrySyncTime: () =>
                gradesProvider.retrySaveSyncTime(persistOutcome.pendingSyncTime),
          );
          return;
        }
        final summary = gradesProvider.overallSummary;
        WebViewSyncDialogs.showModuleSuccessDialog(
          context,
          title: '成绩同步成功',
          content: '成功导入 ${result.grades.length} 门课程成绩！\n'
              '平均 GPA: ${summary?.averageGpa ?? '-'}\n'
              '总修学分: ${summary?.totalCredits ?? '-'}',
          returnLabel: '返回查看成绩',
        );
      } else if (result.status == SyncModuleStatus.empty) {
        WebViewSyncDialogs.showSimpleNoticeDialog(
          context,
          icon: Icons.info_outline,
          iconColor: Colors.blue,
          title: '当前页面暂无成绩',
          content:
              '当前查询页面暂未显示任何已发布成绩（为防止网页学期筛选误删过往学期记录，已保留本地历史成绩缓存；如需全量校准请点击【一键同步全部】）。',
        );
      } else if (result.status == SyncModuleStatus.notLoggedIn) {
        WebViewSyncDialogs.showSimpleNoticeDialog(
          context,
          icon: Icons.lock_clock_rounded,
          iconColor: Colors.orange,
          title: '未登录统一认证',
          content: '检测到统一身份认证尚未登录（已保留本地历史成绩缓存），请登录后再试。',
        );
      } else {
        WebViewSyncDialogs.showMissingTableDialog(
          context,
          title: '未检测到成绩表格',
          content: '当前页面未识别到成绩表格（已保留本地历史成绩缓存）。\n\n'
              '操作提示：\n'
              '请先点击上方快捷栏中的【成绩查询】按钮，跳转至成绩列表页后再执行同步。\n'
              '${result.error != null ? "详细原因: ${result.error}" : ""}',
          navigateLabel: '前往成绩查询',
          onNavigate: () =>
              unawaited(adapter.navigateTo(WebViewConstants.gradesUrl)),
        );
      }
    } on Object catch (e) {
      DiagnosticsService.recordSyncEvent(
        triggerMode: 'grades',
        durationMs: stopwatch.elapsedMilliseconds,
        gradesStatus: SyncModuleStatus.error,
        gradesError: e,
      );
      _handleSyncFailure(context, '成绩解析异常', e);
    } finally {
      _setSyncingState(false, null);
    }
  }

  /// 执行一键解析并同步考试安排
  Future<void> syncExams() async {
    final context = getContext();
    if (!_canStartSync(context)) return;

    final examsProvider = context.read<ExamsProvider>();
    _setSyncingState(true, '正在提取考试安排...');
    final stopwatch = Stopwatch()..start();

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

      DiagnosticsService.recordSyncEvent(
        triggerMode: 'exams',
        durationMs: stopwatch.elapsedMilliseconds,
        examsStatus: result.status,
        examsError: result.error,
      );

      if (_isDisposed || !context.mounted) return;

      if (result.status == SyncModuleStatus.ok || result.exams.isNotEmpty) {
        final persistOutcome =
            await _persistSafely(() => examsProvider.updateExams(result.exams));
        if (_isDisposed || !context.mounted) return;
        if (!persistOutcome.isOk) {
          WebViewSyncDialogs.showPersistErrorDialog(
            context,
            '考试日程',
            persistOutcome,
            onRetrySyncTime: () =>
                examsProvider.retrySaveSyncTime(persistOutcome.pendingSyncTime),
          );
          return;
        }
        WebViewSyncDialogs.showModuleSuccessDialog(
          context,
          title: '考试日程同步成功',
          content: '成功解析导入 ${result.exams.length} 门考试日程！已自动提取考试时间与考场教室。',
          returnLabel: '返回查看考试',
        );
      } else if (result.status == SyncModuleStatus.empty) {
        final persistOutcome =
            await _persistSafely(() => examsProvider.updateExams(const []));
        if (_isDisposed || !context.mounted) return;
        if (!persistOutcome.isOk) {
          WebViewSyncDialogs.showPersistErrorDialog(
            context,
            '考试日程',
            persistOutcome,
            onRetrySyncTime: () =>
                examsProvider.retrySaveSyncTime(persistOutcome.pendingSyncTime),
          );
          return;
        }
        WebViewSyncDialogs.showSimpleNoticeDialog(
          context,
          icon: Icons.info_outline,
          iconColor: Colors.blue,
          title: '当前暂无考试',
          content: '强智教务系统显示当前学期暂未安排期末考试（本地旧考试日程已同步清空）。',
        );
      } else if (result.status == SyncModuleStatus.notLoggedIn) {
        WebViewSyncDialogs.showSimpleNoticeDialog(
          context,
          icon: Icons.lock_clock_rounded,
          iconColor: Colors.orange,
          title: '未登录统一认证',
          content: '检测到统一身份认证尚未登录（已保留本地历史考试缓存），请登录后再试。',
        );
      } else {
        WebViewSyncDialogs.showMissingTableDialog(
          context,
          title: '未检测到考试表格',
          content: '当前页面未识别到考试安排数据（已保留本地历史考试缓存）。\n\n'
              '操作提示：\n'
              '请先点击上方快捷栏中的【考试安排】按钮，跳转至考试查询页后再执行同步。\n'
              '${result.error != null ? "详细原因: ${result.error}" : ""}',
          navigateLabel: '前往考试安排',
          onNavigate: () =>
              unawaited(adapter.navigateTo(WebViewConstants.examsUrl)),
        );
      }
    } on Object catch (e) {
      DiagnosticsService.recordSyncEvent(
        triggerMode: 'exams',
        durationMs: stopwatch.elapsedMilliseconds,
        examsStatus: SyncModuleStatus.error,
        examsError: e,
      );
      _handleSyncFailure(context, '考试解析异常', e);
    } finally {
      _setSyncingState(false, null);
    }
  }
}
