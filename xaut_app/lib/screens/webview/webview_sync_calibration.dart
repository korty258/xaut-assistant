import 'package:flutter/material.dart';
import '../../providers/schedule_provider.dart';
import 'webview_sync_dialogs.dart';

typedef PreparedCalibration = ({
  SemesterCalibrationDecision? pendingDecision,
  String? detailMessage,
  bool rejectedByUser,
  bool isSuccess,
});

typedef CalibrationCommitResult = ({
  String? detailMessage,
  bool isSuccess,
  bool saveFailed,
  bool calibrationRollbackFailed,
});

/// 课表与教学周基准两阶段提交及跨模块原子回滚辅助器
abstract final class WebViewSyncCalibrationHelper {
  /// 阶段 1：评估并确认识别到的教学周或开学基准日（只做判定与用户确认，不提前改写磁盘或内存状态）
  static Future<PreparedCalibration> prepareWeekCalibration(
    ScheduleProvider scheduleProvider, {
    required BuildContext Function() getContext,
    required bool Function() isDisposed,
    required Future<bool> Function(SemesterCalibrationDecision decision)?
        confirmOverride,
    int? detectedWeek,
    String? detectedSemester,
    DateTime? detectedStart,
  }) async {
    final decision = scheduleProvider.evaluateSemesterCalibration(
      detectedWeek: detectedWeek,
      detectedSemester: detectedSemester,
      detectedStart: detectedStart,
    );

    if (!decision.hasUpdate) {
      if (decision.candidateMonday != null && scheduleProvider.hasSemesterStart) {
        return (
          pendingDecision: null,
          detailMessage: '当前第 ${scheduleProvider.actualCurrentWeek} 周基准一致，无需变更',
          rejectedByUser: false,
          isSuccess: true,
        );
      }
      return (
        pendingDecision: null,
        detailMessage: null,
        rejectedByUser: false,
        isSuccess: false,
      );
    }

    if (decision.requiresConfirmation) {
      bool confirmed = false;
      if (confirmOverride != null) {
        confirmed = await confirmOverride(decision);
      } else {
        final context = getContext();
        if (isDisposed() || !context.mounted) {
          return (
            pendingDecision: null,
            detailMessage: '已保持原学期基准不变',
            rejectedByUser: true,
            isSuccess: false,
          );
        }
        confirmed =
            await WebViewSyncDialogs.confirmSemesterCalibrationOverrideDialog(
          context,
          decision,
        );
      }

      if (isDisposed() || !confirmed) {
        return (
          pendingDecision: null,
          detailMessage: '已保持原学期基准不变',
          rejectedByUser: true,
          isSuccess: false,
        );
      }
    }

    return (
      pendingDecision: decision,
      detailMessage: null,
      rejectedByUser: false,
      isSuccess: false,
    );
  }

  /// 阶段 2：仅在课表持久化成功后再提交学期与周次基准更新，保证两者原子一致
  static Future<CalibrationCommitResult> commitPendingWeekCalibration(
    ScheduleProvider scheduleProvider, {
    required SemesterCalibrationDecision? pendingDecision,
    required String? preparedDetail,
    required bool preparedSuccess,
    required bool rejectedByUser,
    required bool coursesPersisted,
  }) async {
    if (rejectedByUser) {
      return (
        detailMessage: '已保持原学期基准不变',
        isSuccess: false,
        saveFailed: false,
        calibrationRollbackFailed: false,
      );
    }
    if (pendingDecision == null) {
      return (
        detailMessage: preparedDetail,
        isSuccess: preparedSuccess,
        saveFailed: false,
        calibrationRollbackFailed: false,
      );
    }
    if (!coursesPersisted) {
      return (
        detailMessage: '由于课表保存失败，已保持原学期基准不变',
        isSuccess: false,
        saveFailed: false,
        calibrationRollbackFailed: false,
      );
    }

    try {
      if (pendingDecision.candidateMonday != null) {
        final ok = await scheduleProvider.setSemesterStartDate(
          pendingDecision.candidateMonday!,
          semester: pendingDecision.candidateSemester.isNotEmpty
              ? pendingDecision.candidateSemester
              : null,
        );
        if (!ok) {
          final incomplete = scheduleProvider.lastCalibrationRollbackFailed;
          return (
            detailMessage: incomplete
                ? '教学周基准保存失败，且原学期基准磁盘回滚未完成，请手动重新校准'
                : '教学周基准保存失败，已保持原学期基准不变',
            isSuccess: false,
            saveFailed: true,
            calibrationRollbackFailed: incomplete,
          );
        }
        if (pendingDecision.requiresConfirmation) {
          return (
            detailMessage: '已按确认更新学期基准',
            isSuccess: true,
            saveFailed: false,
            calibrationRollbackFailed: false,
          );
        }
        final week = scheduleProvider.actualCurrentWeek;
        final monday = scheduleProvider.semesterStartDate;
        final monStr = monday != null
            ? '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}'
            : '';
        return (
          detailMessage:
              '已自动对齐第 $week 周${monStr.isNotEmpty ? " (第1周周一: $monStr)" : ""}',
          isSuccess: true,
          saveFailed: false,
          calibrationRollbackFailed: false,
        );
      } else {
        if (pendingDecision.candidateSemester.isNotEmpty) {
          final ok = await scheduleProvider
              .setSemesterNameOnly(pendingDecision.candidateSemester);
          if (!ok) {
            return (
              detailMessage: '学期名称保存失败，已保持原学期基准不变',
              isSuccess: false,
              saveFailed: true,
              calibrationRollbackFailed: false,
            );
          }
        }
        return (
          detailMessage:
              '已识别学期 ${pendingDecision.candidateSemester}，未检测到周次，请手动校准开学日',
          isSuccess: false,
          saveFailed: false,
          calibrationRollbackFailed: false,
        );
      }
    } on Object catch (_) {
      final incomplete = scheduleProvider.lastCalibrationRollbackFailed;
      return (
        detailMessage: incomplete
            ? '教学周基准保存失败，且原学期基准磁盘回滚未完成，请手动重新校准'
            : '教学周基准保存失败，已保持原学期基准不变',
        isSuccess: false,
        saveFailed: true,
        calibrationRollbackFailed: incomplete,
      );
    }
  }

