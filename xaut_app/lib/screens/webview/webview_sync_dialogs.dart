import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import '../../providers/exams_provider.dart';
import '../../providers/grades_provider.dart';
import '../../providers/schedule_provider.dart';
import '../../services/parser_service.dart';
import 'webview_constants.dart';

/// 本地持久化结果与局部状态（支持“数据已存盘但同步时间失败”与回滚文案覆盖）
class SyncPersistOutcome {
  final String? errorCategory;
  final bool dataSavedOnly;
  final DateTime? pendingSyncTime;
  final String? overrideMessage;

  const SyncPersistOutcome.success()
      : errorCategory = null,
        dataSavedOnly = false,
        pendingSyncTime = null,
        overrideMessage = null;

  const SyncPersistOutcome.partialSyncTime({
    required String this.errorCategory,
    this.pendingSyncTime,
  })  : dataSavedOnly = true,
        overrideMessage = null;

  const SyncPersistOutcome.failed(
    String this.errorCategory, {
    this.overrideMessage,
  })  : dataSavedOnly = false,
        pendingSyncTime = null;

  bool get isOk => errorCategory == null;
}

/// 教务同步模块状态弹窗与交互提示 UI 呈现器
abstract final class WebViewSyncDialogs {
  static Future<bool> confirmSemesterCalibrationOverrideDialog(
    BuildContext context,
    SemesterCalibrationDecision decision,
  ) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            icon: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange,
              size: 36,
            ),
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

  static void showPersistErrorDialog(
    BuildContext context,
    String moduleTitle,
    SyncPersistOutcome outcome, {
    Future<bool> Function()? onRetrySyncTime,
  }) {
    if (outcome.dataSavedOnly) {
      bool isRetrying = false;
      String? retryStatus;
      unawaited(
        showDialog<void>(
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
        ),
      );
      return;
    }

    final bool hasMismatchWarning =
        outcome.errorCategory == 'calibration_rollback_failed' ||
            outcome.errorCategory == 'calibration_rollback_incomplete';
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(
            hasMismatchWarning
                ? Icons.warning_amber_rounded
                : Icons.error_outline_rounded,
            color: hasMismatchWarning ? Colors.orange : Colors.red,
            size: 36,
          ),
          title: Text(
            hasMismatchWarning
                ? '$moduleTitle与基准未完全一致'
                : (outcome.overrideMessage != null
                    ? '$moduleTitle同步已回滚'
                    : '$moduleTitle本地保存失败'),
          ),
          content: Text(
            outcome.overrideMessage ??
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
      ),
    );
  }

  static String formatModulePersistDetail({
    required SyncPersistOutcome outcome,
    required SyncModuleStatus status,
    required String okSummary,
    required String emptySummary,
    required String retainLabel,
    required String notLoggedInDetail,
    required String errorDetail,
  }) {
    if (!outcome.isOk) {
      if (outcome.overrideMessage != null) {
        return outcome.overrideMessage!;
      }
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

  static void showSimpleNoticeDialog(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String content,
    bool useTextButton = false,
  }) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(icon, color: iconColor),
              const SizedBox(width: 8),
              Expanded(child: Text(title)),
            ],
          ),
          content: Text(content),
          actions: [
            if (useTextButton)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('我知道了'),
              )
            else
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('我知道了'),
              ),
          ],
        ),
      ),
    );
  }

  static void showSyncAllNotLoggedInDialog(BuildContext context) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.lock_clock_rounded,
            color: Colors.orange,
            size: 36,
          ),
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
      ),
    );
  }

  static void showSmartRouteHintDialog(
    BuildContext context, {
    required NavDestination dest,
    required VoidCallback onTriggerSyncAll,
  }) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.blue),
              SizedBox(width: 8),
              Expanded(child: Text('智能识别提示')),
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
                onTriggerSyncAll();
              },
              child: const Text('一键同步全部'),
            ),
          ],
        ),
      ),
    );
  }

  static void showModuleSuccessDialog(
    BuildContext context, {
    required String title,
    required String content,
    required String returnLabel,
  }) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(child: Text(title)),
            ],
          ),
          content: Text(content),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                if (context.mounted) {
                  unawaited(Navigator.of(context).maybePop());
                }
              },
              child: Text(returnLabel),
            ),
          ],
        ),
      ),
    );
  }

  static void showMissingTableDialog(
    BuildContext context, {
    required String title,
    required String content,
    required String navigateLabel,
    required VoidCallback onNavigate,
  }) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(child: Text(title)),
            ],
          ),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('我知道了'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                onNavigate();
              },
              child: Text(navigateLabel),
            ),
          ],
        ),
      ),
    );
  }

  static void showSyncAllSummaryDialog({
    required BuildContext context,
    required SyncAllResult result,
    required bool rejectedByUser,
    required String? calibrationDetailMessage,
    required bool calibrationSuccess,
    required bool calibrationSaveFailed,
    required SyncPersistOutcome initialCoursesOutcome,
    required SyncPersistOutcome initialGradesOutcome,
    required SyncPersistOutcome initialExamsOutcome,
    required ScheduleProvider scheduleProvider,
    required GradesProvider gradesProvider,
    required ExamsProvider examsProvider,
  }) {
    var coursesOutcome = initialCoursesOutcome;
    var gradesOutcome = initialGradesOutcome;
    var examsOutcome = initialExamsOutcome;

    final String weekDetail = rejectedByUser
        ? '已保持原学期基准不变'
        : (calibrationDetailMessage ?? '未识别到顶栏周次，可在课表页手动校准开学日');

    bool isRetryingSyncTimes = false;
    String? syncTimeRetryNote;

    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            final String coursesDetail = rejectedByUser
                ? '已按您的选择保留原课表与原学期基准'
                : formatModulePersistDetail(
                    outcome: coursesOutcome,
                    status: result.statusCourses,
                    okSummary: '成功导入 ${result.courses.length} 门课程',
                    emptySummary: '当前学期暂无课表数据（已清空旧缓存）',
                    retainLabel: '课表',
                    notLoggedInDetail: '未登录统一认证（已保留本地历史缓存）',
                    errorDetail:
                        '课表解析失败${result.errorCourses != null ? " (${result.errorCourses})" : " (页面可能已改版)"}（已保留本地历史缓存）',
                  );
            final String gradesDetail = formatModulePersistDetail(
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
            final String examsDetail = formatModulePersistDetail(
              outcome: examsOutcome,
              status: result.statusExams,
              okSummary: '成功导入 ${result.exams.length} 门考试安排',
              emptySummary: '当前学期暂无考试安排（已清空旧缓存）',
              retainLabel: '考试',
              notLoggedInDetail: '未登录统一认证（已保留本地历史缓存）',
              errorDetail:
                  '考试解析失败${result.errorExams != null ? " (${result.errorExams})" : " (页面可能已改版)"}（已保留本地历史缓存）',
            );

            final bool allPersistOk = coursesOutcome.isOk &&
                gradesOutcome.isOk &&
                examsOutcome.isOk &&
                !calibrationSaveFailed;
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
                  buildSyncResultRow(
                    context: ctx,
                    icon: Icons.calendar_month,
                    title: '课表数据',
                    detail: coursesDetail,
                    isSuccess: !rejectedByUser &&
                        coursesOutcome.isOk &&
                        result.statusCourses.isOk,
                  ),
                  const SizedBox(height: 10),
                  buildSyncResultRow(
                    context: ctx,
                    icon: Icons.today_rounded,
                    title: '教学周校准',
                    detail: weekDetail,
                    isSuccess: calibrationSuccess,
                  ),
                  const SizedBox(height: 10),
                  buildSyncResultRow(
                    context: ctx,
                    icon: Icons.grade,
                    title: '学业成绩',
                    detail: gradesDetail,
                    isSuccess: gradesOutcome.isOk && result.statusGrades.isOk,
                  ),
                  const SizedBox(height: 10),
                  buildSyncResultRow(
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
                            color: hasRetryableSyncTime
                                ? Colors.orange
                                : Colors.green,
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
                                coursesOutcome =
                                    const SyncPersistOutcome.success();
                              }
                            }
                            if (gradesOutcome.dataSavedOnly) {
                              final ok = await gradesProvider.retrySaveSyncTime(
                                gradesOutcome.pendingSyncTime,
                              );
                              if (ok) {
                                gradesOutcome =
                                    const SyncPersistOutcome.success();
                              }
                            }
                            if (examsOutcome.dataSavedOnly) {
                              final ok = await examsProvider.retrySaveSyncTime(
                                examsOutcome.pendingSyncTime,
                              );
                              if (ok) {
                                examsOutcome =
                                    const SyncPersistOutcome.success();
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
                    if (context.mounted) {
                      unawaited(Navigator.of(context).maybePop());
                    }
                  },
                  child: const Text('返回主页查看'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static Widget buildSyncResultRow({
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
