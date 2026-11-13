import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/schedule_provider.dart';
import '../../providers/grades_provider.dart';
import '../../providers/exams_provider.dart';
import '../../services/diagnostics_service.dart';
import '../../services/parser_service.dart';
import '../../services/storage_service.dart';
import 'webview_constants.dart';
import 'webview_platform_adapter.dart';

class _PersistOutcome {
  final String? errorCategory;
  final bool dataSavedOnly;
  final DateTime? pendingSyncTime;

  const _PersistOutcome.success()
      : errorCategory = null,
        dataSavedOnly = false,
        pendingSyncTime = null;

  const _PersistOutcome.partialSyncTime({
    required String this.errorCategory,
    this.pendingSyncTime,
  }) : dataSavedOnly = true;

  const _PersistOutcome.failed(String this.errorCategory)
      : dataSavedOnly = false,
        pendingSyncTime = null;

  bool get isOk => errorCategory == null;
}

/// 负责调度强智教务系统跨模块同步业务流与结果弹窗
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

  Future<_PersistOutcome> _persistSafely(Future<void> Function() action) async {
    try {
      await action();
      return const _PersistOutcome.success();
    } on StorageWriteException catch (e) {
      final category = DiagnosticsService.sanitizeErrorCategory(e);
      if (e.dataSaved) {
        return _PersistOutcome.partialSyncTime(
          errorCategory: category,
          pendingSyncTime: e.pendingSyncTime,
        );
      }
      return _PersistOutcome.failed(category);
    } catch (e) {
      return _PersistOutcome.failed(
        DiagnosticsService.sanitizeErrorCategory(e),
      );
    }
  }

  void _showPersistErrorDialog(
    BuildContext context,
    String moduleTitle,
    _PersistOutcome outcome, {
    Future<bool> Function()? onRetrySyncTime,
  }) {
    if (outcome.dataSavedOnly) {
      bool isRetrying = false;
      String? retryStatus;
      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            icon: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange,
              size: 36,
            ),
            title: Text('$moduleTitle已保存，但同步时间未更新'),
            content: Text(
              '已成功抓取并加密保存新的$moduleTitle，界面展示已更新为最新数据；'
              '但写入“最近同步时间”时发生异常（${outcome.errorCategory}），同步时间仍保留上次记录。\n\n'
              '您无需重新抓取教务，可直接重试保存同步时间。'
              '${retryStatus != null ? "\n\n$retryStatus" : ""}',
            ),
            actions: [
              TextButton(
                onPressed: isRetrying ? null : () => Navigator.of(ctx).pop(),
                child: const Text('稍后处理'),
              ),
              if (onRetrySyncTime != null)
                FilledButton(
                  onPressed: isRetrying
                      ? null
                      : () async {
                          setDialogState(() {
                            isRetrying = true;
                            retryStatus = null;
                          });
                          final ok = await onRetrySyncTime();
                          if (!ctx.mounted) return;
                          if (ok) {
                            Navigator.of(ctx).pop();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('$moduleTitle同步时间已更新')),
                              );
                            }
                          } else {
                            setDialogState(() {
                              isRetrying = false;
                              retryStatus = '同步时间写入仍然失败，请稍后重试。';
                            });
                          }
                        },
                  child: Text(isRetrying ? '正在重试...' : '重试写入时间'),
                ),
            ],
          ),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.error_outline_rounded, color: Colors.red, size: 36),
        title: Text('$moduleTitle本地保存失败'),
        content: Text(
          '已成功抓取教务数据，但在加密写入本地存储时发生异常（${outcome.errorCategory}）。\n\n'
          '为保障数据安全，本次未覆盖界面展示，已保留您原有的本地数据与同步时间。请重启应用或检查设备存储权限后重试。',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  String _formatModulePersistDetail({
    required _PersistOutcome outcome,
    required SyncModuleStatus status,
    required String okSummary,
    required String emptySummary,
    required String retainLabel,
    required String notLoggedInDetail,
    required String errorDetail,
  }) {
    if (!outcome.isOk) {
      if (outcome.dataSavedOnly) {
        final base = status.isOk ? okSummary : emptySummary;
        return '$base，但同步时间写入失败 (${outcome.errorCategory})（已保留原同步时间）';
      }
      return '本地加密保存失败 (${outcome.errorCategory})（已保留原$retainLabel与同步时间）';
    }
    switch (status) {
      case SyncModuleStatus.ok:
        return okSummary;
      case SyncModuleStatus.empty:
        return emptySummary;
      case SyncModuleStatus.notLoggedIn:
        return notLoggedInDetail;
      case SyncModuleStatus.error:
        return errorDetail;
    }
  }

  void _setSyncingState(bool syncing, String? message) {
    _isSyncInFlight = syncing;
    if (_isDisposed) return;
    isSyncingNotifier.value = syncing;
    onStateChanged(syncing, message);
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
  Future<({String? detailMessage, bool rejectedByUser, bool isSuccess})>
      _applyDetectedWeekCalibration(
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

    if (!decision.hasUpdate) {
      if (decision.candidateMonday != null && scheduleProvider.hasSemesterStart) {
        return (
          detailMessage: '当前第 ${scheduleProvider.actualCurrentWeek} 周基准一致，无需变更',
          rejectedByUser: false,
          isSuccess: true,
        );
      }
      return (detailMessage: null, rejectedByUser: false, isSuccess: false);
    }

    if (!decision.requiresConfirmation) {
      if (decision.candidateMonday != null) {
        await scheduleProvider.setSemesterStartDate(
          decision.candidateMonday!,
          semester: decision.candidateSemester.isNotEmpty
              ? decision.candidateSemester
              : null,
        );
        final week = scheduleProvider.actualCurrentWeek;
        final monday = scheduleProvider.semesterStartDate;
        final monStr = monday != null
            ? '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}'
            : '';
        return (
          detailMessage: '已自动对齐第 $week 周${monStr.isNotEmpty ? " (第1周周一: $monStr)" : ""}',
          rejectedByUser: false,
          isSuccess: true,
        );
      } else {
        // 关键修复：无基准日期（未识别到周次或开学日，仅识别到学期名称）
        if (decision.candidateSemester.isNotEmpty) {
          await scheduleProvider.setSemesterNameOnly(decision.candidateSemester);
        }
        return (
          detailMessage: '已识别学期 ${decision.candidateSemester}，未检测到周次，请手动校准开学日',
          rejectedByUser: false,
          isSuccess: false,
        );
      }
    }

    // 触发了需要确认的冲突或大幅跳变
    bool confirmed = false;
    if (confirmSemesterCalibrationOverride != null) {
      confirmed = await confirmSemesterCalibrationOverride!(decision);
    } else {
      final context = getContext();
      if (_isDisposed || !context.mounted) {
        return (detailMessage: '已保持原学期基准不变', rejectedByUser: true, isSuccess: false);
      }
      confirmed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.warning_amber_rounded,
                  color: Colors.orange, size: 36),
              title: const Text('检测到学期基准变更或冲突'),
              content: Text(
                '${decision.conflictReason ?? "教务系统返回的学期或开学周与当前本地设置存在偏差。"}\n\n'
                '若当前同步包含新课表数据：\n'
                '• 选择【保持原设置】：将同时保留原课表与原学期基准，避免新课表与旧学期日期错位混用；\n'
                '• 选择【更新学期基准】：将一并应用新课表与新学期基准。',
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

    if (_isDisposed) {
      return (detailMessage: '已保持原学期基准不变', rejectedByUser: true, isSuccess: false);
    }

    if (confirmed) {
      if (decision.candidateMonday != null) {
        await scheduleProvider.setSemesterStartDate(
          decision.candidateMonday!,
          semester: decision.candidateSemester.isNotEmpty
              ? decision.candidateSemester
              : null,
        );
      } else if (decision.candidateSemester.isNotEmpty) {
        await scheduleProvider.setSemesterNameOnly(decision.candidateSemester);
      }
      return (detailMessage: '已按确认更新学期基准', rejectedByUser: false, isSuccess: true);
    } else {
      return (detailMessage: '已保持原学期基准不变', rejectedByUser: true, isSuccess: false);
    }
  }

  /// 执行一键全量同步（同时同步 课表 + 成绩 + 考试 3大模块，消除 UI 冻结）
  Future<void> syncAll() async {
    final context = getContext();
    if (_isSyncInFlight) {
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
      return;
    }

    if (isSyncCoolingDown()) return;

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
        onProgress: (msg) {
          _setSyncingState(true, msg);
        },
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

      // 0. 当课表模块有效返回（ok 或 empty）时，优先在写入本地课表前完成学期与周次校准确认
      ({String? detailMessage, bool rejectedByUser, bool isSuccess}) calibRes = (
        detailMessage: null,
        rejectedByUser: false,
        isSuccess: false,
      );
      if (result.statusCourses.isOk || result.statusCourses.isEmpty) {
        calibRes = await _applyDetectedWeekCalibration(
          scheduleProvider,
          detectedWeek: result.detectedWeek,
          detectedSemester: result.detectedSemester,
          detectedStart: result.detectedSemesterStart,
        );
        if (_isDisposed || !context.mounted) return;
      }
      final bool rejectedByUser = calibRes.rejectedByUser;

      // 1. 课表：仅当用户未拒绝更新基准时，才写入新课表或空课表（单轮执行，避免全量空数据分支重复清空）
      var coursesOutcome = const _PersistOutcome.success();
      if (!rejectedByUser) {
        if (result.statusCourses.isOk) {
          coursesOutcome =
              await _persistSafely(() => scheduleProvider.updateCourses(result.courses));
        } else if (result.statusCourses.isEmpty) {
          coursesOutcome =
              await _persistSafely(() => scheduleProvider.updateCourses(const []));
        }
      }
      // notLoggedIn 或 error 严格保留原有课表缓存

      // 2. 成绩
      var gradesOutcome = const _PersistOutcome.success();
      if (result.statusGrades.isOk) {
        gradesOutcome =
            await _persistSafely(() => gradesProvider.updateGrades(result.grades));
      } else if (result.statusGrades.isEmpty) {
        gradesOutcome =
            await _persistSafely(() => gradesProvider.updateGrades(const []));
      }
      // notLoggedIn 或 error 严格保留原有成绩缓存

      // 3. 考试
      var examsOutcome = const _PersistOutcome.success();
      if (result.statusExams.isOk) {
        examsOutcome =
            await _persistSafely(() => examsProvider.updateExams(result.exams));
      } else if (result.statusExams.isEmpty) {
        examsOutcome =
            await _persistSafely(() => examsProvider.updateExams(const []));
      }
      // notLoggedIn 或 error 严格保留原有考试缓存

      if (_isDisposed || !context.mounted) return;

      // 全部空数据且三模块均完全写入成功时，展示简洁空数据弹窗
      if (!rejectedByUser &&
          result.statusCourses.isEmpty &&
          result.statusGrades.isEmpty &&
          result.statusExams.isEmpty &&
          coursesOutcome.isOk &&
          gradesOutcome.isOk &&
          examsOutcome.isOk) {
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

      final String weekDetail = rejectedByUser
          ? '已保持原学期基准不变'
          : (calibRes.detailMessage ?? '未识别到顶栏周次，可在课表页手动校准开学日');

      bool isRetryingSyncTimes = false;
      String? syncTimeRetryNote;

      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            final String coursesDetail = rejectedByUser
                ? '已按您的选择保留原课表与原学期基准'
                : _formatModulePersistDetail(
                    outcome: coursesOutcome,
                    status: result.statusCourses,
                    okSummary: '成功导入 ${result.courses.length} 门课程',
                    emptySummary: '当前学期暂无课表数据（已清空旧缓存）',
                    retainLabel: '课表',
                    notLoggedInDetail: '未登录统一认证（已保留本地历史缓存）',
                    errorDetail:
                        '课表解析失败${result.errorCourses != null ? " (${result.errorCourses})" : " (页面可能已改版)"}（已保留本地历史缓存）',
                  );
            final String gradesDetail = _formatModulePersistDetail(
              outcome: gradesOutcome,
              status: result.statusGrades,
              okSummary:
                  '成功导入 ${result.grades.length} 门成绩 (GPA: ${gradesProvider.overallSummary?.averageGpa ?? "-"})',
              emptySummary: '当前学期暂无成绩发布（已清空旧缓存）',
              retainLabel: '成绩',
              notLoggedInDetail: '未登录统一认证（已保留本地历史缓存）',
              errorDetail:
                  '成绩解析失败${result.errorGrades != null ? " (${result.errorGrades})" : " (页面可能已改版)"}（已保留本地历史缓存）',
            );
            final String examsDetail = _formatModulePersistDetail(
              outcome: examsOutcome,
              status: result.statusExams,
              okSummary: '成功导入 ${result.exams.length} 门考试安排',
              emptySummary: '当前学期暂无考试安排（已清空旧缓存）',
              retainLabel: '考试',
              notLoggedInDetail: '未登录统一认证（已保留本地历史缓存）',
              errorDetail:
                  '考试解析失败${result.errorExams != null ? " (${result.errorExams})" : " (页面可能已改版)"}（已保留本地历史缓存）',
            );

            final bool allPersistOk =
                coursesOutcome.isOk && gradesOutcome.isOk && examsOutcome.isOk;
            final bool hasRetryableSyncTime = coursesOutcome.dataSavedOnly ||
                gradesOutcome.dataSavedOnly ||
                examsOutcome.dataSavedOnly;

            return AlertDialog(
              icon: Icon(
                allPersistOk
                    ? Icons.cloud_done_rounded
                    : Icons.warning_amber_rounded,
                color: allPersistOk ? Colors.green : Colors.orange,
                size: 36,
              ),
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
                    isSuccess: !rejectedByUser &&
                        coursesOutcome.isOk &&
                        result.statusCourses.isOk,
                  ),
                  const SizedBox(height: 10),
                  _buildSyncResultRow(
                    context: ctx,
                    icon: Icons.today_rounded,
                    title: '教学周校准',
                    detail: weekDetail,
                    isSuccess: calibRes.isSuccess,
                  ),
                  const SizedBox(height: 10),
                  _buildSyncResultRow(
                    context: ctx,
                    icon: Icons.grade,
                    title: '学业成绩',
                    detail: gradesDetail,
                    isSuccess: gradesOutcome.isOk && result.statusGrades.isOk,
                  ),
                  const SizedBox(height: 10),
                  _buildSyncResultRow(
                    context: ctx,
                    icon: Icons.assignment,
                    title: '考试日程',
                    detail: examsDetail,
                    isSuccess: examsOutcome.isOk && result.statusExams.isOk,
                  ),
                  if (syncTimeRetryNote != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      syncTimeRetryNote!,
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: hasRetryableSyncTime ? Colors.orange : Colors.green,
                          ),
                    ),
                  ],
                ],
              ),
              actions: [
                if (hasRetryableSyncTime)
                  TextButton(
                    onPressed: isRetryingSyncTimes
                        ? null
                        : () async {
                            setDialogState(() {
                              isRetryingSyncTimes = true;
                              syncTimeRetryNote = null;
                            });
                            if (coursesOutcome.dataSavedOnly) {
                              final ok = await scheduleProvider.retrySaveSyncTime(
                                coursesOutcome.pendingSyncTime,
                              );
                              if (ok) {
                                coursesOutcome = const _PersistOutcome.success();
                              }
                            }
                            if (gradesOutcome.dataSavedOnly) {
                              final ok = await gradesProvider.retrySaveSyncTime(
                                gradesOutcome.pendingSyncTime,
                              );
                              if (ok) {
                                gradesOutcome = const _PersistOutcome.success();
                              }
                            }
                            if (examsOutcome.dataSavedOnly) {
                              final ok = await examsProvider.retrySaveSyncTime(
                                examsOutcome.pendingSyncTime,
                              );
                              if (ok) {
                                examsOutcome = const _PersistOutcome.success();
                              }
                            }
                            if (!ctx.mounted) return;
                            final stillPending = coursesOutcome.dataSavedOnly ||
                                gradesOutcome.dataSavedOnly ||
                                examsOutcome.dataSavedOnly;
                            setDialogState(() {
                              isRetryingSyncTimes = false;
                              syncTimeRetryNote = stillPending
                                  ? '部分同步时间重试仍未成功，已更新成功项的时间记录。'
                                  : '同步时间已全部补充更新。';
                            });
                          },
                    child: Text(isRetryingSyncTimes ? '正在重试...' : '重试写入时间'),
                  ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop();
                  },
                  child: const Text('返回主页查看'),
                ),
              ],
            );
          },
        ),
      );
    } catch (e) {
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
      if (_isDisposed || !context.mounted) return;
      final errStr = e.toString();
      final isCancel = errStr.contains('取消') || errStr.contains('跳转');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isCancel ? '同步已取消' : '全量同步异常: $e')),
      );
    } finally {
      _setSyncingState(false, null);
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
      return;
    }

    if (isSyncCoolingDown()) return;

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

      if (syncRes.status == SyncModuleStatus.ok || syncRes.courses.isNotEmpty) {
        // 先执行学期基准与周次校准确认，确保原子一致性
        final calibRes = await _applyDetectedWeekCalibration(
          scheduleProvider,
          detectedWeek: syncRes.detectedWeek,
          detectedSemester: syncRes.detectedSemester,
          detectedStart: syncRes.detectedSemesterStart,
        );
        if (_isDisposed || !context.mounted) return;

        if (calibRes.rejectedByUser) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.info_outline, color: Colors.orange),
              title: const Text('已取消课表更新'),
              content: const Text('已取消更新：已保持原课表与原学期基准不变'),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('我知道了'),
                ),
              ],
            ),
          );
          return;
        }

        final persistOutcome =
            await _persistSafely(() => scheduleProvider.updateCourses(syncRes.courses));
        if (_isDisposed || !context.mounted) return;
        if (!persistOutcome.isOk) {
          _showPersistErrorDialog(
            context,
            '课表',
            persistOutcome,
            onRetrySyncTime: () =>
                scheduleProvider.retrySaveSyncTime(persistOutcome.pendingSyncTime),
          );
          return;
        }
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
              '${calibRes.detailMessage != null ? "\n${calibRes.detailMessage}" : ""}',
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
        final calibRes = await _applyDetectedWeekCalibration(
          scheduleProvider,
          detectedWeek: syncRes.detectedWeek,
          detectedSemester: syncRes.detectedSemester,
          detectedStart: syncRes.detectedSemesterStart,
        );
        if (_isDisposed || !context.mounted) return;
        if (calibRes.rejectedByUser) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.info_outline, color: Colors.orange),
              title: const Text('已取消课表更新'),
              content: const Text('已取消更新：已保持原课表与原学期基准不变'),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('我知道了'),
                ),
              ],
            ),
          );
          return;
        }
        final persistOutcome =
            await _persistSafely(() => scheduleProvider.updateCourses(const []));
        if (_isDisposed || !context.mounted) return;
        if (!persistOutcome.isOk) {
          _showPersistErrorDialog(
            context,
            '课表',
            persistOutcome,
            onRetrySyncTime: () =>
                scheduleProvider.retrySaveSyncTime(persistOutcome.pendingSyncTime),
          );
          return;
        }
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
      DiagnosticsService.recordSyncEvent(
        triggerMode: 'courses',
        durationMs: stopwatch.elapsedMilliseconds,
        coursesStatus: SyncModuleStatus.error,
        coursesError: e,
      );
      if (_isDisposed || !context.mounted) return;
      final errStr = e.toString();
      final isCancel = errStr.contains('取消') || errStr.contains('跳转');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isCancel ? '同步已取消' : '课表解析异常: $e')),
      );
    } finally {
      _setSyncingState(false, null);
    }
  }

  /// 执行一键解析并同步成绩
  Future<void> syncGrades() async {
    final context = getContext();
    if (_isSyncInFlight) {
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
      return;
    }

    if (isSyncCoolingDown()) return;

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
          _showPersistErrorDialog(
            context,
            '学业成绩',
            persistOutcome,
            onRetrySyncTime: () =>
                gradesProvider.retrySaveSyncTime(persistOutcome.pendingSyncTime),
          );
          return;
        }
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
      DiagnosticsService.recordSyncEvent(
        triggerMode: 'grades',
        durationMs: stopwatch.elapsedMilliseconds,
        gradesStatus: SyncModuleStatus.error,
        gradesError: e,
      );
      if (_isDisposed || !context.mounted) return;
      final errStr = e.toString();
      final isCancel = errStr.contains('取消') || errStr.contains('跳转');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isCancel ? '同步已取消' : '成绩解析异常: $e')),
      );
    } finally {
      _setSyncingState(false, null);
    }
  }

  /// 执行一键解析并同步考试安排
  Future<void> syncExams() async {
    final context = getContext();
    if (_isSyncInFlight) {
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
      return;
    }

    if (isSyncCoolingDown()) return;

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
          _showPersistErrorDialog(
            context,
            '考试日程',
            persistOutcome,
            onRetrySyncTime: () =>
                examsProvider.retrySaveSyncTime(persistOutcome.pendingSyncTime),
          );
          return;
        }
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
        final persistOutcome =
            await _persistSafely(() => examsProvider.updateExams(const []));
        if (_isDisposed || !context.mounted) return;
        if (!persistOutcome.isOk) {
          _showPersistErrorDialog(
            context,
            '考试日程',
            persistOutcome,
            onRetrySyncTime: () =>
                examsProvider.retrySaveSyncTime(persistOutcome.pendingSyncTime),
          );
          return;
        }
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
      DiagnosticsService.recordSyncEvent(
        triggerMode: 'exams',
        durationMs: stopwatch.elapsedMilliseconds,
        examsStatus: SyncModuleStatus.error,
        examsError: e,
      );
      if (_isDisposed || !context.mounted) return;
      final errStr = e.toString();
      final isCancel = errStr.contains('取消') || errStr.contains('跳转');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isCancel ? '同步已取消' : '考试解析异常: $e')),
      );
    } finally {
      _setSyncingState(false, null);
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