  /// 原子协调写入课表与教学周基准：分别校验课表快照回滚结果与学期基准磁盘回滚结果
  static Future<({
    SyncPersistOutcome coursesOutcome,
    CalibrationCommitResult calibRes,
  })> persistCoursesAndCalibrationAtomic(
    ScheduleProvider scheduleProvider, {
    required Future<SyncPersistOutcome> Function(Future<void> Function() action)
        persistSafely,
    required Future<void> Function() writeCourses,
    required SemesterCalibrationDecision? pendingDecision,
    required String? preparedDetail,
    required bool preparedSuccess,
    required bool rejectedByUser,
    required bool Function() isDisposed,
  }) async {
    final prevCourses = scheduleProvider.courses.toList();
    final prevSyncTime = scheduleProvider.lastSyncTime;
    var coursesOutcome = await persistSafely(writeCourses);
    if (isDisposed()) {
      return (
        coursesOutcome: coursesOutcome,
        calibRes: (
          detailMessage: null,
          isSuccess: false,
          saveFailed: false,
          calibrationRollbackFailed: false,
        ),
      );
    }

    var calibRes = await commitPendingWeekCalibration(
      scheduleProvider,
      pendingDecision: pendingDecision,
      preparedDetail: preparedDetail,
      preparedSuccess: preparedSuccess,
      rejectedByUser: rejectedByUser,
      coursesPersisted: coursesOutcome.isOk || coursesOutcome.dataSavedOnly,
    );

    if (pendingDecision != null &&
        calibRes.saveFailed &&
        (coursesOutcome.isOk || coursesOutcome.dataSavedOnly)) {
      final coursesRestored = await scheduleProvider.restoreCoursesSnapshot(
        prevCourses,
        prevSyncTime: prevSyncTime,
      );
      final calibIncomplete = calibRes.calibrationRollbackFailed;
      final String msg;
      final String errCat;
      if (coursesRestored && !calibIncomplete) {
        msg = '教学周基准保存失败，已回滚保留原课表与原学期基准';
        errCat = 'calibration_rollback';
      } else if (coursesRestored && calibIncomplete) {
        msg = '教学周基准保存失败：原课表已回滚保留，但原学期名称/开学日磁盘回滚未完成，请手动重新校准';
        errCat = 'calibration_rollback_incomplete';
      } else if (!coursesRestored && calibIncomplete) {
        msg = '新课表已写入，且教学周基准保存及课表、基准磁盘回滚均未完成，请手动校准并重新同步';
        errCat = 'calibration_rollback_failed';
      } else {
        msg = '新课表已写入，但教学周基准保存失败且课表回滚未完成，请手动校准或重新同步';
        errCat = 'calibration_rollback_failed';
      }
      coursesOutcome = SyncPersistOutcome.failed(
        errCat,
        overrideMessage: msg,
      );
      calibRes = (
        detailMessage: msg,
        isSuccess: false,
        saveFailed: true,
        calibrationRollbackFailed: calibIncomplete,
      );
    }

    return (coursesOutcome: coursesOutcome, calibRes: calibRes);
  }
}
